import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import '../models/ride_model.dart';
import '../models/user_model.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import 'map_ride_screen.dart';

class RequestRideScreen extends StatefulWidget {
  final UserModel user;

  const RequestRideScreen({super.key, required this.user});

  @override
  State<RequestRideScreen> createState() => _RequestRideScreenState();
}

class _RequestRideScreenState extends State<RequestRideScreen> {
  final _formKey = GlobalKey<FormState>();
  final _sourceController = TextEditingController();
  final _destinationController = TextEditingController();
  LatLng? _sourceLatLng;
  LatLng? _destinationLatLng;

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  bool _hasSearched = false;
  bool _isLoading = false;
  List<RideModel> _matchingRides = [];

  Future<void> _pickLocationOnSatelliteMap(SelectionTarget target) async {
    final result = await Navigator.of(context).push<LocationPickResult>(
      MaterialPageRoute(
        builder: (_) => MapRideScreen(
          user: widget.user,
          mode: MapScreenMode.pickLocation,
          pickTarget: target,
          initialAddress: target == SelectionTarget.pickup
              ? _sourceController.text
              : _destinationController.text,
          initialPickup: target == SelectionTarget.pickup ? _sourceLatLng : null,
          initialDropoff: target == SelectionTarget.dropoff ? _destinationLatLng : null,
        ),
      ),
    );

    if (result != null) {
      setState(() {
        if (target == SelectionTarget.pickup) {
          _sourceController.text = result.address;
          _sourceLatLng = result.position;
        } else {
          _destinationController.text = result.address;
          _destinationLatLng = result.position;
        }
      });
    }
  }

  void _openSatelliteLiveMapBooking() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MapRideScreen(
          user: widget.user,
          mode: MapScreenMode.routeAndTrack,
          initialAddress: _sourceController.text,
          initialPickup: _sourceLatLng,
          initialDropoff: _destinationLatLng,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _selectedTime = TimeOfDay.now();
  }

  @override
  void dispose() {
    _sourceController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _performSearch() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _hasSearched = true;
    });

    try {
      final formattedDate =
          _selectedDate != null ? DateFormat('yyyy-MM-dd').format(_selectedDate!) : '';

      final storage = await StorageService.getInstance();
      final results = await storage.searchMatchingRides(
        source: _sourceController.text,
        destination: _destinationController.text,
        date: formattedDate,
        currentUserId: widget.user.id,
      );

      if (!mounted) return;

      setState(() {
        _matchingRides = results;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error searching for rides.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _recordRideRequestAndBook(RideModel ride) async {
    final storage = await StorageService.getInstance();

    final requestedRideLog = RideModel(
      id: 'req_${DateTime.now().millisecondsSinceEpoch}',
      userId: widget.user.id,
      userName: widget.user.fullName,
      userPhone: widget.user.phone,
      source: ride.source,
      destination: ride.destination,
      date: ride.date,
      time: ride.time,
      availableSeats: 1,
      type: 'requested',
      createdAt: DateTime.now().toIso8601String(),
      status: 'active',
      pickupLat: _sourceLatLng?.latitude,
      pickupLng: _sourceLatLng?.longitude,
      dropoffLat: _destinationLatLng?.latitude,
      dropoffLng: _destinationLatLng?.longitude,
    );

    await storage.addRide(requestedRideLog);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.directions_car, color: AppTheme.primaryEmerald, size: 28),
            SizedBox(width: 10),
            Text('Contact Driver'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Driver: ${ride.userName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 6),
            Text('Phone: ${ride.userPhone}', style: const TextStyle(color: AppTheme.accentIndigo, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            if (ride.vehicleDetails != null)
              Text('Vehicle: ${ride.vehicleDetails}', style: const TextStyle(color: AppTheme.textMuted)),
            const SizedBox(height: 12),
            const Text(
              'Your ride request has been saved in your Ride History. You can call or message the driver directly!',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveAsGeneralRequest() async {
    if (!_formKey.currentState!.validate()) return;

    final formattedDate =
        _selectedDate != null ? DateFormat('yyyy-MM-dd').format(_selectedDate!) : DateFormat('yyyy-MM-dd').format(DateTime.now());
    final formattedTime =
        _selectedTime != null ? _selectedTime!.format(context) : 'Anytime';

    final storage = await StorageService.getInstance();
    final newReq = RideModel(
      id: 'req_${DateTime.now().millisecondsSinceEpoch}',
      userId: widget.user.id,
      userName: widget.user.fullName,
      userPhone: widget.user.phone,
      source: _sourceController.text.trim(),
      destination: _destinationController.text.trim(),
      date: formattedDate,
      time: formattedTime,
      availableSeats: 1,
      type: 'requested',
      createdAt: DateTime.now().toIso8601String(),
      status: 'active',
      pickupLat: _sourceLatLng?.latitude,
      pickupLng: _sourceLatLng?.longitude,
      dropoffLat: _destinationLatLng?.latitude,
      dropoffLng: _destinationLatLng?.longitude,
    );

    await storage.addRide(newReq);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Your ride request has been logged in Ride History! Drivers can now match with you.'),
        backgroundColor: AppTheme.primaryEmerald,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = _selectedDate != null
        ? DateFormat('EEE, MMM d').format(_selectedDate!)
        : 'Any Date';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Find a Ride'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppTheme.bgDark,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Search Box Card
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.search_rounded, color: AppTheme.accentIndigo, size: 24),
                          SizedBox(width: 10),
                          Text(
                            'Search Available Rides',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.bgDark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      TextFormField(
                        controller: _sourceController,
                        decoration: InputDecoration(
                          labelText: 'Desired Source',
                          hintText: 'e.g. North Campus Library',
                          prefixIcon: const Icon(Icons.my_location, color: AppTheme.primaryEmerald),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.satellite_alt_rounded, color: AppTheme.primaryEmerald),
                            tooltip: 'Pick on Satellite Map',
                            onPressed: () => _pickLocationOnSatelliteMap(SelectionTarget.pickup),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter source location';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      TextFormField(
                        controller: _destinationController,
                        decoration: InputDecoration(
                          labelText: 'Desired Destination',
                          hintText: 'e.g. Engineering Block',
                          prefixIcon: const Icon(Icons.location_on, color: AppTheme.accentIndigo),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.satellite_alt_rounded, color: AppTheme.accentIndigo),
                            tooltip: 'Pick on Satellite Map',
                            onPressed: () => _pickLocationOnSatelliteMap(SelectionTarget.dropoff),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter destination';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      InkWell(
                        onTap: _pickDate,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today, size: 18, color: AppTheme.primaryEmerald),
                              const SizedBox(width: 10),
                              Text('Travel Date: $dateStr', style: const TextStyle(fontWeight: FontWeight.w600)),
                              const Spacer(),
                              const Icon(Icons.arrow_drop_down, color: AppTheme.textMuted),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      ElevatedButton.icon(
                        onPressed: _isLoading ? null : _performSearch,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accentIndigo,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: _isLoading
                            ? const SizedBox.shrink()
                            : const Icon(Icons.search),
                        label: _isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Text('Find Matching Rides', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),

                      // Direct Satellite Route & Live Tracking Button
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _openSatelliteLiveMapBooking,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryEmerald,
                          side: const BorderSide(color: AppTheme.primaryEmerald),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.map_rounded, size: 18),
                        label: const Text(
                          'Book & Track on Satellite Map',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Search Results Section
            if (_hasSearched) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Matching Rides (${_matchingRides.length})',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.bgDark),
                  ),
                  if (_matchingRides.isEmpty)
                    TextButton.icon(
                      onPressed: _saveAsGeneralRequest,
                      icon: const Icon(Icons.add_alert_outlined, size: 18),
                      label: const Text('Post Request'),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              if (_matchingRides.isEmpty)
                Card(
                  color: Colors.amber.shade50,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(Icons.directions_car_outlined, size: 48, color: Colors.amber.shade800),
                        const SizedBox(height: 12),
                        Text(
                          'No direct matching rides found',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber.shade900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'No offered rides match your exact route right now. You can log this request to your history so drivers can reach out to you!',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: Colors.black.withValues(alpha: 0.7)),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _saveAsGeneralRequest,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber.shade800,
                          ),
                          icon: const Icon(Icons.bookmark_add),
                          label: const Text('Save Request to History'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _matchingRides.length,
                  itemBuilder: (ctx, index) {
                    final ride = _matchingRides[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: AppTheme.primaryEmerald.withValues(alpha: 0.15),
                                  child: Text(
                                    ride.userName.isNotEmpty ? ride.userName[0].toUpperCase() : 'D',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primaryEmerald,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        ride.userName,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                      ),
                                      if (ride.vehicleDetails != null)
                                        Text(
                                          ride.vehicleDetails!,
                                          style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                        ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryEmerald.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '${ride.availableSeats} seat(s)',
                                    style: const TextStyle(
                                      color: AppTheme.primaryEmerald,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 24),

                            Row(
                              children: [
                                const Icon(Icons.circle, size: 10, color: AppTheme.primaryEmerald),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'From: ${ride.source}',
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.location_on, size: 14, color: AppTheme.accentIndigo),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'To: ${ride.destination}',
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            Row(
                              children: [
                                const Icon(Icons.calendar_today, size: 14, color: AppTheme.textMuted),
                                const SizedBox(width: 6),
                                Text(ride.date, style: const TextStyle(fontSize: 13, color: AppTheme.textMuted)),
                                const SizedBox(width: 16),
                                const Icon(Icons.access_time, size: 14, color: AppTheme.textMuted),
                                const SizedBox(width: 6),
                                Text(ride.time, style: const TextStyle(fontSize: 13, color: AppTheme.textMuted)),
                                const Spacer(),
                                ElevatedButton(
                                  onPressed: () => _recordRideRequestAndBook(ride),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    backgroundColor: AppTheme.primaryEmerald,
                                  ),
                                  child: const Text('Connect Driver', style: TextStyle(fontSize: 13)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }
}
