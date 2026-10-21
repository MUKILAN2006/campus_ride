import 'dart:async';
import 'dart:math';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/ride_model.dart';
import 'storage_service.dart';
import 'location_service.dart';

enum RideTrackingStage {
  idle,
  searchingDriver,
  driverAssigned,
  driverApproachingPickup,
  driverAtPickup,
  inTransitToDestination,
  completed,
  cancelled,
}

class RideTrackingUpdate {
  final RideModel ride;
  final RideTrackingStage stage;
  final LatLng driverLocation;
  final double heading;
  final int remainingMinutes;
  final String statusMessage;
  final double tripProgress; // 0.0 to 1.0

  const RideTrackingUpdate({
    required this.ride,
    required this.stage,
    required this.driverLocation,
    required this.heading,
    required this.remainingMinutes,
    required this.statusMessage,
    required this.tripProgress,
  });
}

class RideTrackingService {
  static final RideTrackingService _instance = RideTrackingService._internal();
  factory RideTrackingService() => _instance;
  RideTrackingService._internal();

  Timer? _simulationTimer;
  final StreamController<RideTrackingUpdate> _updateController =
      StreamController<RideTrackingUpdate>.broadcast();

  Stream<RideTrackingUpdate> get trackingStream => _updateController.stream;

  RideModel? _currentRide;
  RideModel? get currentRide => _currentRide;

  RideTrackingStage _currentStage = RideTrackingStage.idle;
  RideTrackingStage get currentStage => _currentStage;

  bool get isTrackingActive =>
      _currentStage != RideTrackingStage.idle &&
      _currentStage != RideTrackingStage.completed &&
      _currentStage != RideTrackingStage.cancelled;

  // Active waypoints for the driver journey
  List<LatLng> _tripWaypoints = [];
  int _currentWaypointIndex = 0;
  int _pickupWaypointIndex = 0;

  /// Starts an active tracking session for a newly booked ride.
  Future<void> startTrackingRide(RideModel ride) async {
    // Cancel any previous session
    stopTracking();

    _currentRide = ride;
    _currentStage = RideTrackingStage.searchingDriver;

    final storage = await StorageService.getInstance();
    await storage.saveActiveRide(ride);

    // Initial broadcast: searching for nearby campus driver
    _updateController.add(
      RideTrackingUpdate(
        ride: ride,
        stage: _currentStage,
        driverLocation: LatLng(ride.pickupLat ?? 37.4275, ride.pickupLng ?? -122.1697),
        heading: 0.0,
        remainingMinutes: ride.durationMins ?? 5,
        statusMessage: 'Matching with nearby campus drivers...',
        tripProgress: 0.0,
      ),
    );

    // After 2.5 seconds, driver accepts
    await Future.delayed(const Duration(milliseconds: 2500));
    if (_currentStage != RideTrackingStage.searchingDriver) return;

    // Driver starting location (slightly offset from pickup)
    final double startLat = (ride.pickupLat ?? 37.4275) + 0.0035;
    final double startLng = (ride.pickupLng ?? -122.1697) - 0.0038;
    final LatLng driverStart = LatLng(startLat, startLng);

    final pickup = LatLng(ride.pickupLat ?? 37.4275, ride.pickupLng ?? -122.1697);
    final dropoff = LatLng(ride.dropoffLat ?? 37.4330, ride.dropoffLng ?? -122.1695);

    // Generate waypoints: driver -> pickup -> dropoff
    final locService = LocationService();
    _tripWaypoints = locService.generateFullDriverTripWaypoints(driverStart, pickup, dropoff);
    _pickupWaypointIndex = 8; // Index where driver reaches pickup
    _currentWaypointIndex = 0;

    _currentStage = RideTrackingStage.driverAssigned;
    _currentRide = _currentRide!.copyWith(
      status: 'driver_assigned',
      driverLat: driverStart.latitude,
      driverLng: driverStart.longitude,
      driverName: ride.driverName ?? 'Marcus Reed',
      driverPhone: ride.driverPhone ?? '+1 (650) 555-0198',
      driverRating: ride.driverRating ?? '4.92',
      vehicleDetails: ride.vehicleDetails ?? 'Silver Toyota Camry • ABC-7892',
    );

    await storage.saveActiveRide(_currentRide!);
    await storage.updateRide(_currentRide!);

    _emitUpdate(
      stage: RideTrackingStage.driverAssigned,
      statusMessage: 'Driver assigned! ${_currentRide!.driverName} is on the way.',
      minutes: (_currentRide!.durationMins ?? 6) + 3,
      progress: 0.05,
    );

    // Start periodic location updates (every 2.5 seconds)
    _startPeriodicLocationSimulation();
  }

  void _startPeriodicLocationSimulation() {
    _simulationTimer?.cancel();
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 2400), (timer) async {
      if (_currentRide == null || _tripWaypoints.isEmpty) {
        timer.cancel();
        return;
      }

      if (_currentWaypointIndex < _tripWaypoints.length - 1) {
        _currentWaypointIndex++;
      } else {
        // Trip is finished
        timer.cancel();
        await _completeTrip();
        return;
      }

      final LatLng currentPos = _tripWaypoints[_currentWaypointIndex];
      final LatLng prevPos = _tripWaypoints[_currentWaypointIndex > 0 ? _currentWaypointIndex - 1 : 0];
      final double heading = _calculateBearing(prevPos, currentPos);

      // Determine stage
      if (_currentWaypointIndex < _pickupWaypointIndex) {
        _currentStage = RideTrackingStage.driverApproachingPickup;
        final int remainingToPickup =
            ((_pickupWaypointIndex - _currentWaypointIndex) * 0.5).ceil() + 1;

        _currentRide = _currentRide!.copyWith(
          driverLat: currentPos.latitude,
          driverLng: currentPos.longitude,
          status: 'driver_approaching',
        );

        _emitUpdate(
          stage: _currentStage,
          statusMessage: 'Driver arriving at pickup in ~$remainingToPickup min',
          minutes: remainingToPickup,
          progress: _currentWaypointIndex / _tripWaypoints.length,
          overridePos: currentPos,
          heading: heading,
        );
      } else if (_currentWaypointIndex == _pickupWaypointIndex) {
        _currentStage = RideTrackingStage.driverAtPickup;

        _currentRide = _currentRide!.copyWith(
          driverLat: currentPos.latitude,
          driverLng: currentPos.longitude,
          status: 'at_pickup',
        );

        _emitUpdate(
          stage: _currentStage,
          statusMessage: 'Driver has arrived at the pickup point! Boarding now...',
          minutes: _currentRide!.durationMins ?? 5,
          progress: _currentWaypointIndex / _tripWaypoints.length,
          overridePos: currentPos,
          heading: heading,
        );
      } else {
        _currentStage = RideTrackingStage.inTransitToDestination;
        final int remainingSteps = _tripWaypoints.length - 1 - _currentWaypointIndex;
        final int remainingMins = (remainingSteps * 0.4).ceil() + 1;

        _currentRide = _currentRide!.copyWith(
          driverLat: currentPos.latitude,
          driverLng: currentPos.longitude,
          status: 'in_progress',
        );

        _emitUpdate(
          stage: _currentStage,
          statusMessage: 'Heading to destination. ETA ~$remainingMins mins',
          minutes: remainingMins,
          progress: _currentWaypointIndex / _tripWaypoints.length,
          overridePos: currentPos,
          heading: heading,
        );
      }

      // Persist driver updated coordinates in local storage
      final storage = await StorageService.getInstance();
      await storage.saveActiveRide(_currentRide!);
    });
  }

  void _emitUpdate({
    required RideTrackingStage stage,
    required String statusMessage,
    required int minutes,
    required double progress,
    LatLng? overridePos,
    double heading = 0.0,
  }) {
    if (_currentRide == null) return;

    final LatLng driverPos = overridePos ??
        LatLng(
          _currentRide!.driverLat ?? _currentRide!.pickupLat ?? 37.4275,
          _currentRide!.driverLng ?? _currentRide!.pickupLng ?? -122.1697,
        );

    _updateController.add(
      RideTrackingUpdate(
        ride: _currentRide!,
        stage: stage,
        driverLocation: driverPos,
        heading: heading,
        remainingMinutes: minutes,
        statusMessage: statusMessage,
        tripProgress: progress.clamp(0.0, 1.0),
      ),
    );
  }

  Future<void> _completeTrip() async {
    _currentStage = RideTrackingStage.completed;
    if (_currentRide != null) {
      _currentRide = _currentRide!.copyWith(status: 'completed');
      final storage = await StorageService.getInstance();
      await storage.updateRideStatus(_currentRide!.id, 'completed');
      await storage.clearActiveRide();
    }

    final lastPos = _tripWaypoints.isNotEmpty
        ? _tripWaypoints.last
        : LatLng(_currentRide?.dropoffLat ?? 37.4275, _currentRide?.dropoffLng ?? -122.1697);

    _emitUpdate(
      stage: RideTrackingStage.completed,
      statusMessage: 'Trip completed! You have arrived safely at your campus destination.',
      minutes: 0,
      progress: 1.0,
      overridePos: lastPos,
    );
  }

  /// Cancels the current ride and releases listeners
  Future<void> cancelRide() async {
    _simulationTimer?.cancel();
    _simulationTimer = null;

    if (_currentRide != null) {
      _currentStage = RideTrackingStage.cancelled;
      _currentRide = _currentRide!.copyWith(status: 'cancelled');
      final storage = await StorageService.getInstance();
      await storage.updateRideStatus(_currentRide!.id, 'cancelled');
      await storage.clearActiveRide();

      _emitUpdate(
        stage: RideTrackingStage.cancelled,
        statusMessage: 'Ride cancelled.',
        minutes: 0,
        progress: 0.0,
      );
    }

    _currentStage = RideTrackingStage.idle;
    _currentRide = null;
    _tripWaypoints.clear();
  }

  /// Stops periodic timers and resets active session
  void stopTracking() {
    _simulationTimer?.cancel();
    _simulationTimer = null;
    _currentStage = RideTrackingStage.idle;
    _currentRide = null;
    _tripWaypoints.clear();
  }

  /// Cleans up resources when screen or app is closed
  void dispose() {
    stopTracking();
  }

  /// Calculates bearing angle in degrees between two LatLng points
  double _calculateBearing(LatLng from, LatLng to) {
    final double lat1 = from.latitude * (3.141592653589793 / 180.0);
    final double lon1 = from.longitude * (3.141592653589793 / 180.0);
    final double lat2 = to.latitude * (3.141592653589793 / 180.0);
    final double lon2 = to.longitude * (3.141592653589793 / 180.0);

    final double dLon = lon2 - lon1;
    final double y = sin(dLon) * cos(lat2);
    final double x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);

    final double radians = atan2(y, x);
    return (radians * (180.0 / 3.141592653589793) + 360.0) % 360.0;
  }
}
