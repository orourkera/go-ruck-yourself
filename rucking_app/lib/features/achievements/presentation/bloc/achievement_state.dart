import 'package:equatable/equatable.dart';
import 'package:rucking_app/features/achievements/data/models/achievement_model.dart';

abstract class AchievementState extends Equatable {
  const AchievementState();
  
  @override
  List<Object> get props => [];
}

class AchievementsInitial extends AchievementState {}

class AchievementsLoading extends AchievementState {}

class AchievementsLoaded extends AchievementState {
  final List<Achievement> allAchievements;
  final List<String> categories;
  final List<UserAchievement> userAchievements;
  final List<AchievementProgress> userProgress;
  final AchievementStats? stats;
  final List<UserAchievement> recentAchievements;
  final List<Achievement> newlyEarned;
  
  const AchievementsLoaded({
    required this.allAchievements,
    required this.categories,
    required this.userAchievements,
    required this.userProgress,
    this.stats,
    required this.recentAchievements,
    this.newlyEarned = const [],
  });
  
  @override
  List<Object> get props => [
    allAchievements,
    categories,
    userAchievements,
    userProgress,
    stats ?? const AchievementStats(
      totalEarned: 0,
      totalAvailable: 0,
      completionPercentage: 0.0,
      powerPoints: 0,
      byCategory: {},
      byTier: {},
    ),
    recentAchievements,
    newlyEarned,
  ];
  
  AchievementsLoaded copyWith({
    List<Achievement>? allAchievements,
    List<String>? categories,
    List<UserAchievement>? userAchievements,
    List<AchievementProgress>? userProgress,
    AchievementStats? stats,
    List<UserAchievement>? recentAchievements,
    List<Achievement>? newlyEarned,
  }) {
    return AchievementsLoaded(
      allAchievements: allAchievements ?? this.allAchievements,
      categories: categories ?? this.categories,
      userAchievements: userAchievements ?? this.userAchievements,
      userProgress: userProgress ?? this.userProgress,
      stats: stats ?? this.stats,
      recentAchievements: recentAchievements ?? this.recentAchievements,
      newlyEarned: newlyEarned ?? this.newlyEarned,
    );
  }

  /// Helper methods for UI
  List<Achievement> getAchievementsByCategory(String category) {
    return allAchievements.where((a) => a.category == category).toList();
  }

  List<Achievement> getUnlockedAchievements() {
    final earnedIds = userAchievements.map((ua) => ua.achievementId).toSet();
    return allAchievements.where((a) => earnedIds.contains(a.id)).toList();
  }

  List<Achievement> getLockedAchievements() {
    final earnedIds = userAchievements.map((ua) => ua.achievementId).toSet();
    return allAchievements.where((a) => !earnedIds.contains(a.id)).toList();
  }

  AchievementProgress? getProgressForAchievement(String achievementId) {
    return userProgress.where((p) => p.achievementId == achievementId).firstOrNull;
  }

  double getOverallProgress() {
    if (allAchievements.isEmpty) return 0.0;
    return (userAchievements.length / allAchievements.length * 100).clamp(0.0, 100.0);
  }
}

class AchievementsError extends AchievementState {
  final String message;
  final String? errorCode;
  
  const AchievementsError({
    required this.message,
    this.errorCode,
  });
  
  @override
  List<Object> get props => [message, errorCode ?? ''];
}

class AchievementsSessionChecked extends AchievementState {
  final List<Achievement> newAchievements;
  final AchievementsLoaded previousState;
  
  const AchievementsSessionChecked({
    required this.newAchievements,
    required this.previousState,
  });
  
  @override
  List<Object> get props => [newAchievements, previousState];
}

// Extension to add firstOrNull helper if not available
extension IterableExtension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (iterator.moveNext()) {
      return iterator.current;
    }
    return null;
  }
}
