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
        '/api/leaderboard',
        queryParams: queryParams,
      );

      return LeaderboardResponseModel.fromJson(response.data);
    } catch (e) {
      throw Exception('Failed to fetch leaderboard: $e');
    }
  }

  /// Get current user's rank on the leaderboard
  Future<int?> getCurrentUserRank({String sortBy = 'powerPoints'}) async {
    try {
      final response = await apiClient.get(
        '/api/leaderboard/my-rank',
        queryParams: {
          'sort_by': _mapSortField(sortBy),
        },
      );

      return response.data['rank'] as int?;
    } catch (e) {
      // User might not be on leaderboard yet
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
