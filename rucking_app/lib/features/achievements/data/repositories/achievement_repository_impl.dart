import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/network/api_endpoints.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/achievements/data/models/achievement_model.dart';
import 'package:rucking_app/features/achievements/domain/repositories/achievement_repository.dart';

class AchievementRepositoryImpl implements AchievementRepository {
  final ApiClient _apiClient;

  AchievementRepositoryImpl({
    required ApiClient apiClient,
  }) : _apiClient = apiClient;

  @override
  Future<List<Achievement>> getAllAchievements() async {
    try {
      final response = await _apiClient.get(ApiEndpoints.achievements);
      
      // The API returns: {'status': 'success', 'achievements': [...]}
      if (response['status'] == 'success' && response['achievements'] != null) {
        final achievementsData = response['achievements'] as List;
        return achievementsData
            .map((json) => Achievement.fromJson(json))
            .toList();
      }
      
      return [];
    } catch (e) {
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
      final endpoint = ApiEndpoints.getUserAchievementsEndpoint(userId);
      final response = await _apiClient.get(endpoint);
      
      if (response['status'] == 'success' && response['user_achievements'] != null) {
        final userAchievementsData = response['user_achievements'] as List;
        return userAchievementsData
            .map((json) => UserAchievement.fromJson(json))
            .toList();
      }
      
      return [];
    } catch (e) {
      AppLogger.error('Error fetching user achievements', exception: e);
      throw Exception('Failed to fetch user achievements: $e');
    }
  }

  @override
  Future<List<AchievementProgress>> getUserAchievementProgress(String userId) async {
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
      final endpoint = ApiEndpoints.getCheckSessionAchievementsEndpoint(sessionId.toString());
      final response = await _apiClient.post(endpoint, {});
      
      if (response['status'] == 'success' && response['new_achievements'] != null) {
        final newAchievementsData = response['new_achievements'] as List;
        return newAchievementsData
            .map((json) => Achievement.fromJson(json))
            .toList();
      }
      
      return [];
    } catch (e) {
      AppLogger.error('Error checking session achievements', exception: e);
      throw Exception('Failed to check session achievements: $e');
    }
  }

  @override
  Future<AchievementStats> getAchievementStats(String userId) async {
    try {
      final endpoint = ApiEndpoints.getAchievementStatsEndpoint(userId);
      final response = await _apiClient.get(endpoint);
      
      if (response['status'] == 'success' && response['stats'] != null) {
        return AchievementStats.fromJson(response['stats']);
      }
      
      // Return empty stats if no data
      return const AchievementStats(
        totalEarned: 0,
        totalAvailable: 0,
        completionPercentage: 0.0,
        byCategory: {},
        byTier: {},
      );
    } catch (e) {
      AppLogger.error('Error fetching achievement stats', exception: e);
      throw Exception('Failed to fetch achievement stats: $e');
    }
  }

  @override
  Future<List<UserAchievement>> getRecentAchievements() async {
    try {
      final response = await _apiClient.get(ApiEndpoints.recentAchievements);
      
      if (response['status'] == 'success' && response['recent_achievements'] != null) {
        final recentAchievementsData = response['recent_achievements'] as List;
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
}
