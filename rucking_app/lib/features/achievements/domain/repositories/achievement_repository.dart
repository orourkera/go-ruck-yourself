import 'package:rucking_app/features/achievements/data/models/achievement_model.dart';

/// Interface for achievements repository
abstract class AchievementRepository {
  /// Get all available achievements
  Future<List<Achievement>> getAllAchievements();
  
  /// Get achievement categories
  Future<List<String>> getAchievementCategories();
  
  /// Get user's earned achievements
  Future<List<UserAchievement>> getUserAchievements(String userId);
  
  /// Get user's progress toward unearned achievements
  Future<List<AchievementProgress>> getUserAchievementProgress(String userId);
  
  /// Check and award achievements for a completed session
  Future<List<Achievement>> checkSessionAchievements(int sessionId);
  
  /// Get achievement statistics for a user
  Future<AchievementStats> getAchievementStats(String userId);
  
  /// Get recently earned achievements across the platform
  Future<List<UserAchievement>> getRecentAchievements();
}
