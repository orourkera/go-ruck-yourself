import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for caching achievement data to improve loading performance
class AchievementCacheService {
  static const String _achievementsKey = 'achievements_cache';
  static const String _userAchievementsKey = 'user_achievements_cache';
  static const String _achievementStatsKey = 'achievement_stats_cache';
  static const String _recentAchievementsKey = 'recent_achievements_cache';
  static const String _timestampKey = 'achievement_cache_timestamp';
  static const Duration _cacheDuration = Duration(minutes: 10); // Cache valid for 10 minutes

  /// Saves all achievements to local storage
  Future<void> cacheAllAchievements(List<dynamic> achievements) async {
    final prefs = await SharedPreferences.getInstance();
    final String jsonData = jsonEncode(achievements);
    await prefs.setString(_achievementsKey, jsonData);
    await prefs.setInt(_timestampKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// Saves user achievements to local storage
  Future<void> cacheUserAchievements(String userId, List<dynamic> userAchievements) async {
    final prefs = await SharedPreferences.getInstance();
    final String jsonData = jsonEncode(userAchievements);
    await prefs.setString('${_userAchievementsKey}_$userId', jsonData);
  }

  /// Saves achievement stats to local storage
  Future<void> cacheAchievementStats(String userId, Map<String, dynamic> stats) async {
    final prefs = await SharedPreferences.getInstance();
    final String jsonData = jsonEncode(stats);
    await prefs.setString('${_achievementStatsKey}_$userId', jsonData);
  }

  /// Saves recent achievements to local storage
  Future<void> cacheRecentAchievements(List<dynamic> recentAchievements) async {
    final prefs = await SharedPreferences.getInstance();
    final String jsonData = jsonEncode(recentAchievements);
    await prefs.setString(_recentAchievementsKey, jsonData);
  }

  /// Retrieves cached achievements if they exist and are not expired
  Future<List<dynamic>?> getCachedAchievements() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Check if cache exists
    if (!prefs.containsKey(_achievementsKey)) return null;
    
    // Check if cache is expired
    final timestamp = prefs.getInt(_timestampKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - timestamp > _cacheDuration.inMilliseconds) return null;
    
    // Return cached data
    final String? jsonData = prefs.getString(_achievementsKey);
    if (jsonData == null) return null;
    
    try {
      return jsonDecode(jsonData) as List<dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// Retrieves cached user achievements if they exist and are not expired
  Future<List<dynamic>?> getCachedUserAchievements(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Check if cache exists
    if (!prefs.containsKey('${_userAchievementsKey}_$userId')) return null;
    
    // Check if cache is expired (use same timestamp as achievements)
    final timestamp = prefs.getInt(_timestampKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - timestamp > _cacheDuration.inMilliseconds) return null;
    
    final String? jsonData = prefs.getString('${_userAchievementsKey}_$userId');
    if (jsonData == null) return null;
    
    try {
      return jsonDecode(jsonData) as List<dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// Retrieves cached achievement stats if they exist and are not expired
  Future<Map<String, dynamic>?> getCachedAchievementStats(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Check if cache exists
    if (!prefs.containsKey('${_achievementStatsKey}_$userId')) return null;
    
    // Check if cache is expired
    final timestamp = prefs.getInt(_timestampKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - timestamp > _cacheDuration.inMilliseconds) return null;
    
    final String? jsonData = prefs.getString('${_achievementStatsKey}_$userId');
    if (jsonData == null) return null;
    
    try {
      return jsonDecode(jsonData) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// Retrieves cached recent achievements if they exist and are not expired
  Future<List<dynamic>?> getCachedRecentAchievements() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Check if cache exists
    if (!prefs.containsKey(_recentAchievementsKey)) return null;
    
    // Check if cache is expired
    final timestamp = prefs.getInt(_timestampKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - timestamp > _cacheDuration.inMilliseconds) return null;
    
    final String? jsonData = prefs.getString(_recentAchievementsKey);
    if (jsonData == null) return null;
    
    try {
      return jsonDecode(jsonData) as List<dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// Clears all cached achievement data
  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    
    // Remove all achievement-related cache keys
    for (final key in keys) {
      if (key.startsWith(_achievementsKey) ||
          key.startsWith(_userAchievementsKey) ||
          key.startsWith(_achievementStatsKey) ||
          key.startsWith(_recentAchievementsKey) ||
          key == _timestampKey) {
        await prefs.remove(key);
      }
    }
  }

  /// Checks if the cache is expired
  Future<bool> isCacheExpired() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt(_timestampKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    return now - timestamp > _cacheDuration.inMilliseconds;
  }
}
