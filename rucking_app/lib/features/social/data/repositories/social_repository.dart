import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:rucking_app/features/social/domain/models/ruck_like.dart';
import 'package:rucking_app/features/social/domain/models/ruck_comment.dart';
import 'package:rucking_app/core/error/exceptions.dart';
import 'package:rucking_app/core/network/api_endpoints.dart';

/// Repository for handling social interactions (likes, comments)
class SocialRepository {
  final http.Client _httpClient;
  final SupabaseClient _supabaseClient;

  /// Constructor
  SocialRepository({
    required http.Client httpClient,
    required SupabaseClient supabaseClient,
  })  : _httpClient = httpClient,
        _supabaseClient = supabaseClient;

  /// Get the JWT token for authorization
  Future<String?> _getAuthToken() async {
    return _supabaseClient.auth.currentSession?.accessToken;
  }

  /// Get likes for a specific ruck session
  Future<List<RuckLike>> getRuckLikes(int ruckId) async {
    try {
      final token = await _getAuthToken();
      if (token == null) {
        throw UnauthorizedException('User is not authenticated');
      }

      final response = await _httpClient.get(
        Uri.parse('${ApiEndpoints.baseUrl}/api/ruck-likes?ruck_id=$ruckId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return (data['data'] as List)
              .map((json) => RuckLike.fromJson(json))
              .toList();
        } else {
          return [];
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw UnauthorizedException('Unauthorized request');
      } else {
        throw ServerException(
            'Failed to get likes: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      if (e is UnauthorizedException) rethrow;
      throw ServerException('Failed to get likes: $e');
    }
  }

  /// Add a like to a ruck session
  Future<RuckLike> addRuckLike(int ruckId) async {
    try {
      final token = await _getAuthToken();
      if (token == null) {
        throw UnauthorizedException('User is not authenticated');
      }

      final response = await _httpClient.post(
        Uri.parse('${ApiEndpoints.baseUrl}/api/ruck-likes'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'ruck_id': ruckId,
        }),
      );

      if (response.statusCode == 201) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return RuckLike.fromJson(data['data']);
        } else {
          throw ServerException('Failed to add like: Invalid response data');
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw UnauthorizedException('Unauthorized request');
      } else {
        throw ServerException(
            'Failed to add like: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      if (e is UnauthorizedException) rethrow;
      throw ServerException('Failed to add like: $e');
    }
  }

  /// Remove a like from a ruck session
  Future<bool> removeRuckLike(int ruckId) async {
    try {
      final token = await _getAuthToken();
      if (token == null) {
        throw UnauthorizedException('User is not authenticated');
      }

      final response = await _httpClient.delete(
        Uri.parse('${ApiEndpoints.baseUrl}/api/ruck-likes?ruck_id=$ruckId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        return data['success'] == true;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw UnauthorizedException('Unauthorized request');
      } else {
        throw ServerException(
            'Failed to remove like: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      if (e is UnauthorizedException) rethrow;
      throw ServerException('Failed to remove like: $e');
    }
  }

  /// Check if the current user has liked a specific ruck session
  Future<bool> hasUserLikedRuck(int ruckId) async {
    try {
      final token = await _getAuthToken();
      if (token == null) {
        throw UnauthorizedException('User is not authenticated');
      }

      final response = await _httpClient.get(
        Uri.parse('${ApiEndpoints.baseUrl}/api/ruck-likes/check?ruck_id=$ruckId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return data['data']['has_liked'] ?? false;
        } else {
          return false;
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw UnauthorizedException('Unauthorized request');
      } else {
        throw ServerException(
            'Failed to check like status: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      if (e is UnauthorizedException) rethrow;
      throw ServerException('Failed to check like status: $e');
    }
  }

  /// Get comments for a specific ruck session
  Future<List<RuckComment>> getRuckComments(int ruckId) async {
    try {
      final token = await _getAuthToken();
      if (token == null) {
        throw UnauthorizedException('User is not authenticated');
      }

      final response = await _httpClient.get(
        Uri.parse('${ApiEndpoints.baseUrl}/api/ruck-comments?ruck_id=$ruckId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return (data['data'] as List)
              .map((json) => RuckComment.fromJson(json))
              .toList();
        } else {
          return [];
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw UnauthorizedException('Unauthorized request');
      } else {
        throw ServerException(
            'Failed to get comments: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      if (e is UnauthorizedException) rethrow;
      throw ServerException('Failed to get comments: $e');
    }
  }

  /// Add a comment to a ruck session
  Future<RuckComment> addRuckComment(int ruckId, String content) async {
    try {
      final token = await _getAuthToken();
      if (token == null) {
        throw UnauthorizedException('User is not authenticated');
      }

      final response = await _httpClient.post(
        Uri.parse('${ApiEndpoints.baseUrl}/api/ruck-comments'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'ruck_id': ruckId,
          'content': content,
        }),
      );

      if (response.statusCode == 201) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return RuckComment.fromJson(data['data']);
        } else {
          throw ServerException('Failed to add comment: Invalid response data');
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw UnauthorizedException('Unauthorized request');
      } else {
        throw ServerException(
            'Failed to add comment: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      if (e is UnauthorizedException) rethrow;
      throw ServerException('Failed to add comment: $e');
    }
  }

  /// Update an existing comment
  Future<RuckComment> updateRuckComment(String commentId, String content) async {
    try {
      final token = await _getAuthToken();
      if (token == null) {
        throw UnauthorizedException('User is not authenticated');
      }

      final response = await _httpClient.put(
        Uri.parse('${ApiEndpoints.baseUrl}/api/ruck-comments'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'comment_id': commentId,
          'content': content,
        }),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return RuckComment.fromJson(data['data']);
        } else {
          throw ServerException('Failed to update comment: Invalid response data');
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw UnauthorizedException('Unauthorized request');
      } else {
        throw ServerException(
            'Failed to update comment: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      if (e is UnauthorizedException) rethrow;
      throw ServerException('Failed to update comment: $e');
    }
  }

  /// Delete a comment
  Future<bool> deleteRuckComment(String commentId) async {
    try {
      final token = await _getAuthToken();
      if (token == null) {
        throw UnauthorizedException('User is not authenticated');
      }

      final response = await _httpClient.delete(
        Uri.parse('${ApiEndpoints.baseUrl}/api/ruck-comments?comment_id=$commentId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        return data['success'] == true;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw UnauthorizedException('Unauthorized request');
      } else {
        throw ServerException(
            'Failed to delete comment: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      if (e is UnauthorizedException) rethrow;
      throw ServerException('Failed to delete comment: $e');
    }
  }
}
