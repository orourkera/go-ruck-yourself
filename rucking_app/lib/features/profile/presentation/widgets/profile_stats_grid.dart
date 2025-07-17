import 'package:flutter/material.dart';
import 'package:rucking_app/features/profile/domain/entities/user_profile_stats.dart';
import 'package:rucking_app/core/utils/measurement_utils.dart';

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
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      children: [
        _buildStatCard(
          context,
          icon: Icons.sports_mma,
          title: 'Total Rucks',
          value: stats.totalRucks.toString(),
        ),
        _buildStatCard(
          context,
          icon: Icons.straighten,
          title: 'Distance',
          value: MeasurementUtils.formatDistance(stats.totalDistanceKm, metric: preferMetric),
        ),
        _buildStatCard(
          context,
          icon: Icons.local_fire_department,
          title: 'Calories',
          value: MeasurementUtils.formatCalories(stats.totalCaloriesBurned.toInt()),
        ),
        _buildStatCard(
          context,
          icon: Icons.terrain,
          title: 'Elevation',
          value: MeasurementUtils.formatSingleElevation(stats.totalElevationGainM, metric: preferMetric),
        ),
      ],
    );
  }

  Widget _buildStatCard(BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: Theme.of(context).primaryColor,
              size: 24,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}