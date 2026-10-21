import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import '../models/ride_model.dart';
import '../models/user_model.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import 'map_ride_screen.dart';

class OfferRideScreen extends StatefulWidget {
  final UserModel user;

  const OfferRideScreen({super.key, required this.user});

  @override
  State<OfferRideScreen> createState() => _OfferRideScreenState();
}

class _OfferRideScreenState extends State<OfferRideScreen> {
  final _formKey = GlobalKey<FormState>();
  final _sourceController = TextEditingController();
  final _destinationController = TextEditingController();
  LatLng? _sourceLatLng;
  LatLng? _destinationLatLng;

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  int _availableSeats = 3;
  bool _isLoading = false;

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

  void _previewRouteOnMap() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MapRideScreen(
          user: widget.user,
          mode: MapScreenMode.previewRoute,
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
    if (widget.user.seatCapacity != null && widget.user.seatCapacity! > 0) {
      _availableSeats = widget.user.seatCapacity!;
    }
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
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.primaryEmerald,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  Future<void> _submitOffer() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a travel date')),
      );
      return;
    }
    if (_selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a departure time')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final formattedDate = DateFormat('yyyy-MM-dd').format(_selectedDate!);
      final formattedTime = _selectedTime!.format(context);

      String? vehicleInfo;
      if (widget.user.vehicleMakeModel != null && widget.user.vehicleNumber != null) {
        vehicleInfo = '${widget.user.vehicleMakeModel} (${widget.user.vehicleNumber})';
      }

      final newRide = RideModel(
        id: 'ride_${DateTime.now().millisecondsSinceEpoch}',
        userId: widget.user.id,
        userName: widget.user.fullName,
        userPhone: widget.user.phone,
        source: _sourceController.text.trim(),
        destination: _destinationController.text.trim(),
        date: formattedDate,
        time: formattedTime,
        availableSeats: _availableSeats,
        type: 'offered',
        vehicleDetails: vehicleInfo,
        createdAt: DateTime.now().toIso8601String(),
        status: 'active',
        pickupLat: _sourceLatLng?.latitude,
        pickupLng: _sourceLatLng?.longitude,
        dropoffLat: _destinationLatLng?.latitude,
        dropoffLng: _destinationLatLng?.longitude,
      );

      final storage = await StorageService.getInstance();
      await storage.addRide(newRide);

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.check_circle_rounded, color: AppTheme.primaryEmerald, size: 28),
              SizedBox(width: 10),
              Text('Ride Offered!'),
            ],
          ),
          content: Text(
            'Your ride from ${_sourceController.text} to ${_destinationController.text} on $formattedDate at $formattedTime has been saved locally and made available to campus peers.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pop(true);
              },
              child: const Text('Back to Dashboard'),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to post ride offer.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = _selectedDate != null
        ? DateFormat('EEE, MMM d, yyyy').format(_selectedDate!)
        : 'Select Date';
    final timeStr = _selectedTime != null
        ? _selectedTime!.format(context)
        : 'Select Time';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Offer a Ride'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppTheme.bgDark,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.time_to_leave_rounded, color: Colors.white, size: 32),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Share Your Journey',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Offer seats to fellow campus members',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Source Location
              TextFormField(
                controller: _sourceController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Source Location *',
                  hintText: 'e.g. North Campus Library / Hostel A',
                  prefixIcon: const Icon(Icons.my_location_rounded, color: AppTheme.primaryEmerald),
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
              const SizedBox(height: 18),

              // Destination Location
              TextFormField(
                controller: _destinationController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Destination *',
                  hintText: 'e.g. Engineering Building / Metro Station',
                  prefixIcon: const Icon(Icons.location_on_rounded, color: AppTheme.accentIndigo),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.satellite_alt_rounded, color: AppTheme.accentIndigo),
                    tooltip: 'Pick on Satellite Map',
                    onPressed: () => _pickLocationOnSatelliteMap(SelectionTarget.dropoff),
                  ),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter destination location';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // Preview Route on Satellite Map Button
              if (_sourceController.text.isNotEmpty && _destinationController.text.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primaryEmerald,
                      side: const BorderSide(color: AppTheme.primaryEmerald),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    ),
                    icon: const Icon(Icons.map_rounded, size: 20),
                    label: const Text(
                      'Preview Route on Satellite Map',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: _previewRouteOnMap,
                  ),
                ),
              const SizedBox(height: 6),

              // Date & Time Pickers
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Travel Date',
                              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.calendar_today_rounded, size: 18, color: AppTheme.primaryEmerald),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    dateStr,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: _pickTime,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Departure Time',
                              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.access_time_rounded, size: 18, color: AppTheme.accentIndigo),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    timeStr,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Available Seats Selector
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.event_seat_rounded, color: AppTheme.primaryEmerald),
                    const SizedBox(width: 14),
                    const Text(
                      'Available Seats:',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: _availableSeats > 1
                          ? () => setState(() => _availableSeats--)
                          : null,
                      icon: const Icon(Icons.remove_circle_outline, color: AppTheme.accentIndigo),
                    ),
                    Text(
                      '$_availableSeats',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      onPressed: _availableSeats < 6
                          ? () => setState(() => _availableSeats++)
                          : null,
                      icon: const Icon(Icons.add_circle_outline, color: AppTheme.primaryEmerald),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 36),

              // Offer Button
              ElevatedButton(
                onPressed: _isLoading ? null : _submitOffer,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : const Text(
                        'Post Ride Offer',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
