import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:rucking_app/core/services/auth_service.dart';
import 'package:rucking_app/core/services/app_error_handler.dart';
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
  
  // Cache expiration in seconds - increased to 5 minutes for better performance
  static const int _cacheExpirationSeconds = 300; // 5 minutes cache
  
  // Getters for cached data - these provide immediate access to cached values without network calls
  bool? getCachedLikeStatus(int ruckId) => _likeStatusCache[ruckId];
  int? getCachedLikeCount(int ruckId) => _likeCountCache[ruckId];
  List<RuckComment>? getCachedComments(String ruckId) => _commentsCache[ruckId];

  /// Clear cached comments for a specific ruck to force refresh
  void clearCommentsCache(String ruckId) {
    _commentsCache.remove(ruckId);
  }

  /// Clear all comments cache
  void clearAllCommentsCache() {
    _commentsCache.clear();
  }

  /// Clear all cached data for a specific ruck
  void clearRuckCache(String ruckId) {
    final ruckIdInt = int.tryParse(ruckId);
    if (ruckIdInt != null) {
      _likeStatusCache.remove(ruckIdInt);
      _likeCountCache.remove(ruckIdInt);
    }
    _commentsCache.remove(ruckId);
  }

  /// Update cache with initial values from UI to ensure consistency
  void updateCacheWithInitialValues(int ruckId, bool isLiked, int likeCount) {
    _likeStatusCache[ruckId] = isLiked;
    _likeCountCache[ruckId] = likeCount;
    _likeCacheTimestamps[ruckId] = DateTime.now();
  }

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
      } else if (response.statusCode == 404) {
        clearRuckCache(ruckId.toString());
        return []; // Return empty list for 404
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
    try {
      final token = await _authToken;
      if (token == null) {
        throw UnauthorizedException(message: 'User is not authenticated');
      }

      final endpoint = '${AppConfig.apiBaseUrl}/ruck-likes';
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

      if (response.statusCode == 200 || response.statusCode == 201) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          // Update cache to set liked=true and increment like count
          _likeStatusCache[ruckId] = true;
          _likeCountCache[ruckId] = (_likeCountCache[ruckId] ?? 0) + 1;
          _likeCacheTimestamps[ruckId] = DateTime.now();
          return RuckLike.fromJson(data['data']);
        } else {
          throw ServerException(message: 'Invalid response: ${response.body}');
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw UnauthorizedException(message: 'Unauthorized request');
      } else if (response.statusCode == 404) {
        clearRuckCache(ruckId.toString());
        throw ServerException(message: 'Ruck session not found');
      } else {
        throw ServerException(
            message: 'Failed to add like: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      if (e is UnauthorizedException) rethrow;
      
      // Enhanced error handling with Sentry - wrapped to prevent secondary errors
      try {
        await AppErrorHandler.handleError(
          'social_add_like',
          e,
          context: {
            'ruck_id': ruckId,
            'operation': 'add_like',
          },
          userId: (await _authService.getCurrentUser())?.userId,
          sendToBackend: true,
        );
      } catch (errorHandlerException) {
        // If error reporting fails, log it but don't crash the app
        print('Error reporting failed during social add like: $errorHandlerException');
      }
      
      throw ServerException(message: 'Failed to add like: $e');
    }
  }

  /// Remove a like from a ruck session
  /// Updates the cache with the new unlike status
  Future<bool> removeRuckLike(int ruckId) async {
    try {
      final token = await _authToken;
      if (token == null) {
        throw UnauthorizedException(message: 'User is not authenticated');
      }

      final endpoint = '${AppConfig.apiBaseUrl}/ruck-likes?ruck_id=$ruckId';
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
        }
        
        return success;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw UnauthorizedException(message: 'Unauthorized request');
      } else if (response.statusCode == 404) {
        clearRuckCache(ruckId.toString());
        return true; // Return true since like already doesn't exist
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
    // Check cache first if it's valid
    if (_isValidCache(ruckId)) {
      return _likeStatusCache[ruckId] ?? false;
    }

    final token = await _authToken;
    if (token == null) {
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
      final endpoint = '${AppConfig.apiBaseUrl}/ruck-likes/check?ruck_id=$ruckId';
      final response = await _httpClient.get(
        Uri.parse(endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 5));
      
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
          return hasLiked;
        }
        return false;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw UnauthorizedException(message: 'Unauthorized request');
      } else if (response.statusCode == 429) {
        return null; // Return null on rate limit to allow retry later
      } else if (response.statusCode == 404) {
        clearRuckCache(ruckId.toString());
      } else {
        throw ServerException(
            message: 'Failed to check like status: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      return null; // Return null on error
    }
  }

  /// Fallback method for checking a single ruck like count
  /// Returns the like count for the ruck, or null on error
  Future<int?> _fallbackSingleRuckLikeCount(int ruckId, String token) async {
    try {
      final url = '${AppConfig.apiBaseUrl}/ruck-likes?ruck_id=$ruckId';
      
      final response = await _httpClient.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        
        if (data['success'] == true && data['data'] is List) {
          final count = (data['data'] as List).length;
          return count;
        } else {
          return 0;
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw UnauthorizedException(message: 'Unauthorized request');
      } else if (response.statusCode == 429) {
        return null; // Return null on rate limit
      } else if (response.statusCode == 404) {
        clearRuckCache(ruckId.toString());
      } else {
        throw ServerException(
            message: 'Failed to get like count: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
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

      final endpoint = '${AppConfig.apiBaseUrl}/rucks/$ruckId/comments';
      final response = await _httpClient.get(
        Uri.parse(endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final commentsList = (data['data'] as List)
              .map((json) => RuckComment.fromJson(json))
              .toList();
        
          // Deduplicate comments by ID to prevent sync issues
          final deduplicatedComments = <String, RuckComment>{};
          for (final comment in commentsList) {
            deduplicatedComments[comment.id] = comment;
          }
        
          // Sort by creation date (newest first)
          final sortedComments = deduplicatedComments.values.toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        
          return sortedComments;
        } else {
          return [];
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw UnauthorizedException(message: 'Unauthorized request');
      } else if (response.statusCode == 404) {
        clearCommentsCache(ruckId);
        return []; // Return empty list for 404
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

      final endpoint = '${AppConfig.apiBaseUrl}/rucks/$ruckId/comments';
      
      final payload = {
        'content': content,
      };
      
      final response = await _httpClient.post(
        Uri.parse(endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode(payload),
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
      } else if (response.statusCode == 404) {
        clearCommentsCache(ruckId);
        throw ServerException(message: 'Ruck session not found');
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
        Uri.parse('${AppConfig.apiBaseUrl}/comments/${commentId}'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
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
      } else if (response.statusCode == 404) {
        clearAllCommentsCache();
        throw ServerException(message: 'Comment not found');
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
  Future<bool> deleteRuckComment(String ruckId, String commentId) async {
    try {
      final token = await _authToken;
      if (token == null) {
        throw UnauthorizedException(message: 'User is not authenticated');
      }

      debugPrint('[COMMENT DELETE] Attempting to delete comment: $commentId for ruck: $ruckId');
      
      // Use the correct backend endpoint format: DELETE /rucks/{ruck_id}/comments?comment_id={comment_id}
      final correctUrl = '${AppConfig.apiBaseUrl}/rucks/$ruckId/comments?comment_id=$commentId';
      debugPrint('[COMMENT DELETE] Using correct API URL: $correctUrl');

      final response = await _httpClient.delete(
        Uri.parse(correctUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      
      debugPrint('[COMMENT DELETE] Response status: ${response.statusCode}');
      debugPrint('[COMMENT DELETE] Response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        final success = data['success'] == true;
        debugPrint('[COMMENT DELETE] Deletion successful: $success');
        return success;
      } else if (response.statusCode == 404) {
        // Comment already doesn't exist, treat as successful deletion
        debugPrint('[COMMENT DELETE] Comment not found (404), treating as successful deletion');
        clearAllCommentsCache();
        return true;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw UnauthorizedException(message: 'Unauthorized request');
      } else {
        throw ServerException(
            message: 'Failed to delete comment: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('[COMMENT DELETE] Error: $e');
      if (e is UnauthorizedException) rethrow;
      throw ServerException(message: 'Failed to delete comment: $e');
    }
  }

  /// Batch preload social data for multiple rucks to improve performance
  /// This method loads likes and comments for multiple rucks in a single API call
  Future<void> preloadSocialDataForRucks(List<int> ruckIds) async {
    if (ruckIds.isEmpty) return;
    
    try {
      final token = await _authToken;
      if (token == null) return;
      
      // Filter out rucks that already have fresh cache
      final now = DateTime.now();
      final rucksToFetch = ruckIds.where((ruckId) {
        final timestamp = _likeCacheTimestamps[ruckId];
        return timestamp == null || 
               now.difference(timestamp).inSeconds > _cacheExpirationSeconds;
      }).toList();
      
      if (rucksToFetch.isEmpty) return;
      
      final ruckIdsParam = rucksToFetch.join(',');
      final response = await _httpClient.get(
        Uri.parse('${AppConfig.apiBaseUrl}/ruck-likes/batch?ruck_ids=$ruckIdsParam'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final batchData = data['data'] as Map<String, dynamic>;
          
          // Update cache with batch results
          for (final ruckId in rucksToFetch) {
            final ruckIdStr = ruckId.toString();
            if (batchData.containsKey(ruckIdStr)) {
              final ruckData = batchData[ruckIdStr];
              _likeStatusCache[ruckId] = ruckData['user_has_liked'] ?? false;
              _likeCountCache[ruckId] = ruckData['like_count'] ?? 0;
              _likeCacheTimestamps[ruckId] = now;
            }
          }
        }
      } else {
        // Fall back to individual requests for critical data
        _fallbackIndividualRequests(rucksToFetch.take(3).toList()); // Limit fallback
      }
    } catch (e) {
      // Fail silently - cached data will be used or individual requests will be made as needed
    }
  }
  
  /// Fallback method for individual social data requests when batch fails
  Future<void> _fallbackIndividualRequests(List<int> ruckIds) async {
    final token = await _authToken;
    if (token == null) return;
    
    for (final ruckId in ruckIds) {
      try {
        // Quick check for like status without full error handling
        final likeStatus = await _fallbackSingleRuckCheck(ruckId, token);
        if (likeStatus != null) {
          _likeStatusCache[ruckId] = likeStatus;
          _likeCacheTimestamps[ruckId] = DateTime.now();
        }
        
        // Quick check for like count
        final likeCount = await _fallbackSingleRuckLikeCount(ruckId, token);
        if (likeCount != null) {
          _likeCountCache[ruckId] = likeCount;
        }
      } catch (e) {
        // Ignore individual failures during fallback
      }
    }
  }
}
