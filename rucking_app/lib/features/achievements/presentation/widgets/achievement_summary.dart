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
import 'package:rucking_app/features/achievements/presentation/screens/achievements_hub_screen.dart';
import 'package:rucking_app/shared/widgets/skeleton/skeleton_widgets.dart';

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
        // Show skeleton loading while loading
        if (state is AchievementsLoading) {
          return const AchievementSummarySkeleton();
        }
        
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
      return const AchievementStatsSkeleton();
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
      return const RecentAchievementSkeleton();
    }

    if (state is! AchievementsLoaded) {
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
                'Complete challenges to earn achievements!',
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
    
    // Get locked achievements
    final lockedAchievements = state.getLockedAchievements();
    
    // If no locked achievements, show a message
    if (lockedAchievements.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              Icons.emoji_events,
              color: Colors.yellow[300],
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'You\'ve earned all achievements! Wow!',
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
    
    // Get achievements with progress
    final achievementsWithProgress = lockedAchievements
        .where((a) => state.userProgress.any((p) => p.achievementId == a.id && p.currentValue > 0))
        .toList();
    
    // Find a good next achievement to show
    Achievement? nextChallenge;
    String progressText = '';
    String achievementId = '';
    
    // First try to find an achievement with progress
    if (achievementsWithProgress.isNotEmpty) {
      // Sort by closest to completion
      final sortedByProgress = achievementsWithProgress.map((achievement) {
        final progress = state.getProgressForAchievement(achievement.id);
        final percent = progress != null 
            ? (progress.currentValue / progress.targetValue) 
            : 0.0;
        return {'achievement': achievement, 'percent': percent};
      }).toList();
      
      // Sort by highest completion percentage
      sortedByProgress.sort((a, b) => (b['percent'] as double).compareTo(a['percent'] as double));
      
      if (sortedByProgress.isNotEmpty) {
        nextChallenge = sortedByProgress.first['achievement'] as Achievement;
        achievementId = nextChallenge.id;
        final percent = sortedByProgress.first['percent'] as double;
        final progress = state.getProgressForAchievement(nextChallenge.id);
        
        if (progress != null) {
          progressText = ' (${(percent * 100).toInt()}% complete)';
        }
      }
    }
    
    // If no achievement with progress, pick a random beginner one
    if (nextChallenge == null) {
      final beginnerAchievements = lockedAchievements
          .where((a) => a.tier.toLowerCase() == 'beginner' || a.tier.toLowerCase() == 'easy')
          .toList();
      
      if (beginnerAchievements.isNotEmpty) {
        // Get a random beginner achievement
        nextChallenge = beginnerAchievements[DateTime.now().millisecondsSinceEpoch % beginnerAchievements.length];
        achievementId = nextChallenge.id;
      } else {
        // Just get any locked achievement
        nextChallenge = lockedAchievements[0];
        achievementId = nextChallenge.id;
      }
    }
    
    return GestureDetector(
      onTap: () {
        // Navigate to achievement detail page
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AchievementsHubScreen(
              initialAchievementId: achievementId,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              Icons.flag,
              color: Colors.yellow[300],
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Next challenge: ${nextChallenge.name}$progressText',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.visible,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tap to view details',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: Colors.white.withOpacity(0.6),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.white70,
              size: 18,
            ),
          ],
        ),
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
