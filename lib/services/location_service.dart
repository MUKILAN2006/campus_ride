import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:http/http.dart' as http;

enum LocationServiceStatus {
  ready,
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  error,
}

class CampusPoint {
  final String name;
  final String category;
  final gmaps.LatLng position;
  final String subtitle;

  const CampusPoint({
    required this.name,
    required this.category,
    required this.position,
    required this.subtitle,
  });
}

class RouteEstimate {
  final double distanceKm;
  final int durationMinutes;
  final double baseFare;
  final List<gmaps.LatLng> polylinePoints;

  const RouteEstimate({
    required this.distanceKm,
    required this.durationMinutes,
    required this.baseFare,
    required this.polylinePoints,
  });
}

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  // In-memory cache for reverse geocoding
  final Map<String, String> _reverseGeocodeCache = {};

  // Default campus center benchmark
  static const gmaps.LatLng defaultCampusCenter = gmaps.LatLng(11.0404, 77.0747);

  // Pre-configured Campus Points of Interest
  static const List<CampusPoint> campusLocations = [
    CampusPoint(
      name: 'Main Campus Gate',
      category: 'Transit',
      position: gmaps.LatLng(11.0404, 77.0747),
      subtitle: 'Main Entrance & Security Post',
    ),
    CampusPoint(
      name: 'Academic Block & Library',
      category: 'Academic',
      position: gmaps.LatLng(11.0410, 77.0750),
      subtitle: 'Central Library, 1st Floor',
    ),
    CampusPoint(
      name: 'Engineering & Tech Labs',
      category: 'Academic',
      position: gmaps.LatLng(11.0398, 77.0735),
      subtitle: 'Computer Science & Electronics Block',
    ),
    CampusPoint(
      name: 'Student Cafeteria & Food Court',
      category: 'Dining',
      position: gmaps.LatLng(11.0400, 77.0755),
      subtitle: 'Main Dining & Snack Counter',
    ),
    CampusPoint(
      name: 'Campus Hostel & Residential Area',
      category: 'Housing',
      position: gmaps.LatLng(11.0385, 77.0730),
      subtitle: 'Student Dormitories & Guest House',
    ),
    CampusPoint(
      name: 'Avinashi Road Junction',
      category: 'Transit',
      position: gmaps.LatLng(11.0435, 77.0780),
      subtitle: 'Avinashi Highway Bus Stop',
    ),
    CampusPoint(
      name: 'Sports Ground & Arena',
      category: 'Recreation',
      position: gmaps.LatLng(11.0420, 77.0730),
      subtitle: 'Football Ground & Indoor Badminton',
    ),
  ];

  /// Checks whether location services and permissions are granted.
  Future<LocationServiceStatus> checkAndRequestLocationPermission() async {
    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return LocationServiceStatus.serviceDisabled;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return LocationServiceStatus.permissionDenied;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return LocationServiceStatus.permissionDeniedForever;
      }

      return LocationServiceStatus.ready;
    } catch (e) {
      debugPrint('Location permission check notice: $e');
      return LocationServiceStatus.error;
    }
  }

  /// Obtains the device position swiftly:
  /// 1. Tries instant last known position first (< 10ms)
  /// 2. Then tries fresh position with reasonable timeout
  Future<Position?> getCurrentPosition() async {
    try {
      final status = await checkAndRequestLocationPermission();
      if (status != LocationServiceStatus.ready) {
        return null;
      }

      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        return lastKnown;
      }

      try {
        return await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 3),
          ),
        );
      } on TimeoutException {
        debugPrint('GPS lock timed out, falling back to default location');
        return lastKnown;
      }
    } catch (e) {
      debugPrint('Notice getting position: $e');
      return null;
    }
  }

  /// Searches for places online using OpenStreetMap Nominatim with local fallback.
  Future<List<CampusPoint>> searchPlacesOnline(
    String query, {
    gmaps.LatLng? userLocation,
  }) async {
    final clean = query.trim();
    if (clean.isEmpty) {
      return campusLocations;
    }

    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(clean)}&format=json&addressdetails=1&limit=8',
      );

      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'CampusRideFlutterApp/1.0 (contact: support@campusride.edu)',
          'Accept-Language': 'en',
        },
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (data.isNotEmpty) {
          final List<CampusPoint> results = [];
          for (final item in data) {
            final lat = double.tryParse(item['lat']?.toString() ?? '');
            final lon = double.tryParse(item['lon']?.toString() ?? '');
            if (lat != null && lon != null) {
              final String name = item['name'] ??
                  item['address']?['amenity'] ??
                  item['address']?['road'] ??
                  item['address']?['suburb'] ??
                  item['display_name'].toString().split(',').first;

              final String fullDisplay = item['display_name'] ?? '';
              final parts = fullDisplay.split(',');
              final subtitle = parts.length > 1
                  ? parts.sublist(1, min(4, parts.length)).join(',').trim()
                  : (item['type'] ?? 'Location');

              results.add(
                CampusPoint(
                  name: name,
                  category: item['type'] ?? 'Place',
                  position: gmaps.LatLng(lat, lon),
                  subtitle: subtitle,
                ),
              );
            }
          }
          if (results.isNotEmpty) return results;
        }
      }
    } catch (e) {
      debugPrint('Online place search error: $e');
    }

    // Fallback to local matching
    return searchLocations(clean);
  }

  /// Converts a [gmaps.LatLng] coordinate into a human-readable place name using online reverse geocoding.
  Future<String> reverseGeocodeOnline(gmaps.LatLng position) async {
    final cacheKey =
        '${position.latitude.toStringAsFixed(4)},${position.longitude.toStringAsFixed(4)}';
    if (_reverseGeocodeCache.containsKey(cacheKey)) {
      return _reverseGeocodeCache[cacheKey]!;
    }

    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?lat=${position.latitude}&lon=${position.longitude}&format=json&addressdetails=1',
      );

      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'CampusRideFlutterApp/1.0 (contact: support@campusride.edu)',
          'Accept-Language': 'en',
        },
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final address = data['address'] as Map<String, dynamic>?;

        if (address != null) {
          final primary = address['amenity'] ??
              address['building'] ??
              address['college'] ??
              address['university'] ??
              address['road'] ??
              address['suburb'] ??
              address['neighbourhood'] ??
              address['city_district'];

          final secondary = address['road'] ??
              address['suburb'] ??
              address['village'] ??
              address['county'] ??
              address['city'] ??
              address['state_district'];

          String result;
          if (primary != null && secondary != null && primary != secondary) {
            result = '$primary, $secondary';
          } else if (primary != null) {
            result = primary.toString();
          } else if (data['name'] != null && data['name'].toString().isNotEmpty) {
            result = data['name'].toString();
          } else {
            result = data['display_name'].toString().split(',').take(2).join(',').trim();
          }

          _reverseGeocodeCache[cacheKey] = result;
          return result;
        }
      }
    } catch (e) {
      debugPrint('Online reverse geocode error: $e');
    }

    // Fallback to local reverse geocode
    final fallback = reverseGeocode(position);
    _reverseGeocodeCache[cacheKey] = fallback;
    return fallback;
  }

  /// Synchronous fallback reverse geocode
  String reverseGeocode(gmaps.LatLng position) {
    CampusPoint? closest;
    double minDistanceMeters = double.infinity;

    for (final point in campusLocations) {
      final dist = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        point.position.latitude,
        point.position.longitude,
      );
      if (dist < minDistanceMeters) {
        minDistanceMeters = dist;
        closest = point;
      }
    }

    if (closest != null && minDistanceMeters < 250) {
      if (minDistanceMeters < 40) {
        return closest.name;
      } else {
        return '${closest.name} (${minDistanceMeters.round()}m away)';
      }
    }

    return 'Location at ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
  }

  /// Synchronous fallback search
  List<CampusPoint> searchLocations(String query) {
    final clean = query.trim().toLowerCase();
    if (clean.isEmpty) {
      return campusLocations;
    }
    return campusLocations.where((loc) {
      return loc.name.toLowerCase().contains(clean) ||
          loc.category.toLowerCase().contains(clean) ||
          loc.subtitle.toLowerCase().contains(clean);
    }).toList();
  }

  /// Calculates the route distance, travel duration, base fare, and polyline waypoints.
  RouteEstimate calculateRoute(gmaps.LatLng pickup, gmaps.LatLng dropoff) {
    final distanceMeters = Geolocator.distanceBetween(
      pickup.latitude,
      pickup.longitude,
      dropoff.latitude,
      dropoff.longitude,
    );

    final double roadDistanceKm = max(0.4, (distanceMeters * 1.28) / 1000.0);
    final int travelMinutes = max(3, (roadDistanceKm / 24 * 60).round() + 2);
    final double fare = 2.50 + (roadDistanceKm * 1.15);

    final polyline = _generateRealisticRoadPolyline(pickup, dropoff);

    return RouteEstimate(
      distanceKm: double.parse(roadDistanceKm.toStringAsFixed(1)),
      durationMinutes: travelMinutes,
      baseFare: double.parse(fare.toStringAsFixed(2)),
      polylinePoints: polyline,
    );
  }

  List<gmaps.LatLng> _generateRealisticRoadPolyline(gmaps.LatLng start, gmaps.LatLng end) {
    final List<gmaps.LatLng> points = [start];

    final double latDiff = end.latitude - start.latitude;
    final double lngDiff = end.longitude - start.longitude;

    points.add(gmaps.LatLng(
      start.latitude + (latDiff * 0.35),
      start.longitude + (lngDiff * 0.05),
    ));

    points.add(gmaps.LatLng(
      start.latitude + (latDiff * 0.40),
      start.longitude + (lngDiff * 0.55),
    ));

    points.add(gmaps.LatLng(
      start.latitude + (latDiff * 0.85),
      start.longitude + (lngDiff * 0.65),
    ));

    points.add(gmaps.LatLng(
      start.latitude + (latDiff * 0.95),
      start.longitude + (lngDiff * 0.90),
    ));

    points.add(end);
    return points;
  }

  List<gmaps.LatLng> generateFullDriverTripWaypoints(
    gmaps.LatLng driverStart,
    gmaps.LatLng pickup,
    gmaps.LatLng dropoff,
  ) {
    final List<gmaps.LatLng> waypoints = [];

    const int toPickupSteps = 8;
    for (int i = 0; i <= toPickupSteps; i++) {
      final double t = i / toPickupSteps;
      final lat = driverStart.latitude + (pickup.latitude - driverStart.latitude) * t;
      final lng = driverStart.longitude + (pickup.longitude - driverStart.longitude) * t;
      waypoints.add(gmaps.LatLng(lat, lng));
    }

    const int toDropoffSteps = 14;
    for (int i = 1; i <= toDropoffSteps; i++) {
      final double t = i / toDropoffSteps;
      final lat = pickup.latitude + (dropoff.latitude - pickup.latitude) * t;
      final lng = pickup.longitude + (dropoff.longitude - pickup.longitude) * t;
      waypoints.add(gmaps.LatLng(lat, lng));
    }

    return waypoints;
  }
}
