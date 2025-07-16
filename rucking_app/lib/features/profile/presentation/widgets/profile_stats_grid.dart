import 'package:flutter/material.dart';
import 'package:rucking_app/features/profile/domain/entities/user_profile_stats.dart';

class ProfileStatsGrid extends StatelessWidget {
  final UserProfileStats stats;
  final VoidCallback? onFollowersPressed;
  final VoidCallback? onFollowingPressed;

  const ProfileStatsGrid({
    Key? key,
    required this.stats,
    this.onFollowersPressed,
    this.onFollowingPressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      children: [
        _buildStatCard(context, 'Total Rucks', stats.totalRucks.toString()),
        _buildStatCard(context, 'Distance (km)', stats.totalDistanceKm.toStringAsFixed(1)),
        _buildStatCard(context, 'Followers', stats.followersCount.toString(), onTap: onFollowersPressed),
        _buildStatCard(context, 'Following', stats.followingCount.toString(), onTap: onFollowingPressed),
        // Add more stats as needed
      ],
    );
  }

  Widget _buildStatCard(BuildContext context, String label, String value, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(value, style: Theme.of(context).textTheme.headlineMedium),
            Text(label),
          ],
        ),
      ),
    );
  }
} 