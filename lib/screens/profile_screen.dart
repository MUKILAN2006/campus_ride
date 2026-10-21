import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

class ProfileScreen extends StatefulWidget {
  final UserModel user;
  final Function(UserModel updatedUser) onProfileUpdated;

  const ProfileScreen({
    super.key,
    required this.user,
    required this.onProfileUpdated,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _fullNameController;
  late TextEditingController _phoneController;
  late TextEditingController _vehicleMakeController;
  late TextEditingController _vehicleNumberController;

  late int _seatCapacity;
  bool _hasVehicle = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _fullNameController = TextEditingController(text: widget.user.fullName);
    _phoneController = TextEditingController(text: widget.user.phone);
    _vehicleMakeController = TextEditingController(text: widget.user.vehicleMakeModel ?? '');
    _vehicleNumberController = TextEditingController(text: widget.user.vehicleNumber ?? '');

    _hasVehicle = widget.user.hasVehicle;
    _seatCapacity = widget.user.seatCapacity ?? 3;
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _vehicleMakeController.dispose();
    _vehicleNumberController.dispose();
    super.dispose();
  }

  Future<void> _saveProfileChanges() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final updatedUser = widget.user.copyWith(
        fullName: _fullNameController.text.trim(),
        phone: _phoneController.text.trim(),
        vehicleMakeModel: _hasVehicle ? _vehicleMakeController.text.trim() : null,
        vehicleNumber: _hasVehicle ? _vehicleNumberController.text.trim() : null,
        seatCapacity: _hasVehicle ? _seatCapacity : null,
      );

      final storage = await StorageService.getInstance();
      await storage.updateCurrentUserProfile(updatedUser);
      widget.onProfileUpdated(updatedUser);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated successfully in local storage!'),
          backgroundColor: AppTheme.primaryEmerald,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update profile.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile & Vehicle'),
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
              // Avatar & Email Info Card
              Center(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 44,
                      backgroundColor: AppTheme.primaryEmerald,
                      child: Text(
                        widget.user.fullName.isNotEmpty
                            ? widget.user.fullName[0].toUpperCase()
                            : 'U',
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.user.fullName,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.bgDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.user.email,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              const Text(
                'Personal Information',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.bgDark,
                ),
              ),
              const SizedBox(height: 14),

              // Full Name
              TextFormField(
                controller: _fullNameController,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Full name is required';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Phone Number
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Phone number is required';
                  if (val.replaceAll(RegExp(r'\D'), '').length < 10) {
                    return 'Must contain at least 10 digits';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              const Text(
                'Vehicle Details',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.bgDark,
                ),
              ),
              const SizedBox(height: 10),

              // Vehicle Switch
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: AppTheme.primaryEmerald,
                  title: const Text(
                    'I own/driver a vehicle for ride offering',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  value: _hasVehicle,
                  onChanged: (val) {
                    setState(() => _hasVehicle = val);
                  },
                ),
              ),

              if (_hasVehicle) ...[
                const SizedBox(height: 14),
                TextFormField(
                  controller: _vehicleMakeController,
                  decoration: const InputDecoration(
                    labelText: 'Vehicle Make & Model',
                    hintText: 'e.g. Honda Civic',
                    prefixIcon: Icon(Icons.directions_car_outlined),
                  ),
                  validator: (val) {
                    if (_hasVehicle && (val == null || val.trim().isEmpty)) {
                      return 'Please enter vehicle details';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _vehicleNumberController,
                  decoration: const InputDecoration(
                    labelText: 'License Plate / Number',
                    hintText: 'e.g. ABC-1234',
                    prefixIcon: Icon(Icons.pin_outlined),
                  ),
                  validator: (val) {
                    if (_hasVehicle && (val == null || val.trim().isEmpty)) {
                      return 'Please enter license plate number';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(Icons.airline_seat_recline_normal, color: AppTheme.textMuted),
                    const SizedBox(width: 12),
                    const Text('Default Seat Capacity:'),
                    const Spacer(),
                    IconButton(
                      onPressed: _seatCapacity > 1
                          ? () => setState(() => _seatCapacity--)
                          : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text(
                      '$_seatCapacity',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      onPressed: _seatCapacity < 8
                          ? () => setState(() => _seatCapacity++)
                          : null,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 36),

              ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveProfileChanges,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                icon: _isSaving ? const SizedBox.shrink() : const Icon(Icons.save_rounded),
                label: _isSaving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text(
                        'Save Changes',
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
