import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for caching ruck sessions and stats to improve home page loading performance
class SessionCacheService {
  static const String _recentSessionsKey = 'recent_sessions_cache';
  static const String _monthlyStatsKey = 'monthly_stats_cache';
  static const String _timestampKey = 'cache_timestamp';
  static const Duration _cacheDuration =
      Duration(minutes: 15); // Cache valid for 15 minutes

  /// Saves recent sessions to local storage
  Future<void> cacheRecentSessions(List<dynamic> sessions) async {
    final prefs = await SharedPreferences.getInstance();
    final String jsonData = jsonEncode(sessions);
    await prefs.setString(_recentSessionsKey, jsonData);
    await prefs.setInt(_timestampKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// Saves monthly stats to local storage
  Future<void> cacheMonthlyStats(Map<String, dynamic> stats) async {
    final prefs = await SharedPreferences.getInstance();
    final String jsonData = jsonEncode(stats);
    await prefs.setString(_monthlyStatsKey, jsonData);
  }

  /// Retrieves cached sessions if they exist and are not expired
  Future<List<dynamic>?> getCachedSessions() async {
    final prefs = await SharedPreferences.getInstance();

    // Check if cache exists
    if (!prefs.containsKey(_recentSessionsKey)) return null;

    // Check if cache is expired
    final timestamp = prefs.getInt(_timestampKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - timestamp > _cacheDuration.inMilliseconds) return null;

    // Return cached data
    final String? jsonData = prefs.getString(_recentSessionsKey);
    if (jsonData == null) return null;

    try {
      return jsonDecode(jsonData) as List<dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// Retrieves cached monthly stats if they exist
  Future<Map<String, dynamic>?> getCachedStats() async {
    final prefs = await SharedPreferences.getInstance();

    // Check if cache exists
    if (!prefs.containsKey(_monthlyStatsKey)) return null;

    final String? jsonData = prefs.getString(_monthlyStatsKey);
    if (jsonData == null) return null;

    try {
      return jsonDecode(jsonData) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// Clears all cached data
  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_recentSessionsKey);
    await prefs.remove(_monthlyStatsKey);
    await prefs.remove(_timestampKey);
  }
}
