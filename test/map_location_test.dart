import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:campus_ride_flutter/models/ride_model.dart';
import 'package:campus_ride_flutter/services/location_service.dart';

void main() {
  group('LocationService & Route Calculation Tests', () {
    final locationService = LocationService();

    test('Campus locations database is populated', () {
      expect(LocationService.campusLocations.length, greaterThanOrEqualTo(5));
      expect(LocationService.campusLocations.any((p) => p.name.contains('Campus') || p.name.contains('Library')), isTrue);
    });

    test('Campus search finds landmarks correctly', () {
      final results = locationService.searchLocations('Campus');
      expect(results.isNotEmpty, isTrue);
      expect(results.first.name, contains('Campus'));
    });

    test('Reverse geocoding resolves coordinates to closest campus landmark', () {
      const gatePos = LatLng(11.0404, 77.0747);
      final address = locationService.reverseGeocode(gatePos);
      expect(address, contains('Main Campus Gate'));
    });

    test('Route calculation produces distance, duration, and polyline points', () {
      const pickup = LatLng(11.0404, 77.0747);
      const dropoff = LatLng(11.0435, 77.0780);

      final route = locationService.calculateRoute(pickup, dropoff);

      expect(route.distanceKm, greaterThan(0));
      expect(route.durationMinutes, greaterThan(0));
      expect(route.baseFare, greaterThan(0));
      expect(route.polylinePoints.length, greaterThanOrEqualTo(2));
      expect(route.polylinePoints.first, equals(pickup));
      expect(route.polylinePoints.last, equals(dropoff));
    });

    test('RideModel serialization with map coordinates preserves all values', () {
      final ride = RideModel(
        id: 'test_ride_1',
        userId: 'u123',
        userName: 'Jane Doe',
        userPhone: '+1 555-0123',
        source: 'Main Campus Gate',
        destination: 'Avinashi Road Junction',
        date: '2026-10-21',
        time: '10:00 AM',
        availableSeats: 1,
        type: 'requested',
        status: 'active',
        createdAt: '2026-10-21T10:00:00',
        pickupLat: 11.0404,
        pickupLng: 77.0747,
        dropoffLat: 11.0435,
        dropoffLng: 77.0780,
        distanceKm: 1.2,
        durationMins: 4,
        fare: 3.88,
        rideCategory: 'Standard',
        driverName: 'Marcus Reed',
      );

      final map = ride.toMap();
      final revived = RideModel.fromMap(map);

      expect(revived.id, equals(ride.id));
      expect(revived.pickupLat, equals(11.0404));
      expect(revived.dropoffLat, equals(11.0435));
      expect(revived.distanceKm, equals(1.2));
      expect(revived.fare, equals(3.88));
      expect(revived.rideCategory, equals('Standard'));
      expect(revived.driverName, equals('Marcus Reed'));
    });
  });
}
