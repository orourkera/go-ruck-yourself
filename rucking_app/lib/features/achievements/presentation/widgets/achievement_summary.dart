import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/animated_counter.dart';
import 'package:rucking_app/features/achievements/presentation/bloc/achievement_bloc.dart';
import 'package:rucking_app/features/achievements/presentation/bloc/achievement_event.dart';
import 'package:rucking_app/features/achievements/presentation/bloc/achievement_state.dart';
import 'package:rucking_app/features/achievements/data/models/achievement_model.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';

/// Achievement Summary widget for displaying quick achievement stats
class AchievementSummary extends StatefulWidget {
  final bool showTitle;
  final int maxRecentAchievements;

  const AchievementSummary({
    Key? key,
    this.showTitle = true,
    this.maxRecentAchievements = 3,
  }) : super(key: key);

  @override
  State<AchievementSummary> createState() => _AchievementSummaryState();
}

class _AchievementSummaryState extends State<AchievementSummary> {
  @override
  void initState() {
    super.initState();
    _loadAchievementData();
  }

  void _loadAchievementData() {
    final authBloc = BlocProvider.of<AuthBloc>(context);
    final achievementBloc = BlocProvider.of<AchievementBloc>(context);
    
    if (authBloc.state is Authenticated) {
      final userId = (authBloc.state as Authenticated).user.userId;
      
      // Load achievements data
      achievementBloc.add(const LoadAchievements());
      achievementBloc.add(LoadUserAchievements(userId)); // Load user's earned achievements
      achievementBloc.add(LoadAchievementStats(userId));
      achievementBloc.add(const LoadRecentAchievements());
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AchievementBloc, AchievementState>(
      builder: (context, state) {
        return Card(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary.withOpacity(0.8), AppColors.secondary.withOpacity(0.8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.showTitle) ...[
                  Row(
                    children: [
                      Icon(
                        Icons.emoji_events,
                        color: Colors.white,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Achievements',
                        style: AppTextStyles.titleLarge.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          // Navigate to achievements hub
                          Navigator.pushNamed(context, '/achievements');
                        },
                        child: Text(
                          'View All',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: Colors.white,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                
                // Quick stats
                _buildStatsRow(state),
                
                const SizedBox(height: 16),
                
                // Recent achievements
                _buildRecentAchievements(state),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatsRow(AchievementState state) {
    if (state is AchievementsLoading || (state is AchievementsLoaded && state.stats == null)) {
      return const Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
        ],
      );
    }

    final stats = (state is AchievementsLoaded) ? state.stats : null;
    final totalEarned = stats?.totalEarned.toString() ?? '0';
    final totalAvailable = stats?.totalAvailable.toString() ?? '0';
    final powerPoints = stats?.powerPoints ?? 0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildStatColumn(totalEarned, 'Earned', Icons.emoji_events),
        _buildStatColumn(totalAvailable, 'Available', Icons.flag),
        _buildPowerPointsColumn(powerPoints),
      ],
    );
  }

  Widget _buildRecentAchievements(AchievementState state) {
    if (state is AchievementsLoading) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Loading recent achievements...',
              style: AppTextStyles.bodyMedium.copyWith(
                color: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    final recentAchievements = (state is AchievementsLoaded) ? state.userAchievements : <UserAchievement>[];
    
    // If no recent achievements, show recommendation
    if (recentAchievements.isEmpty) {
      // Get stats to check if user has any rucks
      final stats = (state is AchievementsLoaded) ? state.stats : null;
      final hasNoRucks = stats?.totalEarned == 0;
      
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              Icons.lightbulb_outline,
              color: Colors.yellow[300],
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hasNoRucks 
                  ? 'Next up: First Steps - Complete your first ruck!' 
                  : 'Keep going! More achievements await!',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.visible,
              ),
            ),
          ],
        ),
      );
    }
    
    // Show user's earned achievements (most recent first)
    final sortedAchievements = List<UserAchievement>.from(recentAchievements)
      ..sort((a, b) => (b.earnedAt ?? DateTime.now()).compareTo(a.earnedAt ?? DateTime.now()));
    
    final recentNames = sortedAchievements
        .take(3)
        .map((achievement) => achievement.achievement?.name ?? 'Unknown Achievement')
        .join(', ');
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.star,
            color: Colors.yellow[300],
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Recent: $recentNames',
              style: AppTextStyles.bodyMedium.copyWith(
                color: Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String value, String label, IconData icon) {
    return Column(
      children: [
        Icon(
          icon,
          color: Colors.white,
          size: 20,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTextStyles.titleMedium.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  Widget _buildPowerPointsColumn(int powerPoints) {
    return Column(
      children: [
        Icon(
          Icons.bolt,
          color: Colors.white,
          size: 20,
        ),
        const SizedBox(height: 4),
        AnimatedCounter(
          targetValue: powerPoints,
          textStyle: AppTextStyles.titleMedium.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontFamily: 'Bangers',
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Power Points',
          style: AppTextStyles.bodySmall.copyWith(
            color: Colors.white70,
          ),
        ),
      ],
    );
  }
}
