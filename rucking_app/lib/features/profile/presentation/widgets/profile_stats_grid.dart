import 'package:flutter/material.dart';
import 'package:rucking_app/features/profile/domain/entities/user_profile_stats.dart';

class ProfileStatsGrid extends StatelessWidget {
  final UserProfileStats stats;
  final bool preferMetric;
  final VoidCallback? onFollowersPressed;
  final VoidCallback? onFollowingPressed;

  const ProfileStatsGrid({
    Key? key,
    required this.stats,
    this.preferMetric = true,
    this.onFollowersPressed,
    this.onFollowingPressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Convert distance based on user preference
    final distanceValue = preferMetric 
        ? stats.totalDistanceKm 
        : stats.totalDistanceKm * 0.621371; // Convert km to miles
    final distanceUnit = preferMetric ? 'km' : 'mi';
    
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      children: [
        _buildStatCard(context, 'Total Rucks', stats.totalRucks.toString()),
        _buildStatCard(context, 'Distance ($distanceUnit)', distanceValue.toStringAsFixed(1)),
        _buildStatCard(context, 'Total Calories', stats.totalCaloriesBurned.toStringAsFixed(0)),
        _buildStatCard(context, 'Total Elevation', '${stats.totalElevationGainM.toStringAsFixed(0)} m'),
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