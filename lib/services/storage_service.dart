import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../models/ride_model.dart';

class StorageService {
  static const String _keyUsers = 'campus_ride_users';
  static const String _keyCurrentUser = 'campus_ride_current_user';
  static const String _keyRides = 'campus_ride_rides';
  static const String _keyActiveRide = 'campus_ride_active_ride';

  static StorageService? _instance;
  static SharedPreferences? _prefs;

  StorageService._();

  static Future<StorageService> getInstance() async {
    _instance ??= StorageService._();
    _prefs ??= await SharedPreferences.getInstance();
    return _instance!;
  }

  // --- Auth & Users ---

  Future<List<UserModel>> getUsers() async {
    final List<String>? usersJson = _prefs?.getStringList(_keyUsers);
    if (usersJson == null) return [];
    return usersJson.map((str) => UserModel.fromJson(str)).toList();
  }

  Future<bool> registerUser(UserModel user) async {
    final users = await getUsers();
    final String cleanEmail = user.email.trim().toLowerCase();

    // Check if email already exists
    if (users.any((u) => u.email.trim().toLowerCase() == cleanEmail)) {
      return false; // Email taken
    }

    users.add(user);
    final List<String> updatedList = users.map((u) => u.toJson()).toList();
    await _prefs?.setStringList(_keyUsers, updatedList);
    await saveCurrentUser(user);
    return true;
  }

  Future<UserModel?> authenticateUser(String emailOrUsername, String password) async {
    final users = await getUsers();
    final String cleanInput = emailOrUsername.trim().toLowerCase();

    for (var u in users) {
      if ((u.email.trim().toLowerCase() == cleanInput ||
              u.fullName.trim().toLowerCase() == cleanInput) &&
          u.password == password) {
        await saveCurrentUser(u);
        return u;
      }
    }
    return null;
  }

  Future<void> saveCurrentUser(UserModel user) async {
    await _prefs?.setString(_keyCurrentUser, user.toJson());
  }

  UserModel? getCurrentUser() {
    final String? userJson = _prefs?.getString(_keyCurrentUser);
    if (userJson == null || userJson.isEmpty) return null;
    try {
      return UserModel.fromJson(userJson);
    } catch (_) {
      return null;
    }
  }

  Future<void> updateCurrentUserProfile(UserModel updatedUser) async {
    final users = await getUsers();
    final index = users.indexWhere((u) => u.id == updatedUser.id);
    if (index != -1) {
      users[index] = updatedUser;
      final List<String> updatedList = users.map((u) => u.toJson()).toList();
      await _prefs?.setStringList(_keyUsers, updatedList);
    }
    await saveCurrentUser(updatedUser);
  }

  Future<void> logout() async {
    await _prefs?.remove(_keyCurrentUser);
  }

  // --- Rides Management ---

  Future<List<RideModel>> getRides() async {
    final List<String>? ridesJson = _prefs?.getStringList(_keyRides);
    if (ridesJson == null) return [];
    return ridesJson.map((str) => RideModel.fromJson(str)).toList();
  }

  Future<void> addRide(RideModel ride) async {
    final rides = await getRides();
    rides.insert(0, ride); // newest first
    final List<String> updatedList = rides.map((r) => r.toJson()).toList();
    await _prefs?.setStringList(_keyRides, updatedList);
  }

  Future<void> updateRide(RideModel updatedRide) async {
    final rides = await getRides();
    final index = rides.indexWhere((r) => r.id == updatedRide.id);
    if (index != -1) {
      rides[index] = updatedRide;
      final List<String> updatedList = rides.map((r) => r.toJson()).toList();
      await _prefs?.setStringList(_keyRides, updatedList);
    }
  }

  Future<void> updateRideStatus(String rideId, String newStatus) async {
    final rides = await getRides();
    final index = rides.indexWhere((r) => r.id == rideId);
    if (index != -1) {
      final updated = rides[index].copyWith(status: newStatus);
      rides[index] = updated;
      final List<String> updatedList = rides.map((r) => r.toJson()).toList();
      await _prefs?.setStringList(_keyRides, updatedList);

      // Also update active ride if it matches
      final active = getActiveRide();
      if (active != null && active.id == rideId) {
        await saveActiveRide(updated);
      }
    }
  }

  Future<void> saveActiveRide(RideModel ride) async {
    await _prefs?.setString(_keyActiveRide, ride.toJson());
  }

  RideModel? getActiveRide() {
    final String? jsonStr = _prefs?.getString(_keyActiveRide);
    if (jsonStr == null || jsonStr.isEmpty) return null;
    try {
      return RideModel.fromJson(jsonStr);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearActiveRide() async {
    await _prefs?.remove(_keyActiveRide);
  }

  Future<List<RideModel>> getUserHistory(String userId) async {
    final rides = await getRides();
    return rides.where((r) => r.userId == userId).toList();
  }

  Future<List<RideModel>> searchMatchingRides({
    required String source,
    required String destination,
    required String date,
    required String currentUserId,
  }) async {
    final rides = await getRides();
    final cleanSource = source.trim().toLowerCase();
    final cleanDest = destination.trim().toLowerCase();

    return rides.where((ride) {
      // Must be an offered ride from another user or active offer
      if (ride.type != 'offered') return false;
      if (ride.availableSeats <= 0) return false;

      final rideSource = ride.source.trim().toLowerCase();
      final rideDest = ride.destination.trim().toLowerCase();

      bool sourceMatch = rideSource.contains(cleanSource) || cleanSource.contains(rideSource);
      bool destMatch = rideDest.contains(cleanDest) || cleanDest.contains(rideDest);
      bool dateMatch = date.isEmpty || ride.date == date;

      return sourceMatch && destMatch && dateMatch;
    }).toList();
  }
}
