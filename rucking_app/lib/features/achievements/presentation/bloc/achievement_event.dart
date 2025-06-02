import 'package:equatable/equatable.dart';

abstract class AchievementEvent extends Equatable {
  const AchievementEvent();

  @override
  List<Object?> get props => [];
}

/// Event to load all achievements
class LoadAchievements extends AchievementEvent {
  final String? unitPreference;
  
  const LoadAchievements({this.unitPreference});
  
  @override
  List<Object?> get props => [unitPreference];
}

/// Event to load achievement categories
class LoadAchievementCategories extends AchievementEvent {
  const LoadAchievementCategories();
}

/// Event to load user's earned achievements
class LoadUserAchievements extends AchievementEvent {
  final String userId;

  const LoadUserAchievements(this.userId);

  @override
  List<Object> get props => [userId];
}

/// Event to load user's achievement progress
class LoadUserAchievementProgress extends AchievementEvent {
  final String userId;

  const LoadUserAchievementProgress(this.userId);

  @override
  List<Object> get props => [userId];
}

/// Event to check achievements for a completed session
class CheckSessionAchievements extends AchievementEvent {
  final int sessionId;

  const CheckSessionAchievements(this.sessionId);

  @override
  List<Object> get props => [sessionId];
}

/// Event to load achievement statistics
class LoadAchievementStats extends AchievementEvent {
  final String userId;
  final String? unitPreference;

  const LoadAchievementStats(this.userId, {this.unitPreference});

  @override
  List<Object?> get props => [userId, unitPreference];
}

/// Event to load recent achievements across platform
class LoadRecentAchievements extends AchievementEvent {
  const LoadRecentAchievements();
}

/// Event to refresh all achievement data for a user
class RefreshAchievementData extends AchievementEvent {
  final String userId;
  final String? unitPreference;

  const RefreshAchievementData(this.userId, {this.unitPreference});

  @override
  List<Object?> get props => [userId, unitPreference];
}
