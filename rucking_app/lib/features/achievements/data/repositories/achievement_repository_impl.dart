import 'package:flutter/foundation.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/network/api_endpoints.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/services/achievement_cache_service.dart';
import 'package:rucking_app/features/achievements/data/models/achievement_model.dart';
import 'package:rucking_app/features/achievements/domain/repositories/achievement_repository.dart';

class AchievementRepositoryImpl implements AchievementRepository {
  final ApiClient _apiClient;
  final AchievementCacheService _cacheService;

  AchievementRepositoryImpl({
    required ApiClient apiClient,
    required AchievementCacheService cacheService,
  })  : _apiClient = apiClient,
        _cacheService = cacheService;

  @override
  Future<List<Achievement>> getAllAchievements({String? unitPreference}) async {
    try {
      debugPrint(
          '🏆 [AchievementRepository] getAllAchievements called with unitPreference: $unitPreference');

      // Try to get cached data first
      final cachedData = await _cacheService.getCachedAchievements();
      if (cachedData != null) {
        debugPrint(
            '🏆 [AchievementRepository] Found ${cachedData.length} achievements in cache');
        return cachedData.map((json) => Achievement.fromJson(json)).toList();
      }

      debugPrint('🏆 [AchievementRepository] Cache miss, fetching from API');

      // Build endpoint with unit preference query parameter
      String endpoint = ApiEndpoints.achievements;
      if (unitPreference != null) {
        endpoint += '?unit_preference=$unitPreference';
      }

      debugPrint('🏆 [AchievementRepository] API endpoint: $endpoint');

      final response = await _apiClient.get(endpoint);
      debugPrint(
          '🏆 [AchievementRepository] API response received: ${response.toString().substring(0, 200)}...');

      // The API returns: {'status': 'success', 'achievements': [...]}
      if (response['status'] == 'success' && response['achievements'] != null) {
        final achievementsData = response['achievements'] as List;
        debugPrint(
            '🏆 [AchievementRepository] Found ${achievementsData.length} achievements in response');

        // Cache the data
        await _cacheService.cacheAllAchievements(achievementsData);
        debugPrint(
            '🏆 [AchievementRepository] Cached ${achievementsData.length} achievements');

        return achievementsData
            .map((json) => Achievement.fromJson(json))
            .toList();
      }

      debugPrint(
          '🏆 [AchievementRepository] No achievements found in response');
      return [];
    } catch (e) {
      debugPrint('🏆 [AchievementRepository] Error fetching achievements: $e');
      AppLogger.error('Error fetching achievements', exception: e);
      throw Exception('Failed to fetch achievements: $e');
    }
  }

  @override
  Future<List<String>> getAchievementCategories() async {
    try {
      final response = await _apiClient.get(ApiEndpoints.achievementCategories);

      if (response['status'] == 'success' && response['categories'] != null) {
        return List<String>.from(response['categories']);
      }

      return [];
    } catch (e) {
      AppLogger.error('Error fetching achievement categories', exception: e);
      throw Exception('Failed to fetch achievement categories: $e');
    }
  }

  @override
  Future<List<UserAchievement>> getUserAchievements(String userId) async {
    try {
      debugPrint(
          '🏆 [AchievementRepository] getUserAchievements called for userId: $userId');

      // Validate userId to prevent malformed API URLs that cause 500 errors
      if (userId.isEmpty) {
        debugPrint(
            '🏆 [AchievementRepository] Error: userId is empty, cannot fetch achievements');
        throw Exception('User ID is required to fetch achievements');
      }

      // Try to get cached data first
      final cachedData = await _cacheService.getCachedUserAchievements(userId);
      if (cachedData != null) {
        debugPrint(
            '🏆 [AchievementRepository] Found ${cachedData.length} user achievements in cache');
        return cachedData
            .map((json) => UserAchievement.fromJson(json))
            .toList();
      }

      debugPrint(
          '🏆 [AchievementRepository] Cache miss, fetching user achievements from API');

      final endpoint = ApiEndpoints.getUserAchievementsEndpoint(userId);
      debugPrint('🏆 [AchievementRepository] API endpoint: $endpoint');

      final response = await _apiClient.get(endpoint);
      debugPrint(
          '🏆 [AchievementRepository] User achievements response: $response');

      if (response['status'] == 'success' &&
          response['user_achievements'] != null) {
        final userAchievementsData = response['user_achievements'] as List;
        debugPrint(
            '🏆 [AchievementRepository] Found ${userAchievementsData.length} user achievements');

        // Cache the data
        await _cacheService.cacheUserAchievements(userId, userAchievementsData);
        debugPrint(
            '🏆 [AchievementRepository] Cached ${userAchievementsData.length} user achievements');

        return userAchievementsData
            .map((json) => UserAchievement.fromJson(json))
            .toList();
      }

      debugPrint(
          '🏆 [AchievementRepository] No user achievements found or invalid response');
      return [];
    } catch (e) {
      AppLogger.error('Error fetching user achievements', exception: e);
      throw Exception('Failed to fetch user achievements: $e');
    }
  }

  @override
  Future<List<AchievementProgress>> getUserAchievementProgress(
      String userId) async {
    try {
      final endpoint = ApiEndpoints.getUserAchievementsProgressEndpoint(userId);
      final response = await _apiClient.get(endpoint);

      if (response['status'] == 'success' && response['progress'] != null) {
        final progressData = response['progress'] as List;
        return progressData
            .map((json) => AchievementProgress.fromJson(json))
            .toList();
      }

      return [];
    } catch (e) {
      AppLogger.error('Error fetching user achievement progress', exception: e);
      throw Exception('Failed to fetch user achievement progress: $e');
    }
  }

  @override
  Future<List<Achievement>> checkSessionAchievements(int sessionId) async {
    try {
      final endpoint = ApiEndpoints.getCheckSessionAchievementsEndpoint(
          sessionId.toString());
      print('[ACHIEVEMENT_DEBUG] AchievementRepo: Calling endpoint: $endpoint');
      final response = await _apiClient.post(endpoint, {});
      print('[ACHIEVEMENT_DEBUG] AchievementRepo: Full response: $response');
      print(
          '[ACHIEVEMENT_DEBUG] AchievementRepo: Response type: ${response.runtimeType}');

      if (response != null) {
        print(
            '[ACHIEVEMENT_DEBUG] AchievementRepo: Response status: ${response['status']}');
        print(
            '[ACHIEVEMENT_DEBUG] AchievementRepo: Response new_achievements: ${response['new_achievements']}');
        print(
            '[ACHIEVEMENT_DEBUG] AchievementRepo: Response new_achievements type: ${response['new_achievements']?.runtimeType}');
      }

      if (response['status'] == 'success' &&
          response['new_achievements'] != null) {
        final newAchievementsData = response['new_achievements'] as List;
        print(
            '[ACHIEVEMENT_DEBUG] AchievementRepo: Found ${newAchievementsData.length} new achievements in response');
        print(
            '[ACHIEVEMENT_DEBUG] AchievementRepo: Achievement data: $newAchievementsData');

        final achievements = newAchievementsData
            .map((json) => Achievement.fromJson(json))
            .toList();
        print(
            '[ACHIEVEMENT_DEBUG] AchievementRepo: Parsed ${achievements.length} achievements');
        for (int i = 0; i < achievements.length; i++) {
          print(
              '[ACHIEVEMENT_DEBUG] AchievementRepo: Achievement $i: ${achievements[i].name} (ID: ${achievements[i].id})');
        }
        return achievements;
      }

      print(
          '[ACHIEVEMENT_DEBUG] AchievementRepo: No new achievements or status not success');
      return [];
    } catch (e) {
      print('[ACHIEVEMENT_DEBUG] AchievementRepo: Error: $e');
      print(
          '[ACHIEVEMENT_DEBUG] AchievementRepo: Error type: ${e.runtimeType}');
      AppLogger.error('Error checking session achievements', exception: e);
      throw Exception('Failed to check session achievements: $e');
    }
  }

  @override
  Future<AchievementStats> getAchievementStats(String userId,
      {String? unitPreference}) async {
    try {
      // Try to get cached data first
      final cachedData = await _cacheService.getCachedAchievementStats(userId);
      if (cachedData != null) {
        print(
            '[DEBUG] AchievementRepository: Found achievement stats in cache');
        return AchievementStats.fromJson(cachedData);
      }

      print(
          '[DEBUG] AchievementRepository: Cache miss, fetching stats from API');

      // Build endpoint with unit preference query parameter
      String endpoint = ApiEndpoints.getAchievementStatsEndpoint(userId);
      if (unitPreference != null) {
        endpoint += '?unit_preference=$unitPreference';
      }

      print('[DEBUG] AchievementRepository: Fetching stats from: $endpoint');
      final response = await _apiClient.get(endpoint);

      print('[DEBUG] AchievementRepository: Stats API response: $response');

      if (response['status'] == 'success' && response['stats'] != null) {
        print(
            '[DEBUG] AchievementRepository: Parsing stats: ${response['stats']}');
        final stats = AchievementStats.fromJson(response['stats']);

        // Cache the data
        await _cacheService.cacheAchievementStats(userId, response['stats']);
        print('[DEBUG] AchievementRepository: Cached achievement stats');

        return stats;
      }

      print(
          '[DEBUG] AchievementRepository: No stats found, returning empty stats');
      // Return empty stats if no data
      return const AchievementStats(
        totalEarned: 0,
        totalAvailable: 0,
        completionPercentage: 0.0,
        powerPoints: 0,
        byCategory: {},
        byTier: {},
      );
    } catch (e) {
      print('[DEBUG] AchievementRepository: Error fetching stats: $e');
      AppLogger.error('Error fetching achievement stats', exception: e);
      throw Exception('Failed to fetch achievement stats: $e');
    }
  }

  @override
  Future<List<UserAchievement>> getRecentAchievements() async {
    try {
      // Try to get cached data first
      final cachedData = await _cacheService.getCachedRecentAchievements();
      if (cachedData != null) {
        debugPrint(
            '🏆 [AchievementRepository] Found ${cachedData.length} recent achievements in cache');
        return cachedData
            .map((json) => UserAchievement.fromJson(json))
            .toList();
      }

      debugPrint(
          '🏆 [AchievementRepository] Cache miss, fetching recent achievements from API');

      final response = await _apiClient.get(ApiEndpoints.recentAchievements);

      if (response['status'] == 'success' &&
          response['recent_achievements'] != null) {
        final recentAchievementsData = response['recent_achievements'] as List;

        // Cache the data
        await _cacheService.cacheRecentAchievements(recentAchievementsData);
        debugPrint(
            '🏆 [AchievementRepository] Cached ${recentAchievementsData.length} recent achievements');

        return recentAchievementsData
            .map((json) => UserAchievement.fromJson(json))
            .toList();
      }

      return [];
    } catch (e) {
      AppLogger.error('Error fetching recent achievements', exception: e);
      throw Exception('Failed to fetch recent achievements: $e');
    }
  }

  /// Clears all cached achievement data
  Future<void> clearCache() async {
    await _cacheService.clearCache();
    debugPrint('🏆 [AchievementRepository] Cleared all achievement cache');
  }

  /// Checks if the cache is expired
  Future<bool> isCacheExpired() async {
    return await _cacheService.isCacheExpired();
  }
}
