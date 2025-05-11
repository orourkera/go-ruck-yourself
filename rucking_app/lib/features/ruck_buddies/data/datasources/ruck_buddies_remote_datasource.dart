import 'dart:convert';
import 'package:rucking_app/core/error/exceptions.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/features/ruck_buddies/data/models/ruck_buddy_model.dart';

abstract class RuckBuddiesRemoteDataSource {
  /// Gets a list of public ruck sessions from other users
  /// 
  /// Filter types: 'recent', 'popular', 'distance', 'duration'
  ///
  /// Throws a [ServerException] if there is an error
  Future<List<RuckBuddyModel>> getRuckBuddies({
    required int limit, 
    required int offset, 
    required String filter
  });
}

class RuckBuddiesRemoteDataSourceImpl implements RuckBuddiesRemoteDataSource {
  final ApiClient apiClient;

  RuckBuddiesRemoteDataSourceImpl({required this.apiClient});

  @override
  Future<List<RuckBuddyModel>> getRuckBuddies({
    required int limit, 
    required int offset, 
    required String filter
  }) async {
    try {
      final response = await apiClient.get(
        '/ruck-buddies',
        queryParams: {
          'limit': limit.toString(),
          'offset': offset.toString(),
          'filter': filter,
        },
      );

      final Map<String, dynamic> jsonResponse = json.decode(response);
      final List<dynamic> data = jsonResponse['ruck_sessions'] ?? [];
      
      return data.map((item) => RuckBuddyModel.fromJson(item)).toList();
    } catch (e) {
      throw ServerException(
        message: 'Failed to load ruck buddies data: ${e.toString()}',
      );
    }
  }
}
