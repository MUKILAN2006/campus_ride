import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:intl/intl.dart';
import '../models/user_model.dart';
import '../models/ride_model.dart';
import '../services/location_service.dart';
import '../services/ride_tracking_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

enum SelectionTarget { pickup, dropoff }

enum MapScreenMode {
  pickLocation, // Single location picker (Source or Destination)
  previewRoute, // Route preview on satellite map (No money, no car/bike selection)
  routeAndTrack, // Book and track live ride on satellite map (No money, no car/bike selection)
}

enum SatelliteMapStyle {
  satelliteHybrid, // Real photographic satellite tiles + street & place labels (No watermark)
  pureSatellite, // Raw photographic satellite imagery
  streetView, // Street view
}

class LocationPickResult {
  final String address;
  final gmaps.LatLng position;

  const LocationPickResult({
    required this.address,
    required this.position,
  });
}

class MapRideScreen extends StatefulWidget {
  final UserModel user;
  final MapScreenMode mode;
  final SelectionTarget pickTarget;
  final String? initialAddress;
  final gmaps.LatLng? initialPickup;
  final gmaps.LatLng? initialDropoff;

  const MapRideScreen({
    super.key,
    required this.user,
    this.mode = MapScreenMode.routeAndTrack,
    this.pickTarget = SelectionTarget.pickup,
    this.initialAddress,
    this.initialPickup,
    this.initialDropoff,
  });

  @override
  State<MapRideScreen> createState() => _MapRideScreenState();
}

class _MapRideScreenState extends State<MapRideScreen> {
  final LocationService _locationService = LocationService();
  final RideTrackingService _trackingService = RideTrackingService();
  final MapController _mapController = MapController();

  StreamSubscription<RideTrackingUpdate>? _trackingSubscription;

  // Real Satellite imagery with full labels by default
  SatelliteMapStyle _mapStyle = SatelliteMapStyle.satelliteHybrid;

  // Positions
  ll.LatLng _centerPosition = const ll.LatLng(11.0404, 77.0747);
  ll.LatLng? _currentGpsPosition;
  ll.LatLng? _pickupPosition;
  String _pickupAddress = 'Detecting location...';
  ll.LatLng? _dropoffPosition;
  String _dropoffAddress = 'Tap map or search destination';

  // State for single location picker mode
  ll.LatLng? _pickedPosition;
  String _pickedAddress = 'Detecting location...';

  late SelectionTarget _activeTarget;

  // Search State with online geocoding
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _isSearching = false;
  bool _isLoadingSearch = false;
  Timer? _searchDebounceTimer;
  List<CampusPoint> _searchResults = [];

  // Route Metrics
  RouteEstimate? _routeEstimate;
  List<ll.LatLng> _routePoints = [];

  // UI & Loading States
  bool _isLoadingGps = false;
  bool _isCalculatingRoute = false;
  String? _locationStatusBanner;
  bool _isLiveTracking = false;
  RideTrackingUpdate? _latestTrackingUpdate;
  ll.LatLng? _driverPosition;

  @override
  void initState() {
    super.initState();
    _activeTarget = widget.pickTarget;
    _searchResults = LocationService.campusLocations;

    if (widget.initialPickup != null) {
      _pickupPosition = ll.LatLng(widget.initialPickup!.latitude, widget.initialPickup!.longitude);
      _pickupAddress = widget.initialAddress ??
          _locationService.reverseGeocode(widget.initialPickup!);
      _centerPosition = _pickupPosition!;
    }
    if (widget.initialDropoff != null) {
      _dropoffPosition = ll.LatLng(widget.initialDropoff!.latitude, widget.initialDropoff!.longitude);
      _dropoffAddress = widget.initialAddress ??
          _locationService.reverseGeocode(widget.initialDropoff!);
      _centerPosition = _dropoffPosition!;
    }

    if (widget.mode == MapScreenMode.pickLocation) {
      if (widget.pickTarget == SelectionTarget.pickup && _pickupPosition != null) {
        _pickedPosition = _pickupPosition;
        _pickedAddress = _pickupAddress;
      } else if (widget.pickTarget == SelectionTarget.dropoff && _dropoffPosition != null) {
        _pickedPosition = _dropoffPosition;
        _pickedAddress = _dropoffAddress;
      }
    }

    _initLocation();

    if (widget.mode == MapScreenMode.previewRoute || widget.mode == MapScreenMode.routeAndTrack) {
      if (widget.mode == MapScreenMode.routeAndTrack) {
        _listenToTrackingUpdates();
      }
      if (_pickupPosition != null && _dropoffPosition != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _calculateAndShowRoute();
        });
      }
    }
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _trackingSubscription?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _cycleMapStyle() {
    setState(() {
      if (_mapStyle == SatelliteMapStyle.satelliteHybrid) {
        _mapStyle = SatelliteMapStyle.pureSatellite;
      } else if (_mapStyle == SatelliteMapStyle.pureSatellite) {
        _mapStyle = SatelliteMapStyle.streetView;
      } else {
        _mapStyle = SatelliteMapStyle.satelliteHybrid;
      }
    });

    final String styleName = _mapStyle == SatelliteMapStyle.satelliteHybrid
        ? 'Satellite Hybrid (Photo + All Place Labels)'
        : _mapStyle == SatelliteMapStyle.pureSatellite
            ? 'Pure Satellite'
            : 'Street Map';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Map View: $styleName'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _listenToTrackingUpdates() {
    _trackingSubscription = _trackingService.trackingStream.listen((update) {
      if (!mounted) return;
      setState(() {
        _latestTrackingUpdate = update;
        _isLiveTracking = update.stage != RideTrackingStage.idle &&
            update.stage != RideTrackingStage.cancelled;
        _driverPosition = ll.LatLng(update.driverLocation.latitude, update.driverLocation.longitude);
      });

      if (_driverPosition != null) {
        _mapController.move(_driverPosition!, _mapController.camera.zoom);
      }

      if (update.stage == RideTrackingStage.completed) {
        _showTripCompletedDialog();
      }
    });
  }

  Future<void> _initLocation() async {
    setState(() => _isLoadingGps = true);

    final pos = await _locationService.getCurrentPosition();

    if (!mounted) return;

    if (pos != null) {
      final gpsLatLng = ll.LatLng(pos.latitude, pos.longitude);
      final gmapsPos = gmaps.LatLng(pos.latitude, pos.longitude);

      setState(() {
        _currentGpsPosition = gpsLatLng;
        _centerPosition = gpsLatLng;
        _isLoadingGps = false;
        _locationStatusBanner = null;

        if (widget.mode == MapScreenMode.pickLocation && _pickedPosition == null) {
          _pickedPosition = gpsLatLng;
          _pickedAddress = _locationService.reverseGeocode(gmapsPos);
        } else if ((widget.mode == MapScreenMode.routeAndTrack ||
                widget.mode == MapScreenMode.previewRoute) &&
            _pickupPosition == null) {
          _pickupPosition = gpsLatLng;
          _pickupAddress = _locationService.reverseGeocode(gmapsPos);
        }
      });

      _mapController.move(gpsLatLng, 16.5);
      _resolveAddressOnline(gmapsPos);
    } else {
      final fallback = ll.LatLng(
        LocationService.defaultCampusCenter.latitude,
        LocationService.defaultCampusCenter.longitude,
      );
      final gmapsPos = LocationService.defaultCampusCenter;

      setState(() {
        _currentGpsPosition = fallback;
        _centerPosition = fallback;
        _isLoadingGps = false;
        if (widget.mode == MapScreenMode.pickLocation && _pickedPosition == null) {
          _pickedPosition = fallback;
          _pickedAddress = _locationService.reverseGeocode(gmapsPos);
        } else if ((widget.mode == MapScreenMode.routeAndTrack ||
                widget.mode == MapScreenMode.previewRoute) &&
            _pickupPosition == null) {
          _pickupPosition = fallback;
          _pickupAddress = _locationService.reverseGeocode(gmapsPos);
        }
      });

      _mapController.move(fallback, 16.0);
      _resolveAddressOnline(gmapsPos);
    }
  }

  Future<void> _resolveAddressOnline(gmaps.LatLng pos) async {
    final realAddress = await _locationService.reverseGeocodeOnline(pos);
    if (!mounted) return;

    setState(() {
      if (widget.mode == MapScreenMode.pickLocation) {
        _pickedAddress = realAddress;
      } else {
        if (_activeTarget == SelectionTarget.pickup || _pickupPosition == null) {
          _pickupAddress = realAddress;
        } else {
          _dropoffAddress = realAddress;
        }
      }
    });
  }

  void _handleMapTap(ll.LatLng tappedPoint) {
    if (_isLiveTracking) return;

    final gmapsPoint = gmaps.LatLng(tappedPoint.latitude, tappedPoint.longitude);
    final quickAddress = _locationService.reverseGeocode(gmapsPoint);

    if (widget.mode == MapScreenMode.pickLocation) {
      setState(() {
        _pickedPosition = tappedPoint;
        _pickedAddress = quickAddress;
      });
      _mapController.move(tappedPoint, _mapController.camera.zoom);
    } else {
      setState(() {
        if (_activeTarget == SelectionTarget.pickup) {
          _pickupPosition = tappedPoint;
          _pickupAddress = quickAddress;
          _activeTarget = SelectionTarget.dropoff;
        } else {
          _dropoffPosition = tappedPoint;
          _dropoffAddress = quickAddress;
        }
      });
      _calculateAndShowRoute();
    }

    _resolveAddressOnline(gmapsPoint);
  }

  void _onSearchChanged(String query) {
    _searchDebounceTimer?.cancel();
    final clean = query.trim();

    if (clean.isEmpty) {
      setState(() {
        _isSearching = false;
        _isLoadingSearch = false;
        _searchResults = LocationService.campusLocations;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _isLoadingSearch = true;
    });

    _searchDebounceTimer = Timer(const Duration(milliseconds: 350), () async {
      final userPos = _currentGpsPosition != null
          ? gmaps.LatLng(_currentGpsPosition!.latitude, _currentGpsPosition!.longitude)
          : null;

      final results = await _locationService.searchPlacesOnline(clean, userLocation: userPos);

      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _isLoadingSearch = false;
      });
    });
  }

  void _selectSearchResult(CampusPoint point) {
    final targetPos = ll.LatLng(point.position.latitude, point.position.longitude);

    setState(() {
      _isSearching = false;
      _searchController.clear();
      _searchFocusNode.unfocus();

      if (widget.mode == MapScreenMode.pickLocation) {
        _pickedPosition = targetPos;
        _pickedAddress = '${point.name}, ${point.subtitle}';
      } else {
        if (_activeTarget == SelectionTarget.pickup) {
          _pickupPosition = targetPos;
          _pickupAddress = '${point.name}, ${point.subtitle}';
          _activeTarget = SelectionTarget.dropoff;
        } else {
          _dropoffPosition = targetPos;
          _dropoffAddress = '${point.name}, ${point.subtitle}';
        }
      }
    });

    _mapController.move(targetPos, 16.8);

    if (widget.mode == MapScreenMode.previewRoute || widget.mode == MapScreenMode.routeAndTrack) {
      _calculateAndShowRoute();
    }
  }

  void _calculateAndShowRoute() {
    if (_pickupPosition == null || _dropoffPosition == null) {
      setState(() {
        _routeEstimate = null;
        _routePoints.clear();
      });
      return;
    }

    setState(() => _isCalculatingRoute = true);

    final p1 = gmaps.LatLng(_pickupPosition!.latitude, _pickupPosition!.longitude);
    final p2 = gmaps.LatLng(_dropoffPosition!.latitude, _dropoffPosition!.longitude);

    final route = _locationService.calculateRoute(p1, p2);

    setState(() {
      _routeEstimate = route;
      _routePoints = route.polylinePoints
          .map((pt) => ll.LatLng(pt.latitude, pt.longitude))
          .toList();
      _isCalculatingRoute = false;
    });

    final midLat = (_pickupPosition!.latitude + _dropoffPosition!.latitude) / 2;
    final midLng = (_pickupPosition!.longitude + _dropoffPosition!.longitude) / 2;
    _mapController.move(ll.LatLng(midLat, midLng), 15.2);
  }

  void _confirmPickedLocation() {
    if (_pickedPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a location on the satellite map.')),
      );
      return;
    }

    final result = LocationPickResult(
      address: _pickedAddress.isNotEmpty ? _pickedAddress : 'Selected Satellite Location',
      position: gmaps.LatLng(_pickedPosition!.latitude, _pickedPosition!.longitude),
    );

    Navigator.of(context).pop(result);
  }

  Future<void> _recenterGps() async {
    setState(() => _isLoadingGps = true);
    final pos = await _locationService.getCurrentPosition();

    if (!mounted) return;

    if (pos != null) {
      final latLng = ll.LatLng(pos.latitude, pos.longitude);
      final gmapsPos = gmaps.LatLng(pos.latitude, pos.longitude);

      setState(() {
        _currentGpsPosition = latLng;
        _isLoadingGps = false;
        if (widget.mode == MapScreenMode.pickLocation) {
          _pickedPosition = latLng;
          _pickedAddress = _locationService.reverseGeocode(gmapsPos);
        }
      });
      _mapController.move(latLng, 16.8);
      _resolveAddressOnline(gmapsPos);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Centered at your GPS location'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      final fallback = ll.LatLng(
        LocationService.defaultCampusCenter.latitude,
        LocationService.defaultCampusCenter.longitude,
      );
      setState(() => _isLoadingGps = false);
      _mapController.move(fallback, 16.0);
    }
  }

  // Starts live driver tracking without any money/fare or vehicle selection
  Future<void> _startLiveRideTracking() async {
    if (_pickupPosition == null || _dropoffPosition == null || _routeEstimate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select both pickup and drop-off locations.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    final now = DateTime.now();
    final newRide = RideModel(
      id: 'ride_${DateTime.now().millisecondsSinceEpoch}',
      userId: widget.user.id,
      userName: widget.user.fullName,
      userPhone: widget.user.phone,
      source: _pickupAddress,
      destination: _dropoffAddress,
      date: DateFormat('yyyy-MM-dd').format(now),
      time: DateFormat('hh:mm a').format(now),
      availableSeats: 1,
      type: 'requested',
      status: 'active',
      createdAt: now.toIso8601String(),
      pickupLat: _pickupPosition!.latitude,
      pickupLng: _pickupPosition!.longitude,
      dropoffLat: _dropoffPosition!.latitude,
      dropoffLng: _dropoffPosition!.longitude,
      distanceKm: _routeEstimate!.distanceKm,
      durationMins: _routeEstimate!.durationMinutes,
      fare: null, // No money/fare
      rideCategory: 'Campus Ride',
      driverName: 'Marcus Reed',
      driverPhone: '+1 (650) 555-0198',
      driverRating: '4.94',
      vehicleDetails: 'Silver Camry • ABC-7892',
    );

    final storage = await StorageService.getInstance();
    await storage.addRide(newRide);

    await _trackingService.startTrackingRide(newRide);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Live Ride Tracking started on satellite map!'),
        backgroundColor: AppTheme.primaryEmerald,
      ),
    );
  }

  Future<void> _cancelActiveRide() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel Ride?'),
        content: const Text('Are you sure you want to cancel your ongoing campus ride?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep Ride'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _trackingService.cancelRide();
      if (!mounted) return;
      setState(() {
        _isLiveTracking = false;
        _latestTrackingUpdate = null;
        _driverPosition = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Campus ride was cancelled.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _showTripCompletedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primaryEmerald.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: AppTheme.primaryEmerald,
                size: 56,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Trip Completed!',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.bgDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You arrived safely at $_dropoffAddress.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      const Text('Total Distance', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 4),
                      Text(
                        '${_routeEstimate?.distanceKm ?? 2.1} km',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                  Container(width: 1, height: 30, color: Colors.grey.shade300),
                  Column(
                    children: [
                      const Text('Travel Time', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 4),
                      Text(
                        '${_routeEstimate?.durationMinutes ?? 5} mins',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: AppTheme.primaryEmerald,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryEmerald,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                setState(() {
                  _isLiveTracking = false;
                  _latestTrackingUpdate = null;
                  _driverPosition = null;
                  _dropoffPosition = null;
                  _dropoffAddress = 'Tap satellite map or search destination';
                  _routeEstimate = null;
                  _routePoints.clear();
                });
              },
              child: const Text('Done & Back to Map', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isPicker = widget.mode == MapScreenMode.pickLocation;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // 1. Photographic Satellite Map with Place & Road Names (Zero Watermark)
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _pickedPosition ??
                  _pickupPosition ??
                  _currentGpsPosition ??
                  _centerPosition,
              initialZoom: 16.8,
              maxZoom: 20.0,
              minZoom: 3.0,
              onTap: (_, tappedPoint) => _handleMapTap(tappedPoint),
            ),
            children: [
              // High-Resolution Satellite Tiles with Full Road & Place Names (Google Hybrid / OSM)
              if (_mapStyle == SatelliteMapStyle.satelliteHybrid)
                TileLayer(
                  urlTemplate: 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}',
                  userAgentPackageName: 'com.example.campus_ride_flutter',
                  maxZoom: 20,
                )
              else if (_mapStyle == SatelliteMapStyle.pureSatellite)
                TileLayer(
                  urlTemplate: 'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}',
                  userAgentPackageName: 'com.example.campus_ride_flutter',
                  maxZoom: 20,
                )
              else
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.campus_ride_flutter',
                  maxZoom: 19,
                ),

              // Polyline Layer for Route
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      strokeWidth: 6.0,
                      color: AppTheme.primaryEmerald,
                      borderColor: Colors.black45,
                      borderStrokeWidth: 2.0,
                    ),
                  ],
                ),

              // Marker Layer for Interactive Points
              MarkerLayer(
                markers: _buildMarkers(isPicker),
              ),
            ],
          ),

          // 2. Permission / Status Banner
          if (_locationStatusBanner != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 16,
              right: 16,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                color: Colors.amber.shade900.withValues(alpha: 0.94),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.location_off_rounded, color: Colors.white),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _locationStatusBanner!,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ),
                      TextButton(
                        onPressed: _initLocation,
                        child: const Text('Retry', style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 3. Top Floating Search & Selection Header
          Positioned(
            top: MediaQuery.of(context).padding.top + (_locationStatusBanner != null ? 65 : 12),
            left: 16,
            right: 16,
            child: Column(
              children: [
                isPicker ? _buildPickerTopHeader() : _buildTopSearchCard(),
                if (_isSearching) _buildSearchResultsOverlay(),
              ],
            ),
          ),

          // 4. Floating Action Controls (Satellite Layer Switch, Recenter, Landmarks)
          Positioned(
            right: 16,
            bottom: isPicker ? 220 : (_isLiveTracking ? 340 : 250),
            child: Column(
              children: [
                // Satellite / Hybrid / Street Layer Toggle FAB
                FloatingActionButton.small(
                  heroTag: 'fab_satellite_layer',
                  backgroundColor: const Color(0xFF1E293B),
                  foregroundColor: Colors.white,
                  elevation: 4,
                  onPressed: _cycleMapStyle,
                  tooltip: 'Satellite Layer Toggle',
                  child: const Icon(Icons.satellite_alt_rounded, size: 20),
                ),
                const SizedBox(height: 10),
                // Landmarks FAB
                FloatingActionButton.small(
                  heroTag: 'fab_landmarks',
                  backgroundColor: Colors.white,
                  foregroundColor: AppTheme.accentIndigo,
                  elevation: 4,
                  onPressed: () {
                    setState(() {
                      _isSearching = !_isSearching;
                      _searchResults = LocationService.campusLocations;
                    });
                  },
                  tooltip: 'Campus Landmarks',
                  child: const Icon(Icons.school_rounded),
                ),
                const SizedBox(height: 10),
                // Recenter GPS FAB
                FloatingActionButton(
                  heroTag: 'fab_recenter',
                  backgroundColor: Colors.white,
                  foregroundColor: AppTheme.primaryEmerald,
                  elevation: 4,
                  onPressed: _recenterGps,
                  tooltip: 'My GPS Location',
                  child: _isLoadingGps
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Icon(Icons.my_location_rounded),
                ),
              ],
            ),
          ),

          // 5. Bottom Panel: Location Picker OR Route Preview/Booking OR Live Tracking
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: isPicker
                ? _buildSinglePickerBottomPanel()
                : (_isLiveTracking
                    ? _buildLiveTrackingBottomPanel()
                    : _buildRouteBottomPanel()),
          ),
        ],
      ),
    );
  }

  List<Marker> _buildMarkers(bool isPicker) {
    final List<Marker> markers = [];

    // Current GPS user location
    if (_currentGpsPosition != null) {
      markers.add(
        Marker(
          point: _currentGpsPosition!,
          width: 32,
          height: 32,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.25),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.blueAccent,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: const [
                    BoxShadow(color: Colors.black38, blurRadius: 6),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (isPicker) {
      if (_pickedPosition != null) {
        final bool isPickup = widget.pickTarget == SelectionTarget.pickup;
        markers.add(
          Marker(
            point: _pickedPosition!,
            width: 48,
            height: 48,
            child: Icon(
              Icons.location_on_rounded,
              color: isPickup ? Colors.greenAccent : Colors.redAccent,
              size: 44,
            ),
          ),
        );
      }
    } else {
      if (_pickupPosition != null) {
        markers.add(
          Marker(
            point: _pickupPosition!,
            width: 44,
            height: 44,
            child: const Icon(
              Icons.location_on_rounded,
              color: Colors.greenAccent,
              size: 40,
            ),
          ),
        );
      }

      if (_dropoffPosition != null) {
        markers.add(
          Marker(
            point: _dropoffPosition!,
            width: 44,
            height: 44,
            child: const Icon(
              Icons.location_on_rounded,
              color: Colors.redAccent,
              size: 40,
            ),
          ),
        );
      }

      if (_driverPosition != null && _isLiveTracking) {
        markers.add(
          Marker(
            point: _driverPosition!,
            width: 50,
            height: 50,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.amber.shade600,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(color: Colors.black54, blurRadius: 8),
                ],
              ),
              child: const Icon(Icons.directions_car_filled_rounded, color: Colors.white, size: 24),
            ),
          ),
        );
      }
    }

    return markers;
  }

  // --- Top Header for Single Location Picker Mode ---
  Widget _buildPickerTopHeader() {
    final bool isPickup = widget.pickTarget == SelectionTarget.pickup;
    final String title = isPickup ? 'Select Source Location' : 'Select Destination';
    final Color tagColor = isPickup ? AppTheme.primaryEmerald : Colors.redAccent;

    return Card(
      elevation: 6,
      shadowColor: Colors.black45,
      color: const Color(0xFF0F172A).withValues(alpha: 0.94),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 10),
                Icon(
                  isPickup ? Icons.radio_button_checked : Icons.location_on_rounded,
                  color: tagColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.satellite_outlined, color: Colors.white70, size: 14),
                      SizedBox(width: 4),
                      Text('Satellite', style: TextStyle(color: Colors.white70, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              style: const TextStyle(color: Colors.white),
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search place, road, campus...',
                hintStyle: const TextStyle(fontSize: 13, color: Colors.white54),
                prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Colors.white70),
                suffixIcon: _isLoadingSearch
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent),
                        ),
                      )
                    : _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18, color: Colors.white70),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _isSearching = false;
                                _searchResults = LocationService.campusLocations;
                              });
                            },
                          )
                        : null,
                isDense: true,
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.12),
                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Bottom Panel for Single Location Picker ---
  Widget _buildSinglePickerBottomPanel() {
    final bool isPickup = widget.pickTarget == SelectionTarget.pickup;
    final String targetLabel = isPickup ? 'Source Location' : 'Destination';
    final Color themeColor = isPickup ? AppTheme.primaryEmerald : Colors.redAccent;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 18,
            offset: Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: themeColor.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isPickup ? Icons.my_location_rounded : Icons.place_rounded,
                  color: themeColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SELECTED $targetLabel'.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: themeColor,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _pickedAddress.isNotEmpty ? _pickedAddress : 'Tap any spot on the satellite map',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: themeColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 4,
            ),
            icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
            label: Text(
              'Confirm $targetLabel',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            onPressed: _pickedPosition != null ? _confirmPickedLocation : null,
          ),
        ],
      ),
    );
  }

  // --- Top Search & Selection Header Widget for Route/Track Mode ---
  Widget _buildTopSearchCard() {
    return Card(
      elevation: 6,
      shadowColor: Colors.black45,
      color: const Color(0xFF0F172A).withValues(alpha: 0.95),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    style: const TextStyle(color: Colors.white),
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: _activeTarget == SelectionTarget.pickup
                          ? 'Search pickup on satellite...'
                          : 'Search drop-off on satellite...',
                      hintStyle: const TextStyle(fontSize: 13, color: Colors.white54),
                      prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppTheme.primaryEmerald),
                      suffixIcon: _isLoadingSearch
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent),
                              ),
                            )
                          : _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 18, color: Colors.white70),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {
                                      _isSearching = false;
                                      _searchResults = LocationService.campusLocations;
                                    });
                                  },
                                )
                              : null,
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.12),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1, thickness: 0.8, color: Colors.white24),
            const SizedBox(height: 8),

            // Pickup & Dropoff Selectors
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () {
                      setState(() => _activeTarget = SelectionTarget.pickup);
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: _activeTarget == SelectionTarget.pickup
                            ? AppTheme.primaryEmerald.withValues(alpha: 0.25)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _activeTarget == SelectionTarget.pickup
                              ? AppTheme.primaryEmerald
                              : Colors.white24,
                          width: _activeTarget == SelectionTarget.pickup ? 1.5 : 1.0,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.radio_button_checked, size: 16, color: Colors.greenAccent),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'PICKUP',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.greenAccent,
                                  ),
                                ),
                                Text(
                                  _pickupAddress,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      setState(() => _activeTarget = SelectionTarget.dropoff);
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: _activeTarget == SelectionTarget.dropoff
                            ? Colors.redAccent.withValues(alpha: 0.25)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _activeTarget == SelectionTarget.dropoff
                              ? Colors.redAccent
                              : Colors.white24,
                          width: _activeTarget == SelectionTarget.dropoff ? 1.5 : 1.0,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on_rounded, size: 16, color: Colors.redAccent),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'DROP-OFF',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.redAccent,
                                  ),
                                ),
                                Text(
                                  _dropoffAddress,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- Autocomplete Campus & Place Search Results Overlay ---
  Widget _buildSearchResultsOverlay() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 280),
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: _isLoadingSearch
          ? const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.cyanAccent, strokeWidth: 2)),
                    SizedBox(width: 12),
                    Text('Searching places...', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ),
            )
          : _searchResults.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(
                    child: Text('No matching places found. Try another search term.', style: TextStyle(color: Colors.white60, fontSize: 13)),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _searchResults.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 48, color: Colors.white12),
                  itemBuilder: (context, idx) {
                    final item = _searchResults[idx];
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: AppTheme.accentIndigo.withValues(alpha: 0.3),
                        child: const Icon(Icons.place_rounded, size: 18, color: Colors.cyanAccent),
                      ),
                      title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white)),
                      subtitle: Text(
                        item.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: Colors.white60),
                      ),
                      onTap: () => _selectSearchResult(item),
                    );
                  },
                ),
    );
  }

  // --- Bottom Panel for Route Preview & Book/Track (NO MONEY, NO VEHICLE SELECTION) ---
  Widget _buildRouteBottomPanel() {
    final bool isPreview = widget.mode == MapScreenMode.previewRoute;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 18,
            offset: Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Route Metrics: Distance & Est. Time (NO MONEY / FARE)
          if (_isCalculatingRoute)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.cyanAccent, strokeWidth: 2)),
                    SizedBox(width: 10),
                    Text('Calculating route across satellite paths...', style: TextStyle(fontSize: 13, color: Colors.white70)),
                  ],
                ),
              ),
            )
          else if (_routeEstimate != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildMetricChip(
                  icon: Icons.straighten_rounded,
                  label: 'Total Distance',
                  value: '${_routeEstimate!.distanceKm} km',
                  color: Colors.cyanAccent,
                ),
                Container(width: 1, height: 32, color: Colors.white12),
                _buildMetricChip(
                  icon: Icons.timer_outlined,
                  label: 'Estimated Travel Time',
                  value: '${_routeEstimate!.durationMinutes} mins',
                  color: Colors.amberAccent,
                ),
              ],
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: const [
                  Icon(Icons.touch_app_rounded, color: AppTheme.primaryEmerald, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Tap anywhere on satellite map to set destination & preview route',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 18),

          // Action Button: Preview Route vs Start Live Tracking (NO MONEY, NO CAR/BIKE OPTIONS)
          if (isPreview)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryEmerald,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 3,
              ),
              icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
              label: const Text(
                'Close Route Preview',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              onPressed: () => Navigator.of(context).pop(),
            )
          else
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _dropoffPosition != null ? AppTheme.primaryEmerald : Colors.white24,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: _dropoffPosition != null ? 3 : 0,
              ),
              icon: const Icon(Icons.navigation_rounded, size: 20),
              label: Text(
                _dropoffPosition != null
                    ? 'Start Live Ride Tracking'
                    : 'Select Destination on Map',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onPressed: _dropoffPosition != null ? _startLiveRideTracking : null,
            ),
        ],
      ),
    );
  }

  // --- Live Driver Tracking Bottom Panel ---
  Widget _buildLiveTrackingBottomPanel() {
    final update = _latestTrackingUpdate;
    final ride = update?.ride;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 18,
            offset: Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Colors.greenAccent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  update?.statusMessage ?? 'Live Satellite Tracking Active...',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.accentIndigo.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'ETA: ${update?.remainingMinutes ?? 4} min',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.cyanAccent,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: update?.tripProgress ?? 0.1,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryEmerald),
              minHeight: 6,
            ),
          ),

          const SizedBox(height: 16),

          // Driver Information Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppTheme.accentIndigo,
                  child: const Icon(Icons.person_rounded, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            ride?.driverName ?? 'Marcus Reed',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.star_rounded, size: 12, color: Colors.amberAccent),
                                const SizedBox(width: 2),
                                Text(
                                  ride?.driverRating ?? '4.92',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amberAccent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        ride?.vehicleDetails ?? 'Silver Toyota Camry • ABC-7892',
                        style: const TextStyle(fontSize: 12, color: Colors.white60),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.phone_rounded, color: Colors.greenAccent),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Calling driver ${ride?.driverPhone ?? "+1 (650) 555-0198"}...'),
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.cyanAccent),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Driver Chat: "I am arriving at the campus stop in 2 mins."'),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: const BorderSide(color: Colors.redAccent),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            icon: const Icon(Icons.cancel_outlined, size: 18),
            label: const Text('Cancel Ride', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: _cancelActiveRide,
          ),
        ],
      ),
    );
  }

  Widget _buildMetricChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.white60),
        ),
      ],
    );
  }
}
