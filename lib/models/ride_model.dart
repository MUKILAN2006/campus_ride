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
  final String status; // 'active', 'completed', 'cancelled'

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
  });

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
    );
  }

  String toJson() => json.encode(toMap());

  factory RideModel.fromJson(String source) =>
      RideModel.fromMap(json.decode(source));
}
