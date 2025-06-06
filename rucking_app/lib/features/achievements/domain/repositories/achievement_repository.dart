import 'package:rucking_app/features/achievements/data/models/achievement_model.dart';

/// Interface for achievements repository
abstract class AchievementRepository {
  /// Get all available achievements filtered by unit preference
  Future<List<Achievement>> getAllAchievements({String? unitPreference});
  
  /// Get achievement categories
  Future<List<String>> getAchievementCategories();
  
  /// Get user's earned achievements
  Future<List<UserAchievement>> getUserAchievements(String userId);
  
  /// Get user's progress toward unearned achievements
  Future<List<AchievementProgress>> getUserAchievementProgress(String userId);
  
  /// Check and award achievements for a completed session
  Future<List<Achievement>> checkSessionAchievements(int sessionId);
  
  /// Get achievement statistics for a user filtered by unit preference
  Future<AchievementStats> getAchievementStats(String userId, {String? unitPreference});
  
  /// Get recently earned achievements across the platform
  Future<List<UserAchievement>> getRecentAchievements();
  
  /// Clears all cached achievement data
  Future<void> clearCache();
  
  /// Checks if the cache is expired
  Future<bool> isCacheExpired();
}
