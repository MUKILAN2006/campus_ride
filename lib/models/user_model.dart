import 'dart:convert';

class UserModel {
  final String id;
  final String fullName;
  final String email;
  final String phone;
  final String password;
  final String? vehicleMakeModel;
  final String? vehicleNumber;
  final int? seatCapacity;

  UserModel({
    required this.id,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.password,
    this.vehicleMakeModel,
    this.vehicleNumber,
    this.seatCapacity,
  });

  bool get hasVehicle =>
      vehicleMakeModel != null &&
      vehicleMakeModel!.trim().isNotEmpty &&
      vehicleNumber != null &&
      vehicleNumber!.trim().isNotEmpty;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fullName': fullName,
      'email': email,
      'phone': phone,
      'password': password,
      'vehicleMakeModel': vehicleMakeModel,
      'vehicleNumber': vehicleNumber,
      'seatCapacity': seatCapacity,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'] ?? '',
      fullName: map['fullName'] ?? '',
      email: map['email'] ?? '',
      phone: map['phone'] ?? '',
      password: map['password'] ?? '',
      vehicleMakeModel: map['vehicleMakeModel'],
      vehicleNumber: map['vehicleNumber'],
      seatCapacity: map['seatCapacity'] != null
          ? int.tryParse(map['seatCapacity'].toString())
          : null,
    );
  }

  String toJson() => json.encode(toMap());

  factory UserModel.fromJson(String source) =>
      UserModel.fromMap(json.decode(source));

  UserModel copyWith({
    String? id,
    String? fullName,
    String? email,
    String? phone,
    String? password,
    String? vehicleMakeModel,
    String? vehicleNumber,
    int? seatCapacity,
  }) {
    return UserModel(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      password: password ?? this.password,
      vehicleMakeModel: vehicleMakeModel ?? this.vehicleMakeModel,
      vehicleNumber: vehicleNumber ?? this.vehicleNumber,
      seatCapacity: seatCapacity ?? this.seatCapacity,
    );
  }
}
