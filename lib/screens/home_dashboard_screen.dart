import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../models/ride_model.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'offer_ride_screen.dart';
import 'request_ride_screen.dart';
import 'ride_history_screen.dart';
import 'profile_screen.dart';

class HomeDashboardScreen extends StatefulWidget {
  final UserModel user;

  const HomeDashboardScreen({super.key, required this.user});

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  late UserModel _currentUser;
  List<RideModel> _userHistory = [];
  int _offeredCount = 0;
  int _requestedCount = 0;

  @override
  void initState() {
    super.initState();
    _currentUser = widget.user;
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    try {
      final storage = await StorageService.getInstance();
      final history = await storage.getUserHistory(_currentUser.id);
      if (!mounted) return;
      setState(() {
        _userHistory = history;
        _offeredCount = history.where((r) => r.type == 'offered').length;
        _requestedCount = history.where((r) => r.type == 'requested').length;
      });
    } catch (_) {}
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Log Out'),
        content: const Text(
          'Are you sure you want to log out? Your account and ride data remain safely stored offline on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final storage = await StorageService.getInstance();
      await storage.logout();

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  Widget _buildDashboardCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.bgDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppTheme.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: const [
            Icon(Icons.directions_car_filled_rounded, color: AppTheme.primaryEmerald),
            SizedBox(width: 8),
            Text(
              'CampusRide',
              style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.bgDark),
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            tooltip: 'Logout',
            onPressed: _handleLogout,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadDashboardData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // User Greeting Banner
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: AppTheme.cardHeaderGradient,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: AppTheme.primaryEmerald,
                          child: Text(
                            _currentUser.fullName.isNotEmpty
                                ? _currentUser.fullName[0].toUpperCase()
                                : 'U',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hello, ${_currentUser.fullName}!',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                _currentUser.email,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryEmerald.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppTheme.primaryEmerald.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            children: const [
                              Icon(Icons.wifi_off_rounded, size: 12, color: Colors.white),
                              SizedBox(width: 4),
                              Text(
                                'Offline Mode',
                                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Divider(color: Colors.white24, height: 1),
                    const SizedBox(height: 14),

                    // Quick Stats Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            Text(
                              '$_offeredCount',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryEmerald,
                              ),
                            ),
                            const Text(
                              'Offered',
                              style: TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                        Container(width: 1, height: 30, color: Colors.white24),
                        Column(
                          children: [
                            Text(
                              '$_requestedCount',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.accentIndigoLight,
                              ),
                            ),
                            const Text(
                              'Requested',
                              style: TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                        Container(width: 1, height: 30, color: Colors.white24),
                        Column(
                          children: [
                            Text(
                              '${_userHistory.length}',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.amberAccent,
                              ),
                            ),
                            const Text(
                              'Total Rides',
                              style: TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              const Text(
                'Dashboard Services',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.bgDark,
                ),
              ),
              const SizedBox(height: 14),

              // Offer Ride Action Card
              _buildDashboardCard(
                title: 'Offer a Ride',
                subtitle: 'Post source, destination, date & available seats',
                icon: Icons.time_to_leave_rounded,
                color: AppTheme.primaryEmerald,
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => OfferRideScreen(user: _currentUser),
                    ),
                  );
                  _loadDashboardData();
                },
              ),
              const SizedBox(height: 14),

              // Request Ride Action Card
              _buildDashboardCard(
                title: 'Request a Ride',
                subtitle: 'Find matching rides offered by campus drivers',
                icon: Icons.person_pin_circle_rounded,
                color: AppTheme.accentIndigo,
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RequestRideScreen(user: _currentUser),
                    ),
                  );
                  _loadDashboardData();
                },
              ),
              const SizedBox(height: 14),

              // Ride History Card
              _buildDashboardCard(
                title: 'Ride History',
                subtitle: 'View previous rides offered and requested',
                icon: Icons.history_rounded,
                color: Colors.amber.shade800,
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RideHistoryScreen(user: _currentUser),
                    ),
                  );
                  _loadDashboardData();
                },
              ),
              const SizedBox(height: 14),

              // Profile Card
              _buildDashboardCard(
                title: 'Profile & Vehicle Details',
                subtitle: 'Manage student details and vehicle capacity',
                icon: Icons.account_circle_rounded,
                color: Colors.purple,
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ProfileScreen(
                        user: _currentUser,
                        onProfileUpdated: (updated) {
                          setState(() {
                            _currentUser = updated;
                          });
                        },
                      ),
                    ),
                  );
                  _loadDashboardData();
                },
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
