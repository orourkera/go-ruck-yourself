import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/achievements/data/models/achievement_model.dart';
import 'package:rucking_app/features/achievements/presentation/bloc/achievement_bloc.dart';
import 'package:rucking_app/features/achievements/presentation/bloc/achievement_state.dart';
import 'package:rucking_app/features/achievements/presentation/widgets/achievement_badge.dart';
import 'package:rucking_app/features/achievements/presentation/screens/achievements_hub_screen.dart';

class AchievementSummary extends StatelessWidget {
  final bool showTitle;
  final int maxRecentItems;
  final VoidCallback? onViewAll;

  const AchievementSummary({
    super.key,
    this.showTitle = true,
    this.maxRecentItems = 3,
    this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AchievementBloc, AchievementState>(
      builder: (context, state) {
        if (state is AchievementsLoading) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),
          );
        }

        if (state is AchievementsError) {
          return const SizedBox.shrink();
        }

        if (state is! AchievementsLoaded) {
          return const SizedBox.shrink();
        }

        final stats = state.stats;
        final recentAchievements = state.recentAchievements?.take(maxRecentItems).toList() ?? [];

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                if (showTitle)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Achievements',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton(
                        onPressed: onViewAll ?? () => _navigateToAchievementsHub(context),
                        child: const Text('View All'),
                      ),
                    ],
                  ),

                if (showTitle) const SizedBox(height: 16.0),

                // Stats row
                if (stats != null)
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatItem(
                          context,
                          'Earned',
                          stats.totalEarned.toString(),
                          Icons.emoji_events,
                          Colors.amber,
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 40,
                        color: Colors.grey.shade300,
                        margin: const EdgeInsets.symmetric(horizontal: 16.0),
                      ),
                      Expanded(
                        child: _buildStatItem(
                          context,
                          'Progress',
                          '${stats.completionPercentage.toStringAsFixed(0)}%',
                          Icons.trending_up,
                          Colors.green,
                        ),
                      ),
                    ],
                  ),

                // Recent achievements
                if (recentAchievements.isNotEmpty) ...[
                  const SizedBox(height: 16.0),
                  Text(
                    'Recent Unlocks',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 12.0),
                  Row(
                    children: recentAchievements.where((userAchievement) => userAchievement.achievement != null).map((userAchievement) {
                      final achievement = userAchievement.achievement!;
                      return Padding(
                        padding: const EdgeInsets.only(right: 12.0),
                        child: Column(
                          children: [
                            AchievementBadge(
                              achievement: achievement,
                              isEarned: true,
                              size: 40,
                            ),
                            const SizedBox(height: 4.0),
                            SizedBox(
                              width: 50,
                              child: Text(
                                achievement.name,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontSize: 10,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ] else if (stats != null && stats.totalEarned == 0) ...[
                  const SizedBox(height: 16.0),
                  Container(
                    padding: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8.0),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.grey.shade600,
                          size: 20,
                        ),
                        const SizedBox(width: 8.0),
                        Expanded(
                          child: Text(
                            'Complete your first ruck to start earning achievements!',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatItem(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4.0),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  void _navigateToAchievementsHub(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const AchievementsHubScreen(),
      ),
    );
  }
}
