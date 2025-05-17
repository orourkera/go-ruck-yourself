import 'dart:convert';

import 'package:rucking_app/core/error/exceptions.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/features/ruck_buddies/data/models/ruck_buddy_model.dart';

abstract class RuckBuddiesRemoteDataSource {
  /// Gets a list of public ruck sessions from other users
  /// 
  /// Filter options: 
  /// - 'closest' - Closest rucks (requires lat/lon)
  /// - 'calories' - Most calories burned
  /// - 'distance' - Furthest distance
  /// - 'duration' - Longest duration
  /// - 'elevation' - Most elevation gain
  ///
  /// Throws a [ServerException] if there is an error
  Future<List<RuckBuddyModel>> getRuckBuddies({
    required int limit, 
    required int offset, 
    required String filter,
    double? latitude,
    double? longitude
  });
}

class RuckBuddiesRemoteDataSourceImpl implements RuckBuddiesRemoteDataSource {
  final ApiClient apiClient;

  RuckBuddiesRemoteDataSourceImpl({required this.apiClient});

  @override
  Future<List<RuckBuddyModel>> getRuckBuddies({
    required int limit, 
    required int offset, 
    required String filter,
    double? latitude,
    double? longitude
  }) async {
    try {
      final queryParams = {
        'limit': limit.toString(),
        'offset': offset.toString(),
        'filter': filter,
      };
      
      // Add location data if available and we're using proximity filter
      if (filter == 'closest' && latitude != null && longitude != null) {
        queryParams['latitude'] = latitude.toString();
        queryParams['longitude'] = longitude.toString();
      }
      
      final response = await apiClient.get(
        '/api/ruck-buddies',
        queryParams: queryParams,
      );

      final Map<String, dynamic> jsonResponse = response;
      final List<dynamic> data = jsonResponse['ruck_sessions'] ?? [];
      
      return data.map((item) => RuckBuddyModel.fromJson(item)).toList();
    } catch (e) {
      throw ServerException(
        message: 'Failed to load ruck buddies data: ${e.toString()}',
      );
    }
  }
}
