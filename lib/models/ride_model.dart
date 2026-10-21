import 'dart:convert';

class RideModel {
  final String id;
  final String userId;
  final String userName;
  final String userPhone;
  final String source;
  final String destination;
  final String date;
  final String time;
  final int availableSeats;
  final String type; // 'offered' or 'requested'
  final String? vehicleDetails;
  final String createdAt;
  final String status; // 'active', 'driver_assigned', 'in_progress', 'completed', 'cancelled'

  // Map & Location specific fields
  final double? pickupLat;
  final double? pickupLng;
  final double? dropoffLat;
  final double? dropoffLng;
  final double? driverLat;
  final double? driverLng;
  final double? distanceKm;
  final int? durationMins;
  final double? fare;
  final String? rideCategory; // 'Carpool', 'Standard', 'Campus Bike', 'Express Van'
  final String? driverName;
  final String? driverPhone;
  final String? driverRating;

  RideModel({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userPhone,
    required this.source,
    required this.destination,
    required this.date,
    required this.time,
    required this.availableSeats,
    required this.type,
    this.vehicleDetails,
    required this.createdAt,
    this.status = 'active',
    this.pickupLat,
    this.pickupLng,
    this.dropoffLat,
    this.dropoffLng,
    this.driverLat,
    this.driverLng,
    this.distanceKm,
    this.durationMins,
    this.fare,
    this.rideCategory,
    this.driverName,
    this.driverPhone,
    this.driverRating,
  });

  RideModel copyWith({
    String? id,
    String? userId,
    String? userName,
    String? userPhone,
    String? source,
    String? destination,
    String? date,
    String? time,
    int? availableSeats,
    String? type,
    String? vehicleDetails,
    String? createdAt,
    String? status,
    double? pickupLat,
    double? pickupLng,
    double? dropoffLat,
    double? dropoffLng,
    double? driverLat,
    double? driverLng,
    double? distanceKm,
    int? durationMins,
    double? fare,
    String? rideCategory,
    String? driverName,
    String? driverPhone,
    String? driverRating,
  }) {
    return RideModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userPhone: userPhone ?? this.userPhone,
      source: source ?? this.source,
      destination: destination ?? this.destination,
      date: date ?? this.date,
      time: time ?? this.time,
      availableSeats: availableSeats ?? this.availableSeats,
      type: type ?? this.type,
      vehicleDetails: vehicleDetails ?? this.vehicleDetails,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      pickupLat: pickupLat ?? this.pickupLat,
      pickupLng: pickupLng ?? this.pickupLng,
      dropoffLat: dropoffLat ?? this.dropoffLat,
      dropoffLng: dropoffLng ?? this.dropoffLng,
      driverLat: driverLat ?? this.driverLat,
      driverLng: driverLng ?? this.driverLng,
      distanceKm: distanceKm ?? this.distanceKm,
      durationMins: durationMins ?? this.durationMins,
      fare: fare ?? this.fare,
      rideCategory: rideCategory ?? this.rideCategory,
      driverName: driverName ?? this.driverName,
      driverPhone: driverPhone ?? this.driverPhone,
      driverRating: driverRating ?? this.driverRating,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'userName': userName,
      'userPhone': userPhone,
      'source': source,
      'destination': destination,
      'date': date,
      'time': time,
      'availableSeats': availableSeats,
      'type': type,
      'vehicleDetails': vehicleDetails,
      'createdAt': createdAt,
      'status': status,
      'pickupLat': pickupLat,
      'pickupLng': pickupLng,
      'dropoffLat': dropoffLat,
      'dropoffLng': dropoffLng,
      'driverLat': driverLat,
      'driverLng': driverLng,
      'distanceKm': distanceKm,
      'durationMins': durationMins,
      'fare': fare,
      'rideCategory': rideCategory,
      'driverName': driverName,
      'driverPhone': driverPhone,
      'driverRating': driverRating,
    };
  }

  factory RideModel.fromMap(Map<String, dynamic> map) {
    return RideModel(
      id: map['id'] ?? '',
      userId: map['userId'] ?? '',
      userName: map['userName'] ?? '',
      userPhone: map['userPhone'] ?? '',
      source: map['source'] ?? '',
      destination: map['destination'] ?? '',
      date: map['date'] ?? '',
      time: map['time'] ?? '',
      availableSeats: map['availableSeats'] != null
          ? int.parse(map['availableSeats'].toString())
          : 1,
      type: map['type'] ?? 'offered',
      vehicleDetails: map['vehicleDetails'],
      createdAt: map['createdAt'] ?? DateTime.now().toIso8601String(),
      status: map['status'] ?? 'active',
      pickupLat: map['pickupLat'] != null ? (map['pickupLat'] as num).toDouble() : null,
      pickupLng: map['pickupLng'] != null ? (map['pickupLng'] as num).toDouble() : null,
      dropoffLat: map['dropoffLat'] != null ? (map['dropoffLat'] as num).toDouble() : null,
      dropoffLng: map['dropoffLng'] != null ? (map['dropoffLng'] as num).toDouble() : null,
      driverLat: map['driverLat'] != null ? (map['driverLat'] as num).toDouble() : null,
      driverLng: map['driverLng'] != null ? (map['driverLng'] as num).toDouble() : null,
      distanceKm: map['distanceKm'] != null ? (map['distanceKm'] as num).toDouble() : null,
      durationMins: map['durationMins'] != null ? (map['durationMins'] as num).toInt() : null,
      fare: map['fare'] != null ? (map['fare'] as num).toDouble() : null,
      rideCategory: map['rideCategory'],
      driverName: map['driverName'],
      driverPhone: map['driverPhone'],
      driverRating: map['driverRating'],
    );
  }

  String toJson() => json.encode(toMap());

  factory RideModel.fromJson(String source) =>
      RideModel.fromMap(json.decode(source));
}
