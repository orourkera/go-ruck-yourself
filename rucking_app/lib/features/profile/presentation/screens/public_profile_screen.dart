import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/profile/presentation/bloc/public_profile_bloc.dart';
import 'package:rucking_app/features/profile/presentation/widgets/profile_header.dart';
import 'package:rucking_app/features/profile/presentation/widgets/profile_stats_grid.dart';
import 'package:rucking_app/features/profile/domain/entities/user_profile_stats.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/shared/widgets/user_avatar.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

class PublicProfileScreen extends StatefulWidget {
  final String userId;
  const PublicProfileScreen({Key? key, required this.userId}) : super(key: key);

  @override
  _PublicProfileScreenState createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    context.read<PublicProfileBloc>().add(LoadPublicProfile(widget.userId));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Profile')),
      body: BlocBuilder<PublicProfileBloc, PublicProfileState>(
        builder: (context, state) {
          if (state is PublicProfileLoading) return Center(child: CircularProgressIndicator());
          if (state is PublicProfileError) return Center(child: Text(state.message));
          if (state is PublicProfileLoaded) {
            return SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    // Avatar + follower/following counts row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Avatar
                        UserAvatar(
                          avatarUrl: state.profile.avatarUrl,
                          username: state.profile.username,
                          size: 80,
                          onTap: null,
                        ),
                        const SizedBox(width: 24),
                        // Counts
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildCountColumn(
                                context,
                                label: 'Followers',
                                count: state.stats?.followersCount ?? 0,
                                onTap: () => Navigator.pushNamed(context, '/profile/${state.profile.id}/followers'),
                              ),
                              _buildCountColumn(
                                context,
                                label: 'Following',
                                count: state.stats?.followingCount ?? 0,
                                onTap: () => Navigator.pushNamed(context, '/profile/${state.profile.id}/following'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Username
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        state.profile.username,
                        style: AppTextStyles.headlineMedium.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Follow button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          context.read<PublicProfileBloc>().add(ToggleFollow(widget.userId));
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: state.isFollowing ? Colors.grey : AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          minimumSize: const Size(double.infinity, 44),
                        ),
                        child: Text(
                          state.isFollowing ? 'Following' : 'Follow',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Stats section
                    if (!state.profile.isPrivateProfile) ...[
                      BlocBuilder<AuthBloc, AuthState>(
                        builder: (context, authState) {
                          bool preferMetric = true; // Default to metric
                          if (authState is Authenticated) {
                            preferMetric = authState.user.preferMetric;
                          }
                          return ProfileStatsGrid(
                            stats: state.stats ?? UserProfileStats.empty(),
                            preferMetric: preferMetric,
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                      TabBar(controller: _tabController, tabs: [Tab(text: 'Stats'), Tab(text: 'Clubs'), Tab(text: 'Recent')]),
                      SizedBox(
                        height: 300,
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _buildStatsTab(state.stats),
                            _buildClubsTab(state.clubs),
                            _buildRecentTab(state.recentRucks),
                          ],
                        ),
                      ),
                    ] else
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Column(
                            children: [
                              Icon(Icons.lock, size: 64, color: Colors.grey),
                              const SizedBox(height: 16),
                              Text(
                                'This profile is private',
                                style: AppTextStyles.titleMedium.copyWith(color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }
          return SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildCountColumn(BuildContext context, {required String label, required int count, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            count.toString(),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _buildStatsTab(UserProfileStats? stats) {
    if (stats == null) return Center(child: Text('No stats available'));
    
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          _buildStatRow('Total Rucks', stats.totalRucks.toString()),
          _buildStatRow('Total Distance', '${stats.totalDistanceKm.toStringAsFixed(1)} km'),
          _buildStatRow('Total Duration', '${(stats.totalDurationSeconds / 3600).toStringAsFixed(1)} hours'),
          _buildStatRow('Calories Burned', stats.totalCaloriesBurned.toStringAsFixed(0)),
          _buildStatRow('Elevation Gain', '${stats.totalElevationGainM.toStringAsFixed(0)} m'),
          _buildStatRow('Duels Won', stats.duelsWon.toString()),
          _buildStatRow('Events Completed', stats.eventsCompleted.toString()),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyles.bodyMedium),
          Text(value, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildClubsTab(List<dynamic>? clubs) {
    if (clubs == null || clubs.isEmpty) {
      return Center(child: Text('No clubs joined'));
    }
    
    return ListView.builder(
      itemCount: clubs.length,
      itemBuilder: (context, index) {
        final club = clubs[index];
        return ListTile(
          title: Text(club.name ?? 'Unknown Club'),
          subtitle: Text('${club.memberCount ?? 0} members'),
        );
      },
    );
  }

  Widget _buildRecentTab(List<dynamic>? recentRucks) {
    if (recentRucks == null || recentRucks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.directions_run, size: 48, color: Colors.grey[400]),
            SizedBox(height: 16),
            Text('No recent rucks', style: AppTextStyles.bodyMedium.copyWith(color: Colors.grey[600])),
          ],
        ),
      );
    }
    
    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: recentRucks.length,
      itemBuilder: (context, index) {
        final ruck = recentRucks[index];
        return Card(
          margin: EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatRuckTitle(ruck['end_time'] ?? ruck['created_at']),
                      style: AppTextStyles.titleLarge,
                    ),
                    if (ruck['power_points'] != null)
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${ruck['power_points'].toStringAsFixed(0)} PP',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildRuckStat(
                        Icons.straighten,
                        _formatDistance(ruck['distance_km']),
                      ),
                    ),
                    Expanded(
                      child: _buildRuckStat(
                        Icons.timer,
                        _formatDuration(ruck['duration_seconds']),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildRuckStat(
                        Icons.trending_up,
                        _formatElevation(ruck['elevation_gain_m']),
                      ),
                    ),
                    Expanded(
                      child: _buildRuckStat(
                        Icons.local_fire_department,
                        _formatCalories(ruck['calories_burned']),
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

  Widget _buildRuckStat(IconData icon, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        SizedBox(width: 6),
        Text(value, style: AppTextStyles.bodySmall.copyWith(color: Colors.grey[700])),
      ],
    );
  }

  String _formatRuckTitle(String? dateTime) {
    if (dateTime == null) return 'Ruck Session';
    try {
      final date = DateTime.parse(dateTime);
      final now = DateTime.now();
      final difference = now.difference(date).inDays;
      
      if (difference == 0) return 'Today';
      if (difference == 1) return 'Yesterday';
      if (difference < 7) return '${difference} days ago';
      
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return 'Ruck Session';
    }
  }

  String _formatDistance(dynamic distance) {
    if (distance == null) return '0.0 km';
    final distanceKm = distance is double ? distance : double.tryParse(distance.toString()) ?? 0.0;
    
    // TODO: Use user's unit preference when available
    return '${distanceKm.toStringAsFixed(1)} km';
  }

  String _formatDuration(dynamic duration) {
    if (duration == null) return '0 min';
    final durationSeconds = duration is int ? duration : int.tryParse(duration.toString()) ?? 0;
    
    final hours = durationSeconds ~/ 3600;
    final minutes = (durationSeconds % 3600) ~/ 60;
    
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }

  String _formatElevation(dynamic elevation) {
    if (elevation == null) return '0 m';
    final elevationM = elevation is double ? elevation : double.tryParse(elevation.toString()) ?? 0.0;
    return '${elevationM.toStringAsFixed(0)} m';
  }

  String _formatCalories(dynamic calories) {
    if (calories == null) return '0 cal';
    final caloriesValue = calories is double ? calories : double.tryParse(calories.toString()) ?? 0.0;
    return '${caloriesValue.toStringAsFixed(0)} cal';
  }
} 