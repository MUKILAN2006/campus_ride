import 'package:flutter/material.dart';
import '../models/ride_model.dart';
import '../models/user_model.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

class RideHistoryScreen extends StatefulWidget {
  final UserModel user;

  const RideHistoryScreen({super.key, required this.user});

  @override
  State<RideHistoryScreen> createState() => _RideHistoryScreenState();
}

class _RideHistoryScreenState extends State<RideHistoryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<RideModel> _allRides = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadHistory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      final storage = await StorageService.getInstance();
      final userRides = await storage.getUserHistory(widget.user.id);
      if (!mounted) return;
      setState(() {
        _allRides = userRides;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load ride history.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildRideList(List<RideModel> rides) {
    if (rides.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: const [
              Icon(Icons.history_toggle_off_rounded, size: 64, color: AppTheme.textMuted),
              SizedBox(height: 16),
              Text(
                'No Ride Activity Recorded',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.bgDark),
              ),
              SizedBox(height: 6),
              Text(
                'Offered and requested rides will automatically appear here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: rides.length,
      itemBuilder: (ctx, index) {
        final ride = rides[index];
        final isOffer = ride.type == 'offered';

        return Card(
          margin: const EdgeInsets.only(bottom: 14),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(18.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: isOffer
                            ? AppTheme.primaryEmerald.withValues(alpha: 0.15)
                            : AppTheme.accentIndigo.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isOffer ? Icons.time_to_leave : Icons.hail,
                            size: 14,
                            color: isOffer ? AppTheme.primaryEmerald : AppTheme.accentIndigo,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isOffer ? 'RIDE OFFERED' : 'RIDE REQUESTED',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isOffer ? AppTheme.primaryEmerald : AppTheme.accentIndigo,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Text(
                      ride.date,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        const Icon(Icons.circle, size: 12, color: AppTheme.primaryEmerald),
                        Container(width: 2, height: 20, color: Colors.grey.shade300),
                        const Icon(Icons.location_on, size: 14, color: AppTheme.accentIndigo),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ride.source,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            ride.destination,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (ride.distanceKm != null || ride.fare != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (ride.rideCategory != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryEmerald.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            ride.rideCategory!,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryEmerald,
                            ),
                          ),
                        ),
                      if (ride.distanceKm != null)
                        Text(
                          '${ride.distanceKm} km',
                          style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                        ),
                      const Spacer(),
                      if (ride.fare != null)
                        Text(
                          '\$${ride.fare!.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryEmerald,
                          ),
                        ),
                    ],
                  ),
                ],
                const Divider(height: 24),

                Row(
                  children: [
                    const Icon(Icons.access_time_rounded, size: 16, color: AppTheme.textMuted),
                    const SizedBox(width: 6),
                    Text(
                      ride.time,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 16),
                    const Icon(Icons.event_seat_rounded, size: 16, color: AppTheme.textMuted),
                    const SizedBox(width: 6),
                    Text(
                      '${ride.availableSeats} seat(s)',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        ride.status.toUpperCase(),
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black54),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final offeredRides = _allRides.where((r) => r.type == 'offered').toList();
    final requestedRides = _allRides.where((r) => r.type == 'requested').toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ride History'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppTheme.bgDark,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primaryEmerald,
          unselectedLabelColor: AppTheme.textMuted,
          indicatorColor: AppTheme.primaryEmerald,
          indicatorWeight: 3,
          tabs: [
            Tab(text: 'All (${_allRides.length})'),
            Tab(text: 'Offered (${offeredRides.length})'),
            Tab(text: 'Requested (${requestedRides.length})'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadHistory,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildRideList(_allRides),
                  _buildRideList(offeredRides),
                  _buildRideList(requestedRides),
                ],
              ),
            ),
    );
  }
}
