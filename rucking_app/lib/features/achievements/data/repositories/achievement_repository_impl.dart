import 'package:rucking_app/core/network/api_endpoints.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/features/achievements/data/models/achievement_model.dart';
import 'package:rucking_app/features/achievements/domain/repositories/achievement_repository.dart';
import 'package:rucking_app/core/api/api_exceptions.dart';

/// Implementation of the AchievementRepository interface
class AchievementRepositoryImpl implements AchievementRepository {
  final ApiClient _apiClient;
  
  AchievementRepositoryImpl(this._apiClient);
  
  @override
  Future<List<Achievement>> getAchievements() async {
    try {
      final response = await _apiClient.get(ApiEndpoints.achievements);
      
      if (response.data['status'] == 'success') {
        final List<dynamic> achievementsData = response.data['achievements'] ?? [];
        return achievementsData
            .map((json) => Achievement.fromJson(json))
            .toList();
      } else {
        throw ApiException('Failed to fetch achievements');
      }
    } catch (e) {
      throw ApiException('Error fetching achievements: $e');
    }
  }
  
  @override
  Future<List<String>> getAchievementCategories() async {
    try {
      final response = await _apiClient.get(ApiEndpoints.achievementCategories);
      
      if (response.data['status'] == 'success') {
        final List<dynamic> categoriesData = response.data['categories'] ?? [];
        return categoriesData.cast<String>();
      } else {
        throw ApiException('Failed to fetch achievement categories');
      }
    } catch (e) {
      throw ApiException('Error fetching achievement categories: $e');
    }
  }
  
  @override
  Future<List<UserAchievement>> getUserAchievements(String userId) async {
    try {
      final endpoint = ApiEndpoints.getUserAchievementsEndpoint(userId);
      final response = await _apiClient.get(endpoint);
      
      if (response.data['status'] == 'success') {
        final List<dynamic> achievementsData = response.data['user_achievements'] ?? [];
        return achievementsData
            .map((json) => UserAchievement.fromJson(json))
            .toList();
      } else {
        throw ApiException('Failed to fetch user achievements');
      }
    } catch (e) {
      throw ApiException('Error fetching user achievements: $e');
    }
  }
  
  @override
  Future<List<AchievementProgress>> getUserAchievementProgress(String userId) async {
    try {
      final endpoint = ApiEndpoints.getUserAchievementsProgressEndpoint(userId);
      final response = await _apiClient.get(endpoint);
      
      if (response.data['status'] == 'success') {
        final List<dynamic> progressData = response.data['achievement_progress'] ?? [];
        return progressData
            .map((json) => AchievementProgress.fromJson(json))
            .toList();
      } else {
        throw ApiException('Failed to fetch achievement progress');
      }
    } catch (e) {
      throw ApiException('Error fetching achievement progress: $e');
    }
  }
  
  @override
  Future<List<Achievement>> checkSessionAchievements(int sessionId) async {
    try {
      final endpoint = ApiEndpoints.getCheckSessionAchievementsEndpoint(sessionId.toString());
      final response = await _apiClient.post(endpoint, {});
      
      if (response.data['status'] == 'success') {
        final List<dynamic> newAchievementsData = response.data['new_achievements'] ?? [];
        return newAchievementsData
            .map((json) => Achievement.fromJson(json))
            .toList();
      } else {
        throw ApiException('Failed to check session achievements');
      }
    } catch (e) {
      throw ApiException('Error checking session achievements: $e');
    }
  }
  
  @override
  Future<AchievementStats> getAchievementStats(String userId) async {
    try {
      final endpoint = ApiEndpoints.getAchievementStatsEndpoint(userId);
      final response = await _apiClient.get(endpoint);
      
      if (response.data['status'] == 'success') {
        return AchievementStats.fromJson(response.data);
      } else {
        throw ApiException('Failed to fetch achievement stats');
      }
    } catch (e) {
      throw ApiException('Error fetching achievement stats: $e');
    }
  }
  
  @override
  Future<List<UserAchievement>> getRecentAchievements() async {
    try {
      final response = await _apiClient.get(ApiEndpoints.recentAchievements);
      
      if (response.data['status'] == 'success') {
        final List<dynamic> recentData = response.data['recent_achievements'] ?? [];
        return recentData
            .map((json) => UserAchievement.fromJson(json))
            .toList();
      } else {
        throw ApiException('Failed to fetch recent achievements');
      }
    } catch (e) {
      throw ApiException('Error fetching recent achievements: $e');
    }
  }
}
