import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart'; // Added import for debugPrint

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
      // Convert filter to the sort_by parameter format expected by API
      String sortBy;
      switch (filter) {
        case 'calories':
          sortBy = 'calories_desc';
          break;
        case 'distance':
          sortBy = 'distance_desc';
          break;
        case 'duration':
          sortBy = 'duration_desc';
          break;
        case 'elevation':
          sortBy = 'elevation_gain_desc';
          break;
        case 'closest':
        default:
          sortBy = 'proximity_asc';
          break;
      }

      final queryParams = {
        'page': (offset ~/ limit + 1).toString(), // Convert offset to page number
        'per_page': limit.toString(),
        'sort_by': sortBy,
      };
      
      // Add location data if available and we're using proximity filter
      if (sortBy == 'proximity_asc' && latitude != null && longitude != null) {
        queryParams['latitude'] = latitude.toString();
        queryParams['longitude'] = longitude.toString();
      }
      
      final response = await apiClient.get(
        '/ruck-buddies',  // Removed duplicate '/api/' since it's already in the base URL
        queryParams: queryParams,
      );
      
      // Debug logging to see raw response
      debugPrint('[API] Raw ruck buddies response type: ${response.runtimeType}');
      debugPrint('[API] Response keys: ${response is Map ? (response as Map).keys.toString() : 'Not a map'}');

      // Process the API response
      Map<String, dynamic> responseData;
      if (response is Map) {
        // Convert Map<dynamic, dynamic> to Map<String, dynamic>
        responseData = Map<String, dynamic>.from(response.map(
          (key, value) => MapEntry(key.toString(), value),
        ));
      } else if (response is String) {
        responseData = json.decode(response);
      } else {
        throw ServerException(message: 'Unexpected response format');
      }

      // Check for ruck data
      final List<dynamic> data;
      
      // First check for 'ruck_sessions' key (used by our backend)
      if (responseData.containsKey('ruck_sessions') && responseData['ruck_sessions'] is List) {
        data = responseData['ruck_sessions'];
        debugPrint('Found ${data.length} ruck sessions in response');
      }
      // Fall back to 'data' key (used in some API versions)
      else if (responseData.containsKey('data') && responseData['data'] is List) {
        data = responseData['data'];
        debugPrint('Found ${data.length} ruck sessions in data field');
      }
      // Handle case where response is directly a List
      else if (response is List) {
        data = response;
        debugPrint('Response is directly a list with ${data.length} items');
      }
      // No recognized data format found
      else {
        debugPrint('No ruck sessions found in response: $responseData');
        data = [];
      }
      
      return data.map((item) => RuckBuddyModel.fromJson(item)).toList();
    } catch (e) {
      throw ServerException(
        message: 'Failed to load ruck buddies data: ${e.toString()}',
      );
    }
  }
}
