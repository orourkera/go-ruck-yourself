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
  
  // Cache for social data to prevent repeated API calls
  final Map<int, bool> _likeStatusCache = {};
  final Map<int, int> _likeCountCache = {};
  final Map<String, List<RuckComment>> _commentsCache = {};
  final Map<int, DateTime> _likeCacheTimestamps = {};
  final Map<String, DateTime> _commentsCacheTimestamps = {};
  
  // Cache expiration in seconds - very short to ensure fresh data while still providing immediate response
  static const int _cacheExpirationSeconds = 10; // 10 seconds cache
  
  // Getters for cached data - these provide immediate access to cached values without network calls
  bool? getCachedLikeStatus(int ruckId) => _likeStatusCache[ruckId];
  int? getCachedLikeCount(int ruckId) => _likeCountCache[ruckId];
  List<RuckComment>? getCachedComments(String ruckId) => _commentsCache[ruckId];

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
      
      debugPrint('[SOCIAL_DEBUG] Getting likes for ruck $ruckId');

      // Don't include /api in the path as it's already in the base URL
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
  /// Updates the cache with the new like status
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
      debugPrint('🔍 Endpoint: $endpoint');
      final response = await _httpClient.post(
        Uri.parse(endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'ruck_id': ruckId,
        }),
      );
      debugPrint('🔍 Response status code: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          debugPrint('🔍 Successfully added like');
          
          // Update cache to set liked=true and increment like count
          _likeStatusCache[ruckId] = true;
          _likeCountCache[ruckId] = (_likeCountCache[ruckId] ?? 0) + 1;
          _likeCacheTimestamps[ruckId] = DateTime.now();
          debugPrint('🔍 Updated cache for ruckId: $ruckId, liked=true, count=${_likeCountCache[ruckId]}');
          
          return RuckLike.fromJson(data['data']);
        } else {
          debugPrint('⚠ API success but invalid response: ${response.body}');
          throw ServerException(message: 'Invalid response: ${response.body}');
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
  /// Updates the cache with the new unlike status
  Future<bool> removeRuckLike(int ruckId) async {
    debugPrint('[SOCIAL_DEBUG] removeRuckLike called for ruckId: $ruckId');
    try {
      final token = await _authToken;
      if (token == null) {
        throw UnauthorizedException(message: 'User is not authenticated');
      }

      // For DELETE requests, use query parameters instead of request body
      final endpoint = '${AppConfig.apiBaseUrl}/ruck-likes?ruck_id=$ruckId';
      debugPrint('[SOCIAL_DEBUG] Endpoint: $endpoint');
      final response = await _httpClient.delete(
        Uri.parse(endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final Map<String, dynamic> data = json.decode(response.body);
        final success = data['success'] == true;
        
        if (success) {
          // Update cache to set liked=false and decrement like count
          _likeStatusCache[ruckId] = false;
          _likeCountCache[ruckId] = (_likeCountCache[ruckId] ?? 1) - 1;
          if (_likeCountCache[ruckId]! < 0) _likeCountCache[ruckId] = 0; // Ensure count doesn't go below 0
          _likeCacheTimestamps[ruckId] = DateTime.now();
          debugPrint('[SOCIAL_DEBUG] Updated cache for ruckId: $ruckId, liked=false, count=${_likeCountCache[ruckId]}');
        }
        
        return success;
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

  /// Check if the current user has liked a specific ruck
  /// Uses caching to reduce API calls. If the cache is invalid, it fetches
  /// fresh data for both the user's like status and the total like count for the ruck,
  /// updating the respective caches.
  Future<bool> hasUserLikedRuck(int ruckId) async {
    debugPrint('[SOCIAL_DEBUG] hasUserLikedRuck called for ruckId: $ruckId');

    // Check cache first if it's valid
    if (_isValidCache(ruckId)) {
      debugPrint('[SOCIAL_DEBUG] Using cached like status for ruckId: $ruckId. Status: ${_likeStatusCache[ruckId]}, Count: ${_likeCountCache[ruckId]}');
      return _likeStatusCache[ruckId] ?? false;
    }

    debugPrint('[SOCIAL_DEBUG] Cache invalid for ruckId: $ruckId. Fetching fresh like status and count.');
    final token = await _authToken;
    if (token == null) {
      debugPrint('[SOCIAL_DEBUG] No auth token in hasUserLikedRuck for ruckId: $ruckId. Assuming not liked, count 0.');
      _likeStatusCache[ruckId] = false; // Update status cache
      _likeCountCache[ruckId] = 0;      // Update count cache
      _likeCacheTimestamps[ruckId] = DateTime.now(); // Update timestamp
      return false; // Not authenticated, so can't have liked it
    }

    // Fetch fresh like status for the user
    final freshHasLiked = await _fallbackSingleRuckCheck(ruckId, token);
    // Fetch fresh total like count for the ruck
    final freshLikeCount = await _fallbackSingleRuckLikeCount(ruckId, token);

    // Update caches with fresh data
    _likeStatusCache[ruckId] = freshHasLiked ?? false;
    _likeCountCache[ruckId] = freshLikeCount ?? 0; // Default to 0 if count fetch fails
    _likeCacheTimestamps[ruckId] = DateTime.now();

    debugPrint('[SOCIAL_DEBUG] Updated cache for ruckId: $ruckId. Status: ${freshHasLiked ?? false}, Count: ${freshLikeCount ?? 0}');

    return freshHasLiked ?? false; // If fallback returns null (error), treat as not liked
  }
  
  /// Checks if cache for a ruckId is still valid
  bool _isValidCache(int ruckId) {
    return _likeCacheTimestamps.containsKey(ruckId) &&
        DateTime.now().difference(_likeCacheTimestamps[ruckId]!) < const Duration(seconds: _cacheExpirationSeconds);
  }

  /// Fallback method for checking a single ruck like status
  /// Returns true/false if user has liked the ruck, or null on error
  Future<bool?> _fallbackSingleRuckCheck(int ruckId, String token) async {
    try {
      debugPrint('[SOCIAL_DEBUG] Individual check for like status of ruck $ruckId');
      final endpoint = '${AppConfig.apiBaseUrl}/ruck-likes/check?ruck_id=$ruckId';
      final response = await _httpClient.get(
        Uri.parse(endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 5));
      
      debugPrint('[SOCIAL_DEBUG] API response status code: ${response.statusCode}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['success'] == true) {
          final bool hasLiked;
          // Handle different API response formats
          if (data['data'] is Map) {
            hasLiked = data['data']['has_liked'] == true || data['data']['has_liked'] == 'true' || data['data']['has_liked'] == 1;
          } else {
            hasLiked = data['data'] == true || data['data'] == 'true' || data['data'] == 1;
          }
          debugPrint('[SOCIAL_DEBUG] User has liked ruck $ruckId: $hasLiked');
          return hasLiked;
        }
        return false;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw UnauthorizedException(message: 'Unauthorized request');
      } else if (response.statusCode == 429) {
        debugPrint('[SOCIAL_DEBUG] Rate limit hit for ruck $ruckId: ${response.statusCode}');
        return null; // Return null on rate limit to allow retry later
      } else {
        throw ServerException(
            message: 'Failed to check like status: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('[SOCIAL_DEBUG] Error in _fallbackSingleRuckCheck: $e');
      return null; // Return null on error
    }
  }

  /// Fallback method for checking a single ruck like count
  /// Returns the like count for the ruck, or null on error
  Future<int?> _fallbackSingleRuckLikeCount(int ruckId, String token) async {
    try {
      final url = '${AppConfig.apiBaseUrl}/ruck-likes?ruck_id=$ruckId';
      debugPrint('[SOCIAL_DEBUG] Individual check for like count of ruck $ruckId, URL: $url');
      
      final response = await _httpClient.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 5));

      debugPrint('[SOCIAL_DEBUG] Like count API response for ruck $ruckId: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        // Log the full response for debugging
        debugPrint('[SOCIAL_DEBUG] Like count response body: ${response.body}');
        
        final Map<String, dynamic> data = json.decode(response.body);
        debugPrint('[SOCIAL_DEBUG] Like count data format check - success: ${data['success']}, data type: ${data['data']?.runtimeType}');
        
        if (data['success'] == true && data['data'] is List) {
          final count = (data['data'] as List).length;
          debugPrint('[SOCIAL_DEBUG] Like count for ruck $ruckId: $count');
          return count;
        } else {
          debugPrint('[SOCIAL_DEBUG] Invalid data format in like count response for ruck $ruckId');
        }
        return 0;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        debugPrint('[SOCIAL_DEBUG] Unauthorized request for like count of ruck $ruckId');
        throw UnauthorizedException(message: 'Unauthorized request');
      } else if (response.statusCode == 429) {
        debugPrint('[SOCIAL_DEBUG] Rate limit hit for like count of ruck $ruckId: ${response.statusCode}');
        return null; // Return null on rate limit
      } else {
        debugPrint('[SOCIAL_DEBUG] Server error for like count of ruck $ruckId: ${response.statusCode} - ${response.body}');
        throw ServerException(
            message: 'Failed to get like count: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('[SOCIAL_DEBUG] Error in _fallbackSingleRuckLikeCount for ruck $ruckId: $e');
      return null; // Return null on error
    }
  }

  /// Get comments for a specific ruck session
  Future<List<RuckComment>> getRuckComments(String ruckId) async {
    try {
      final token = await _authToken;
      if (token == null) {
        throw UnauthorizedException(message: 'User is not authenticated');
      }

      // Use the existing endpoint structure
      final endpoint = '${AppConfig.apiBaseUrl}/ruck-comments?ruck_id=$ruckId';
      debugPrint('[SOCIAL_DEBUG] Getting comments for ruckId $ruckId, endpoint: $endpoint');

      final response = await _httpClient.get(
        Uri.parse(endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      
      debugPrint('[SOCIAL_DEBUG] Comments API response: ${response.statusCode}');
      if (response.statusCode != 200) {
        debugPrint('[SOCIAL_DEBUG] Failed response body: ${response.body}');
      }

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
  Future<RuckComment> addRuckComment(String ruckId, String content) async {
    try {
      final token = await _authToken;
      if (token == null) {
        throw UnauthorizedException(message: 'User is not authenticated');
      }

      debugPrint('[SOCIAL_DEBUG] Adding comment to ruck $ruckId with content: $content');
      
      // Parse the ruck ID to an integer if possible
      int? ruckIdInt;
      try {
        ruckIdInt = int.parse(ruckId);
      } catch (e) {
        debugPrint('[SOCIAL_DEBUG] Could not parse ruckId to int: $e');
      }
      
      // Don't include /api in the path as it's already in the base URL
      // Use the correct endpoint format: /rucks/{id}/comments
      final endpoint = '${AppConfig.apiBaseUrl}/rucks/${ruckIdInt ?? ruckId}/comments';
      debugPrint('[SOCIAL_DEBUG] Comment endpoint: $endpoint');
      
      // Only send the content in the payload, not the ruck_id (as it's in the URL path)
      final payload = {
        'content': content,
      };
      debugPrint('[SOCIAL_DEBUG] Comment payload: ${json.encode(payload)}');
      
      final response = await _httpClient.post(
        Uri.parse(endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode(payload),
      );
      
      debugPrint('[SOCIAL_DEBUG] Comment API response: ${response.statusCode} - ${response.body}');

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

      debugPrint('[SOCIAL_DEBUG] Updating comment $commentId with content: $content');
      
      // To update a comment, we need to know which ruck it belongs to
      // We'll need to extract the ruck ID from the comment ID format (if possible)
      // For now, let's use the PUT method on the specific comment endpoint
      
      // Try to parse the comment ID as an integer if possible
      int? commentIdInt;
      try {
        commentIdInt = int.parse(commentId);
      } catch (e) {
        debugPrint('[SOCIAL_DEBUG] Could not parse commentId to int: $e');
      }
      
      // Since the correct endpoint would be /rucks/{ruck_id}/comments/{comment_id}
      // but we don't have the ruck_id here, we'll use the API's ability to 
      // identify comments directly by ID
      final response = await _httpClient.put(
        Uri.parse('${AppConfig.apiBaseUrl}/comments/${commentIdInt ?? commentId}'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'content': content,
        }),
      );
      
      debugPrint('[SOCIAL_DEBUG] Update comment API response: ${response.statusCode} - ${response.body}');

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

      debugPrint('[SOCIAL_DEBUG] Deleting comment $commentId');
      
      // Try to parse the comment ID as an integer if possible
      int? commentIdInt;
      try {
        commentIdInt = int.parse(commentId);
      } catch (e) {
        debugPrint('[SOCIAL_DEBUG] Could not parse commentId to int: $e');
      }
      
      // The correct endpoint format is /comments/{id} for direct comment management
      // without knowing the ruck_id
      final commentParam = commentIdInt != null ? commentIdInt.toString() : commentId;
      
      // Use the DELETE method on the specific comment endpoint
      final response = await _httpClient.delete(
        Uri.parse('${AppConfig.apiBaseUrl}/comments/$commentParam'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      
      debugPrint('[SOCIAL_DEBUG] Delete comment API response: ${response.statusCode} - ${response.body}');

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
