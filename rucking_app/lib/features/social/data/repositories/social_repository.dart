import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:rucking_app/core/services/auth_service.dart';
import 'package:rucking_app/core/config/app_config.dart';

import 'package:rucking_app/features/social/domain/models/ruck_like.dart';
import 'package:rucking_app/features/social/domain/models/ruck_comment.dart';
import 'package:rucking_app/core/error/exceptions.dart';

/// Repository for handling social interactions (likes, comments)
class SocialRepository {
  final http.Client _httpClient;
  final AuthService _authService;

  /// Constructor
  SocialRepository({
    required http.Client httpClient,
    required AuthService authService,
  }) : 
    _httpClient = httpClient,
    _authService = authService;

  /// Get the JWT token for authorization using AuthService
  Future<String?> get _authToken async {
    try {
      // Use the AuthService to get the token
      return await _authService.getToken();
    } catch (e) {
      debugPrint('Error getting auth token: $e');
      return null;
    }
  }

  /// Get likes for a specific ruck session
  Future<List<RuckLike>> getRuckLikes(int ruckId) async {
    try {
      final token = await _authToken;
      if (token == null) {
        throw UnauthorizedException(message: 'User is not authenticated');
      }

      final response = await _httpClient.get(
        Uri.parse('${AppConfig.apiBaseUrl}/ruck-likes?ruck_id=$ruckId'),
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
        throw UnauthorizedException(message: 'Unauthorized request');
      } else {
        throw ServerException(
            message: 'Failed to get likes: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      if (e is UnauthorizedException) rethrow;
      throw ServerException(message: 'Failed to get likes: $e');
    }
  }

  /// Add a like to a ruck session
  Future<RuckLike> addRuckLike(int ruckId) async {
    debugPrint('🔍 SocialRepository.addRuckLike called for ruckId: $ruckId');
    try {
      debugPrint('🔍 Getting auth token...');
      final token = await _authToken;
      debugPrint('🔍 Auth token retrieved: ${token != null ? 'YES' : 'NO'}');
      
      if (token == null) {
        debugPrint('⚠ No auth token available');
        throw UnauthorizedException(message: 'User is not authenticated');
      }

      debugPrint('🔍 Making API request to add like');
      final endpoint = '${AppConfig.apiBaseUrl}/ruck-likes';
      final payload = {'ruck_id': ruckId};
      debugPrint('🔍 Endpoint: $endpoint');
      debugPrint('🔍 Request payload: $payload');
      final response = await _httpClient.post(
        Uri.parse(endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode(payload),
      );
      
      debugPrint('🔍 API response status code: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final Map<String, dynamic> data = json.decode(response.body);
        debugPrint('🔍 API response data: $data');
        if (data['success'] == true && data['data'] != null) {
          final ruckLike = RuckLike.fromJson(data['data']);
          debugPrint('✅ Successfully added like with id: ${ruckLike.id}');
          return ruckLike;
        } else {
          debugPrint('⚠ Invalid response data: $data');
          throw ServerException(message: 'Failed to add like: Invalid response data');
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        debugPrint('⚠ Unauthorized request: ${response.statusCode}');
        throw UnauthorizedException(message: 'Unauthorized request');
      } else {
        debugPrint('⚠ Server error: ${response.statusCode} - ${response.body}');
        throw ServerException(
            message: 'Failed to add like: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      if (e is UnauthorizedException) rethrow;
      throw ServerException(message: 'Failed to add like: $e');
    }
  }

  /// Remove a like from a ruck session
  Future<bool> removeRuckLike(int ruckId) async {
    try {
      final token = await _authToken;
      if (token == null) {
        throw UnauthorizedException(message: 'User is not authenticated');
      }

      // For DELETE requests, use query parameters instead of request body
      final endpoint = '${AppConfig.apiBaseUrl}/ruck-likes?ruck_id=$ruckId';
      debugPrint('🔍 Endpoint: $endpoint');
      final response = await _httpClient.delete(
        Uri.parse(endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        // No body needed, ruck_id is in query parameter
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final Map<String, dynamic> data = json.decode(response.body);
        return data['success'] == true;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw UnauthorizedException(message: 'Unauthorized request');
      } else {
        throw ServerException(
            message: 'Failed to remove like: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      if (e is UnauthorizedException) rethrow;
      throw ServerException(message: 'Failed to remove like: $e');
    }
  }

  /// Check if the current user has liked a specific ruck session
  Future<bool> hasUserLikedRuck(int ruckId) async {
    debugPrint('🔍 SocialRepository.hasUserLikedRuck called for ruckId: $ruckId');
    try {
      debugPrint('🔍 Getting auth token...');
      final token = await _authToken;
      debugPrint('🔍 Auth token retrieved: ${token != null ? 'YES' : 'NO'}');
      
      if (token == null) {
        debugPrint('⚠ No auth token available');
        throw UnauthorizedException(message: 'User is not authenticated');
      }

      debugPrint('🔍 Making API request to check if user liked ruck');
      final endpoint = '${AppConfig.apiBaseUrl}/ruck-likes/check?ruck_id=$ruckId';
      debugPrint('🔍 Endpoint: $endpoint');
      
      final response = await _httpClient.get(
        Uri.parse(endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      
      debugPrint('🔍 API response status code: ${response.statusCode}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        debugPrint('🔍 API response data: $data');
        
        // The API returns {"success": true, "data": {"has_liked": true/false}}
        // Need to check data['data']['has_liked'] rather than just data['data']
        final result = data['success'] == true && 
                      (data['data'] != null && data['data']['has_liked'] == true);
                      
        debugPrint('🔍 User has liked this ruck: $result');
        return result;
      } else if (response.statusCode == 404) {
        // If the like doesn't exist, return false
        debugPrint('🔍 Like not found (404), returning false');
        return false;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        debugPrint('⚠ Unauthorized request: ${response.statusCode}');
        throw UnauthorizedException(message: 'Unauthorized request');
      } else {
        debugPrint('⚠ Server error: ${response.statusCode} - ${response.body}');
        throw ServerException(
            message: 'Failed to check like status: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      if (e is UnauthorizedException) rethrow;
      throw ServerException(message: 'Failed to check like status: $e');
    }
  }

  /// Get comments for a specific ruck session
  Future<List<RuckComment>> getRuckComments(int ruckId) async {
    try {
      final token = await _authToken;
      if (token == null) {
        throw UnauthorizedException(message: 'User is not authenticated');
      }

      final response = await _httpClient.get(
        Uri.parse('${AppConfig.apiBaseUrl}/ruck-comments?ruck_id=$ruckId'),
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
        throw UnauthorizedException(message: 'Unauthorized request');
      } else {
        throw ServerException(
            message: 'Failed to get comments: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      if (e is UnauthorizedException) rethrow;
      throw ServerException(message: 'Failed to get comments: $e');
    }
  }

  /// Add a comment to a ruck session
  Future<RuckComment> addRuckComment(int ruckId, String content) async {
    try {
      final token = await _authToken;
      if (token == null) {
        throw UnauthorizedException(message: 'User is not authenticated');
      }

      final response = await _httpClient.post(
        Uri.parse('${AppConfig.apiBaseUrl}/ruck-comments'),
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
          throw ServerException(message: 'Failed to add comment: Invalid response data');
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw UnauthorizedException(message: 'Unauthorized request');
      } else {
        throw ServerException(
            message: 'Failed to add comment: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      if (e is UnauthorizedException) rethrow;
      throw ServerException(message: 'Failed to add comment: $e');
    }
  }

  /// Update an existing comment
  Future<RuckComment> updateRuckComment(String commentId, String content) async {
    try {
      final token = await _authToken;
      if (token == null) {
        throw UnauthorizedException(message: 'User is not authenticated');
      }

      final response = await _httpClient.put(
        Uri.parse('${AppConfig.apiBaseUrl}/ruck-comments'),
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
          throw ServerException(message: 'Failed to update comment: Invalid response data');
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw UnauthorizedException(message: 'Unauthorized request');
      } else {
        throw ServerException(
            message: 'Failed to update comment: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      if (e is UnauthorizedException) rethrow;
      throw ServerException(message: 'Failed to update comment: $e');
    }
  }

  /// Delete a comment
  Future<bool> deleteRuckComment(String commentId) async {
    try {
      final token = await _authToken;
      if (token == null) {
        throw UnauthorizedException(message: 'User is not authenticated');
      }

      final response = await _httpClient.delete(
        Uri.parse('${AppConfig.apiBaseUrl}/ruck-comments?comment_id=$commentId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        return data['success'] == true;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw UnauthorizedException(message: 'Unauthorized request');
      } else {
        throw ServerException(
            message: 'Failed to delete comment: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      if (e is UnauthorizedException) rethrow;
      throw ServerException(message: 'Failed to delete comment: $e');
    }
  }
}
