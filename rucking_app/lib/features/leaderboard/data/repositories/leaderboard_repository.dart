import 'package:flutter/foundation.dart';
import '../models/leaderboard_user_model.dart';
import '../models/leaderboard_response_model.dart';
import '../../../../core/services/api_client.dart';

/// Well I'll be hornswoggled! This repository fetches leaderboard data slicker than a greased pig
class LeaderboardRepository {
  final ApiClient apiClient;

  const LeaderboardRepository({
    required this.apiClient,
  });

  /// Fetch leaderboard data from the API
  /// Returns a list of users and their stats, sorted by the specified criteria
  /// 
  /// 🔒 PRIVACY NOTE: Backend MUST filter out users with Allow_Ruck_Sharing = false
  /// Get leaderboard data with sorting, pagination, and search
  /// CRITICAL: Backend filters users with Allow_Ruck_Sharing = false for privacy
  Future<LeaderboardResponseModel> getLeaderboard({
    String sortBy = 'powerPoints',
    bool ascending = false,
    int limit = 50,
    int offset = 0,
    String? searchQuery,
  }) async {
    try {
      // Build query parameters like stacking hay bales
      final queryParams = <String, String>{
        'sort_by': _mapSortField(sortBy),
        'order': ascending ? 'asc' : 'desc',
        'limit': limit.toString(),
        'offset': offset.toString(),
      };

      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        queryParams['search'] = searchQuery.trim();
      }

      final response = await apiClient.get(
        '/leaderboard',
        queryParams: queryParams,
      );
    
    // Debug logging
    debugPrint('[LEADERBOARD] Raw API response type: ${response.runtimeType}');
    debugPrint('[LEADERBOARD] Raw API response: ${response.toString().length > 500 ? '${response.toString().substring(0, 500)}...' : response.toString()}');
    
    // The response is already the parsed JSON data from ApiClient.get()
    final jsonData = response is Map<String, dynamic> ? response : response.data;
    debugPrint('[LEADERBOARD] Parsed JSON data type: ${jsonData.runtimeType}');
    debugPrint('[LEADERBOARD] JSON keys: ${jsonData is Map ? jsonData.keys.toList() : 'Not a Map'}');
    
    final result = LeaderboardResponseModel.fromJson(jsonData);
    debugPrint('[LEADERBOARD] Parsed ${result.users.length} users successfully');
    
    return result;
    } catch (e) {
      throw Exception('Failed to fetch leaderboard: $e');
    }
  }

  /// Get current user's rank on the leaderboard
  Future<int?> getCurrentUserRank({String sortBy = 'powerPoints'}) async {
    try {
      final response = await apiClient.get(
        '/leaderboard/my-rank',
        queryParams: {
          'sort_by': _mapSortField(sortBy),
        },
      );

      // Handle response correctly - it might be direct JSON or wrapped
      final jsonData = response is Map<String, dynamic> ? response : response.data;
      return jsonData['rank'] as int?;
    } catch (e) {
      // User might not be on leaderboard yet
      debugPrint('[LEADERBOARD] Failed to get user rank: $e');
      return null;
    }
  }

  /// Map Flutter field names to backend field names like translating pig latin
  String _mapSortField(String sortBy) {
    switch (sortBy) {
      case 'totalRucks':
        return 'total_rucks';
      case 'distanceKm':
        return 'total_distance_km';
      case 'elevationGainMeters':
        return 'total_elevation_gain_meters';
      case 'caloriesBurned':
        return 'total_calories_burned';
      case 'powerPoints':
        return 'total_power_points';
      case 'averageDistanceKm':
        return 'average_distance_km';
      case 'averagePaceMinKm':
        return 'average_pace_min_km';
      default:
        return 'total_power_points'; // Default to power points
    }
  }
}
