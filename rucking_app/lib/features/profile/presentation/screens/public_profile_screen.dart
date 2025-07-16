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
                                onTap: () => Navigator.pushNamed(context, '/followers', arguments: state.profile.id),
                              ),
                              _buildCountColumn(
                                context,
                                label: 'Following',
                                count: state.stats?.followingCount ?? 0,
                                onTap: () => Navigator.pushNamed(context, '/following', arguments: state.profile.id),
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
      return Center(child: Text('No recent rucks'));
    }
    
    return ListView.builder(
      itemCount: recentRucks.length,
      itemBuilder: (context, index) {
        final ruck = recentRucks[index];
        return ListTile(
          title: Text('Ruck ${index + 1}'),
          subtitle: Text('${ruck.distanceKm?.toStringAsFixed(1) ?? '0.0'} km'),
          trailing: Text('${ruck.durationSeconds != null ? (ruck.durationSeconds! / 60).toStringAsFixed(0) : '0'} min'),
        );
      },
    );
  }
} 