import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart'; // Added import for debugPrint
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:get_it/get_it.dart';

import 'package:rucking_app/core/error/exceptions.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/auth_service_consolidated.dart';
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
  Future<List<RuckBuddyModel>> getRuckBuddies(
      {required int limit,
      required int offset,
      required String filter,
      double? latitude,
      double? longitude});
}

class RuckBuddiesRemoteDataSourceImpl implements RuckBuddiesRemoteDataSource {
  final ApiClient apiClient;

  RuckBuddiesRemoteDataSourceImpl({required this.apiClient});

  @override
  Future<List<RuckBuddyModel>> getRuckBuddies(
      {required int limit,
      required int offset,
      required String filter,
      double? latitude,
      double? longitude}) async {
    try {
      // Convert filter to the sort_by parameter format expected by API
      String sortBy;
      bool followingOnly = false;

      switch (filter) {
        case 'following':
          sortBy = 'proximity_asc'; // Default sort for following
          followingOnly = true;
          break;
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
        'page':
            (offset ~/ limit + 1).toString(), // Convert offset to page number
        'per_page': limit.toString(),
        'sort_by': sortBy,
        'exclude_manual': 'true', // Exclude manual sessions
        'following_only': followingOnly.toString(),
      };

      // Add location data if available and we're using proximity filter
      if (sortBy == 'proximity_asc' && latitude != null && longitude != null) {
        queryParams['latitude'] = latitude.toString();
        queryParams['longitude'] = longitude.toString();
      }

      // Get current user ID for following filter
      String? currentUserId;
      if (followingOnly) {
        try {
          final authService = GetIt.instance<AuthService>();
          final user = await authService.getCurrentUser();
          currentUserId = user?.userId;
        } catch (e) {
          debugPrint('Error getting current user ID for following filter: $e');
        }
      }

      // Call Supabase RPC function directly for optimized route data
      final response = await supabase.Supabase.instance.client.rpc(
        'get_public_sessions_optimized',
        params: {
          'p_page': (offset ~/ limit + 1),
          'p_per_page': limit,
          'p_sort_by': sortBy,
          'p_following_only': followingOnly,
          'p_latitude': latitude,
          'p_longitude': longitude,
          if (currentUserId != null) 'p_user_id': currentUserId,
        },
      );

      // Debug logging to see raw response
      debugPrint(
          '[API] Raw ruck buddies response type: ${response.runtimeType}');
      debugPrint(
          '[API] Response keys: ${response is Map ? (response as Map).keys.toString() : 'Not a map'}');

      // More detailed logging of first several entries
      if (response is Map &&
          response.containsKey('ruck_sessions') &&
          response['ruck_sessions'] is List) {
        List<dynamic> sessions = response['ruck_sessions'];
        for (int i = 0; i < (sessions.length > 3 ? 3 : sessions.length); i++) {
          var session = sessions[i];
          debugPrint('=== RUCK SESSION ${session['id']} DEBUG ===');
          debugPrint('Has photos key? ${session.containsKey('photos')}');
          debugPrint('Photos value type: ${session['photos']?.runtimeType}');
          debugPrint('Photos value: ${session['photos']}');
        }
      }

      // Use the same proven logic as homepage _processSessionResponse
      List<dynamic> data;
      if (response == null) {
        data = [];
      } else if (response is List) {
        data = response;
        debugPrint('Found ${data.length} ruck sessions in RPC response');
      } else if (response is Map &&
          response.containsKey('data') &&
          response['data'] is List) {
        data = response['data'] as List;
        debugPrint('Found ${data.length} ruck sessions in data field');
      } else if (response is Map &&
          response.containsKey('sessions') &&
          response['sessions'] is List) {
        data = response['sessions'] as List;
        debugPrint('Found ${data.length} ruck sessions in sessions field');
      } else if (response is Map &&
          response.containsKey('items') &&
          response['items'] is List) {
        data = response['items'] as List;
        debugPrint('Found ${data.length} ruck sessions in items field');
      } else if (response is Map &&
          response.containsKey('results') &&
          response['results'] is List) {
        data = response['results'] as List;
        debugPrint('Found ${data.length} ruck sessions in results field');
      } else if (response is Map) {
        // Search for any List field in response
        List<dynamic> foundList = [];
        for (var key in response.keys) {
          if (response[key] is List) {
            foundList = response[key] as List;
            debugPrint('Found ${foundList.length} ruck sessions in $key field');
            break;
          }
        }
        data = foundList;
      } else {
        debugPrint('No ruck sessions found in response: $response');
        data = [];
      }

      // Add null safety and type checking for RPC response
      final processedData = <RuckBuddyModel>[];
      for (int i = 0; i < data.length; i++) {
        final item = data[i];
        if (item == null) {
          debugPrint('⚠️ Session $i is null, skipping');
          continue;
        }
        if (item is! Map<String, dynamic>) {
          debugPrint(
              '⚠️ Session $i is not a Map: ${item.runtimeType}, skipping');
          continue;
        }
        try {
          processedData.add(RuckBuddyModel.fromJson(item));
        } catch (e) {
          debugPrint('⚠️ Error parsing session $i: $e');
          debugPrint('⚠️ Session data: $item');
          // Continue processing other sessions
        }
      }

      debugPrint(
          '✅ Successfully parsed ${processedData.length}/${data.length} ruck buddy sessions');
      return processedData;
    } catch (e) {
      throw ServerException(
        message: 'Failed to load ruck buddies data: ${e.toString()}',
      );
    }
  }
}
