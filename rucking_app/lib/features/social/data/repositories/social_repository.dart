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
  
  // Cache for like status to prevent repeated API calls
  final Map<int, bool> _likeStatusCache = {};
  final Map<int, int> _likeCountCache = {};
  final Map<int, DateTime> _likeCacheTimestamps = {};
  
  // Cache expiration in seconds
  static const int _cacheExpirationSeconds = 60; // 1 minute cache

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
  /// Uses caching to reduce API calls
  Future<bool> hasUserLikedRuck(int ruckId) async {
    debugPrint('[SOCIAL_DEBUG] hasUserLikedRuck called for ruckId: $ruckId');
    
    // Check cache first if it's valid
    if (_isValidCache(ruckId)) {
      debugPrint('[SOCIAL_DEBUG] Using cached like status for ruckId: $ruckId');
      return _likeStatusCache[ruckId] ?? false;
    }
    
    final result = await batchCheckUserLikes([ruckId]);
    
    // Handle potential null with proper null safety
    final likeStatusMap = result['likeStatus'];
    if (likeStatusMap == null) return false;
    
    return likeStatusMap[ruckId] ?? false;
  }
  
  /// Checks if cache for a ruckId is still valid
  bool _isValidCache(int ruckId) {
    if (!_likeCacheTimestamps.containsKey(ruckId)) return false;
    
    final timestamp = _likeCacheTimestamps[ruckId]!;
    final now = DateTime.now();
    final difference = now.difference(timestamp).inSeconds;
    
    return difference < _cacheExpirationSeconds && _likeStatusCache.containsKey(ruckId);
  }
  
  /// Batch check if the current user has liked multiple ruck sessions
  /// Returns a map with 'likeStatus' containing ruckId -> hasLiked mapping
  /// and 'likeCounts' containing ruckId -> count mapping
  /// 
  /// OPTIMIZED: Uses a single API call for all ruckIds instead of individual requests
  /// and implements caching to avoid hitting rate limits
  Future<Map<String, Map<int, dynamic>>> batchCheckUserLikes(List<int> ruckIds) async {
    if (ruckIds.isEmpty) return {
      'likeStatus': {},
      'likeCounts': {},
    };
    
    debugPrint('[SOCIAL_DEBUG] batchCheckUserLikes called for ${ruckIds.length} rucks');
    final now = DateTime.now();
    
    // Split ruckIds into cached and uncached lists
    List<int> uncachedRuckIds = [];
    Map<int, bool> likeStatusMap = {};
    Map<int, int> likeCountMap = {};
    
    // Add cached values first
    for (final ruckId in ruckIds) {
      if (_isValidCache(ruckId)) {
        // Use cached values for this ruck
        likeStatusMap[ruckId] = _likeStatusCache[ruckId]!;
        likeCountMap[ruckId] = _likeCountCache[ruckId] ?? 0;
        debugPrint('[SOCIAL_DEBUG] Using cached data for ruckId: $ruckId, liked: ${likeStatusMap[ruckId]}, count: ${likeCountMap[ruckId]}');
      } else {
        // Need to fetch this ruck
        uncachedRuckIds.add(ruckId);
      }
    }
    
    // If all rucks were in cache, return immediately
    if (uncachedRuckIds.isEmpty) {
      debugPrint('[SOCIAL_DEBUG] All ${ruckIds.length} rucks were cached, no API call needed');
      return {
        'likeStatus': likeStatusMap,
        'likeCounts': likeCountMap,
      };
    }
    
    // Need to fetch uncached rucks
    debugPrint('[SOCIAL_DEBUG] Fetching ${uncachedRuckIds.length} uncached rucks');
    
    try {
      final token = await _authToken;
      if (token == null) {
        throw UnauthorizedException(message: 'User is not authenticated');
      }
      
      // Create one comma-separated list of uncached ruckIds
      final ruckIdsStr = uncachedRuckIds.join(',');
      
      try {
        // First check batch like status (if user liked these rucks)
        final batchLikeStatusUrl = '${AppConfig.apiBaseUrl}/ruck-likes/check/batch?ids=$ruckIdsStr';
        debugPrint('[SOCIAL_DEBUG] Batch like status URL: $batchLikeStatusUrl');
        
        // Attempt to get like status from batch endpoint
        final batchLikeStatusResponse = await _httpClient.get(
          Uri.parse(batchLikeStatusUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        ).timeout(const Duration(seconds: 10)); // Slightly longer timeout for batch request
        
        // First try the batch endpoint
        if (batchLikeStatusResponse.statusCode == 200) {
          debugPrint('[SOCIAL_DEBUG] Batch like status response: ${batchLikeStatusResponse.body}');
          final Map<String, dynamic> data = json.decode(batchLikeStatusResponse.body);
          if (data['success'] == true && data['data'] is Map) {
            final Map<String, dynamic> likesData = data['data'] as Map<String, dynamic>;
            
            debugPrint('[SOCIAL_DEBUG] Raw like status data: $likesData');
            
            // Convert string keys to int keys
            likesData.forEach((key, value) {
              // Convert key to int
              final intKey = int.tryParse(key);
              if (intKey != null) {
                // Ensure proper boolean conversion of value, which could be in different formats
                final isLiked = value == true || value == 'true' || value == 1;
                likeStatusMap[intKey] = isLiked;
                
                debugPrint('[SOCIAL_DEBUG] Processed like status for ruck $intKey: isLiked=$isLiked (original value type: ${value.runtimeType}, value: $value)');
                
                // Update cache
                _likeStatusCache[intKey] = isLiked;
                _likeCacheTimestamps[intKey] = now;
              }
            });
            
            debugPrint('[SOCIAL_DEBUG] Successfully processed batch like status for ${likesData.length} rucks');
          } else {
            debugPrint('[SOCIAL_DEBUG] Invalid data format in batch like status response: success=${data['success']}, data type=${data['data']?.runtimeType}');
          }
        } else {
          // Fall back to individual like status checks (legacy approach)
          await _fallbackBatchLikeStatusCheck(uncachedRuckIds, likeStatusMap, token);
          
          // Update cache for individual checks too
          for (final ruckId in uncachedRuckIds) {
            if (likeStatusMap.containsKey(ruckId)) {
              _likeStatusCache[ruckId] = likeStatusMap[ruckId]!;
              _likeCacheTimestamps[ruckId] = now;
            }
          }
        }
        
        // The batch endpoint for counts doesn't exist in the backend yet
        // Skip trying to use it and directly use the fallback method
        debugPrint('[SOCIAL_DEBUG] Skipping non-existent batch count endpoint and using fallback method');
        await _fallbackBatchLikeCountCheck(uncachedRuckIds, likeCountMap, token);
      } catch (e) {
        debugPrint('[SOCIAL_DEBUG] Error during batch API calls: $e. Falling back for both status and count.');
        // Fallback for status if not already populated
        List<int> statusFallbackNeeded = uncachedRuckIds.where((id) => !likeStatusMap.containsKey(id)).toList();
        if (statusFallbackNeeded.isNotEmpty) {
           await _fallbackBatchLikeStatusCheck(statusFallbackNeeded, likeStatusMap, token);
        }
        // Fallback for counts if not already populated
        List<int> countFallbackNeeded = uncachedRuckIds.where((id) => !likeCountMap.containsKey(id)).toList();
        if (countFallbackNeeded.isNotEmpty) {
          await _fallbackBatchLikeCountCheck(countFallbackNeeded, likeCountMap, token);
        }
      }

      // Update cache timestamps for all processed uncached items
      for (final ruckId in uncachedRuckIds) {
        if (likeStatusMap.containsKey(ruckId) || likeCountMap.containsKey(ruckId)) {
           _likeCacheTimestamps[ruckId] = now;
        }
      }
      
      debugPrint('[SOCIAL_DEBUG] Returning like status for ${likeStatusMap.length} rucks and like counts for ${likeCountMap.length} rucks');
      return {
        'likeStatus': likeStatusMap,
        'likeCounts': likeCountMap,
      };
    } catch (e) {
      debugPrint('[SOCIAL_DEBUG] Outer error in batchCheckUserLikes: $e');
      // In case of a broader error (e.g., token issue), return empty maps or rethrow
      return {
        'likeStatus': likeStatusMap, // Potentially partially filled from cache
        'likeCounts': likeCountMap,   // Potentially partially filled from cache
      };
    }
  }
  
  /// Fallback method to check individual like status when batch fails
  /// Uses an adaptive approach to avoid rate limiting
  Future<void> _fallbackBatchLikeStatusCheck(List<int> ruckIds, Map<int, bool> likeStatusMap, String token) async {
    debugPrint('[SOCIAL_DEBUG] Falling back to individual like status checks for ${ruckIds.length} rucks');
    
    // Get current timestamp to update cache
    final now = DateTime.now();
    
    // Use a much smaller batch size to avoid rate limits
    final batchSize = 1; // Process one at a time to minimize rate limit issues
    
    // Check which ruckIds are already in cache to reduce API calls
    final List<int> uncachedRuckIds = [];
    for (final ruckId in ruckIds) {
      // Check if we already have a valid cache entry
      if (_isValidCache(ruckId)) {
        likeStatusMap[ruckId] = _likeStatusCache[ruckId]!;
        debugPrint('[SOCIAL_DEBUG] Using cached like status for ruck $ruckId: ${_likeStatusCache[ruckId]}');
      } else {
        uncachedRuckIds.add(ruckId);
      }
    }
    
    if (uncachedRuckIds.isEmpty) {
      debugPrint('[SOCIAL_DEBUG] All like statuses were in cache, no need for fallback API calls');
      return;
    }
    
    debugPrint('[SOCIAL_DEBUG] Need to fetch ${uncachedRuckIds.length} uncached ruck statuses');
    
    // Process in tiny batches with increasing delays between requests
    int consecutiveErrors = 0;
    int baseDelay = 500; // Start with 500ms delay
    
    for (var i = 0; i < uncachedRuckIds.length; i += batchSize) {
      final end = (i + batchSize < uncachedRuckIds.length) ? i + batchSize : uncachedRuckIds.length;
      final batch = uncachedRuckIds.sublist(i, end);
      
      for (final ruckId in batch) {
        try {
          // Calculate delay with exponential backoff if we've had errors
          final currentDelay = consecutiveErrors > 0 ? 
              baseDelay * (1 << (consecutiveErrors - 1)) : // Exponential backoff
              baseDelay;
              
          // Apply delay before request to avoid rate limits
          if (i > 0 || consecutiveErrors > 0) {
            debugPrint('[SOCIAL_DEBUG] Waiting ${currentDelay}ms before checking ruck $ruckId');
            await Future.delayed(Duration(milliseconds: currentDelay));
          }
          
          final result = await _fallbackSingleRuckCheck(ruckId, token);
          if (result != null) {
            likeStatusMap[ruckId] = result;
            _likeStatusCache[ruckId] = result;
            _likeCacheTimestamps[ruckId] = now;
            consecutiveErrors = 0; // Reset error counter on success
          }
        } catch (e) {
          debugPrint('[SOCIAL_DEBUG] Error checking like status for ruck $ruckId: $e');
          consecutiveErrors++; // Increment error counter
          
          // Default to false on error to avoid showing incorrect UI
          // This will be updated when the rate limit window expires
          likeStatusMap[ruckId] = false;
          
          // If we hit 3 consecutive errors, stop to avoid wasting resources
          if (consecutiveErrors >= 3) {
            debugPrint('[SOCIAL_DEBUG] Too many consecutive errors (${consecutiveErrors}), aborting remaining checks');
            return;
          }
        }
      }
    }
  }
  
  /// Fallback method to check individual like counts when batch fails
  /// Uses an adaptive approach to avoid rate limiting
  Future<void> _fallbackBatchLikeCountCheck(List<int> ruckIds, Map<int, int> likeCountMap, String token) async {
    debugPrint('[SOCIAL_DEBUG] Falling back to individual like count checks for ${ruckIds.length} rucks');
    
    // Get current timestamp to update cache
    final now = DateTime.now();
    
    // Use a much smaller batch size to avoid rate limits
    final batchSize = 1; // Process one at a time to minimize rate limit issues
    
    // Check which ruckIds are already in cache to reduce API calls
    final List<int> uncachedRuckIds = [];
    for (final ruckId in ruckIds) {
      // Check if we already have a valid cache entry for the count
      if (_isValidCache(ruckId) && _likeCountCache.containsKey(ruckId)) {
        likeCountMap[ruckId] = _likeCountCache[ruckId]!;
        debugPrint('[SOCIAL_DEBUG] Using cached like count for ruck $ruckId: ${_likeCountCache[ruckId]}');
      } else {
        uncachedRuckIds.add(ruckId);
      }
    }
    
    if (uncachedRuckIds.isEmpty) {
      debugPrint('[SOCIAL_DEBUG] All like counts were in cache, no need for fallback API calls');
      return;
    }
    
    debugPrint('[SOCIAL_DEBUG] Need to fetch ${uncachedRuckIds.length} uncached ruck counts');
    
    // Process in tiny batches with increasing delays between requests
    int consecutiveErrors = 0;
    int baseDelay = 500; // Start with 500ms delay
    
    for (var i = 0; i < uncachedRuckIds.length; i += batchSize) {
      final end = (i + batchSize < uncachedRuckIds.length) ? i + batchSize : uncachedRuckIds.length;
      final batch = uncachedRuckIds.sublist(i, end);
      
      for (final ruckId in batch) {
        try {
          // Calculate delay with exponential backoff if we've had errors
          final currentDelay = consecutiveErrors > 0 ? 
              baseDelay * (1 << (consecutiveErrors - 1)) : // Exponential backoff
              baseDelay;
              
          // Apply delay before request to avoid rate limits
          if (i > 0 || consecutiveErrors > 0) {
            debugPrint('[SOCIAL_DEBUG] Waiting ${currentDelay}ms before checking like count for ruck $ruckId');
            await Future.delayed(Duration(milliseconds: currentDelay));
          }
          
          final count = await _fallbackSingleRuckLikeCount(ruckId, token);
          if (count != null) {
            likeCountMap[ruckId] = count;
            _likeCountCache[ruckId] = count;
            _likeCacheTimestamps[ruckId] = now;
            consecutiveErrors = 0; // Reset error counter on success
          }
        } catch (e) {
          debugPrint('[SOCIAL_DEBUG] Error checking like count for ruck $ruckId: $e');
          consecutiveErrors++; // Increment error counter
          
          // Default to 0 on error to avoid showing incorrect UI
          // This will be updated when the rate limit window expires
          likeCountMap[ruckId] = 0;
          
          // If we hit 3 consecutive errors, stop to avoid wasting resources
          if (consecutiveErrors >= 3) {
            debugPrint('[SOCIAL_DEBUG] Too many consecutive errors (${consecutiveErrors}), aborting remaining like count checks');
            return;
          }
        }
      }
    }
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
      debugPrint('[SOCIAL_DEBUG] Individual check for like count of ruck $ruckId');
      final response = await _httpClient.get(
        Uri.parse('${AppConfig.apiBaseUrl}/ruck-likes?ruck_id=$ruckId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['success'] == true && data['data'] is List) {
          final count = (data['data'] as List).length;
          debugPrint('[SOCIAL_DEBUG] Like count for ruck $ruckId: $count');
          return count;
        }
        return 0;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw UnauthorizedException(message: 'Unauthorized request');
      } else if (response.statusCode == 429) {
        debugPrint('[SOCIAL_DEBUG] Rate limit hit for ruck $ruckId: ${response.statusCode}');
        return null; // Return null on rate limit
      } else {
        throw ServerException(
            message: 'Failed to get like count: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('[SOCIAL_DEBUG] Error in _fallbackSingleRuckLikeCount: $e');
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

      // Revert to the original endpoint structure
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

      // Use the original endpoint structure with proper URL formatting
      final endpoint = '${AppConfig.apiBaseUrl}/ruck-comments';
      debugPrint('[SOCIAL_DEBUG] Adding comment for ruckId $ruckId, endpoint: $endpoint');
      
      // Include ruck_id in the payload as the original implementation did
      final payload = {
        'ruck_id': ruckId,
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
