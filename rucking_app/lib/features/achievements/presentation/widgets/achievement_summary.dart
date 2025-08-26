import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/config/app_config.dart';
import 'package:rucking_app/core/services/storage_service.dart';
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
  String? _lastSuggestedId;
  @override
  void initState() {
    super.initState();
    _loadAchievementData();
  }

  void _loadAchievementData() async {
    try {
      final authBloc = context.read<AuthBloc>();
      final achievementBloc = context.read<AchievementBloc>();
      
      if (authBloc.state is Authenticated) {
        final userId = (authBloc.state as Authenticated).user.userId;
        
        // Get user's unit preference
        final storageService = GetIt.I<StorageService>();
        final storedUserData = await storageService.getObject(AppConfig.userProfileKey);
        bool preferMetric = false; // Default to imperial (standard)
        
        if (storedUserData != null && storedUserData.containsKey('preferMetric')) {
          preferMetric = storedUserData['preferMetric'] as bool;
        }
        
        final unitPreference = preferMetric ? 'metric' : 'standard';
        debugPrint('🏆 [AchievementSummary] Loading achievements with unit preference: $unitPreference');
        
        // Load achievements data with proper unit preference
        achievementBloc.add(LoadAchievements(unitPreference: unitPreference));
        achievementBloc.add(LoadUserAchievements(userId));
        achievementBloc.add(LoadAchievementStats(userId, unitPreference: unitPreference));
        achievementBloc.add(const LoadRecentAchievements());
      }
    } catch (e) {
      debugPrint('🏆 [AchievementSummary] Error loading unit preference: $e');
      // Fallback to standard if error occurs
      final authBloc = context.read<AuthBloc>();
      final achievementBloc = context.read<AchievementBloc>();
      
      if (authBloc.state is Authenticated) {
        final userId = (authBloc.state as Authenticated).user.userId;
        achievementBloc.add(const LoadAchievements(unitPreference: 'standard'));
        achievementBloc.add(LoadUserAchievements(userId));
        achievementBloc.add(LoadAchievementStats(userId, unitPreference: 'standard'));
        achievementBloc.add(const LoadRecentAchievements());
      }
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
        
        // If we have a session checked state, use the previous state data
        if (state is AchievementsSessionChecked) {
          state = state.previousState;
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
    
    // Determine user's elevation affinity (very low if essentially no elevation progress)
    final elevationProgress = state.userProgress
        .where((p) => (p.achievement?.category.toLowerCase() ?? '') == 'elevation')
        .toList();
    final hasAnyElevationProgress = elevationProgress.any((p) => p.currentValue > 0);
    final avgElevationPercent = elevationProgress.isNotEmpty
        ? (elevationProgress
                .map((p) => p.targetValue > 0 ? (p.currentValue / p.targetValue) : 0.0)
                .fold<double>(0.0, (a, b) => a + b) /
            elevationProgress.length)
        : 0.0;
    
    // First try to find an achievement with progress using smart selection
    if (achievementsWithProgress.isNotEmpty) {
      // Calculate smart scores for each achievement
      final scoredAchievements = achievementsWithProgress.map((achievement) {
        final progress = state.getProgressForAchievement(achievement.id);
        final percent = progress != null 
            ? (progress.currentValue / progress.targetValue) 
            : 0.0;
        
        // Calculate smart score based on multiple factors
        double score = 0.0;
        
        // Factor 1: Sweet spot progress (10-70% complete) - 40% weight
        if (percent >= 0.1 && percent <= 0.7) {
          score += 0.4;
        } else if (percent > 0.7) {
          // Penalize achievements stuck at high % (like elevation for flat routes)
          score += 0.1;
        } else {
          // Some progress is better than none
          score += 0.2;
        }
        
        // Factor 2: Category diversity - 30% weight
        // Avoid elevation-heavy achievements if user likely doesn't do elevation
        final category = achievement.category.toLowerCase();
        final stronglyAvoidElevation = !hasAnyElevationProgress || avgElevationPercent < 0.05;
        if (category == 'elevation') {
          // Heavily deprioritize elevation when user's history suggests low elevation
          score += stronglyAvoidElevation ? -0.3 : 0.05;
        } else {
          score += 0.3;
        }
        
        // Factor 3: Tier appropriateness - 20% weight
        final tier = achievement.tier.toLowerCase();
        if (tier == 'beginner' || tier == 'easy') {
          score += 0.2;
        } else if (tier == 'intermediate' || tier == 'medium') {
          score += 0.15;
        } else {
          score += 0.05;
        }
        
        // Factor 4: Actual progress amount - 10% weight
        score += percent * 0.1;
        
        return {
          'achievement': achievement, 
          'percent': percent, 
          'score': score
        };
      }).toList();
      
      // Sort by smart score (highest first)
      scoredAchievements.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
      
      if (scoredAchievements.isNotEmpty) {
        // Prefer top candidate, but avoid repeating the last suggestion within this session
        Achievement top = scoredAchievements.first['achievement'] as Achievement;
        if (_lastSuggestedId != null && top.id == _lastSuggestedId && scoredAchievements.length > 1) {
          // Pick the next best different candidate, prefer non-elevation
          final alt = scoredAchievements
              .skip(1)
              .map((m) => m['achievement'] as Achievement)
              .firstWhere(
                (a) => a.id != _lastSuggestedId && a.category.toLowerCase() != 'elevation',
                orElse: () => scoredAchievements[1]['achievement'] as Achievement,
              );
          top = alt;
        }
        nextChallenge = top;
        achievementId = top.id;
        final percent = scoredAchievements.first['percent'] as double;
        final progress = state.getProgressForAchievement(nextChallenge.id);
        
        if (progress != null) {
          progressText = ' (${(percent * 100).toInt()}% complete)';
        }
      }
    }
    
    // If no achievement with progress, pick a smart beginner one
    if (nextChallenge == null) {
      final beginnerAchievements = lockedAchievements
          .where((a) => a.tier.toLowerCase() == 'beginner' || a.tier.toLowerCase() == 'easy')
          .toList();
      
      if (beginnerAchievements.isNotEmpty) {
        // First try to get non-elevation achievements for better variety
        final nonElevationBeginners = beginnerAchievements
            .where((a) => a.category.toLowerCase() != 'elevation')
            .toList();
        
        if (nonElevationBeginners.isNotEmpty) {
          // Rotate through different achievements based on day of year for variety
          final dayOfYear = DateTime.now().difference(DateTime(DateTime.now().year)).inDays;
          nextChallenge = nonElevationBeginners[dayOfYear % nonElevationBeginners.length];
        } else {
          // Fallback to any beginner achievement
          nextChallenge = beginnerAchievements[DateTime.now().millisecondsSinceEpoch % beginnerAchievements.length];
        }
        achievementId = nextChallenge.id;
      } else {
        // Just get any locked achievement (prefer non-elevation)
        final nonElevationAchievements = lockedAchievements
            .where((a) => a.category.toLowerCase() != 'elevation')
            .toList();
        
        if (nonElevationAchievements.isNotEmpty) {
          nextChallenge = nonElevationAchievements[0];
        } else {
          nextChallenge = lockedAchievements[0];
        }
        achievementId = nextChallenge.id;
      }
    }
    
    // Remember what we suggested this build to avoid repeating next time
    _lastSuggestedId = achievementId;

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
