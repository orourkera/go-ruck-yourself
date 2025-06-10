import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'dart:async';

/// Custom cache manager for images with longer cache duration and advanced features
class ImageCacheManager {
  static const String _mainKey = 'main_image_cache';
  static const String _profileKey = 'profile_image_cache';
  static const String _photoKey = 'session_photo_cache';
  
  /// Main cache manager with extended duration for better user experience
  static CacheManager get instance => CacheManager(
    Config(
      _mainKey,
      // Cache for 30 days instead of default 7 days
      stalePeriod: const Duration(days: 30),
      // Keep maximum 500 cached images (default is 200)
      maxNrOfCacheObjects: 500,
    ),
  );

  /// Specialized cache for profile pictures with longer retention
  static CacheManager get profileCache => CacheManager(
    Config(
      _profileKey,
      // Profile pics cached for 60 days (they change less frequently)
      stalePeriod: const Duration(days: 60),
      // Smaller cache for avatars - 100 items
      maxNrOfCacheObjects: 100,
    ),
  );

  /// High-retention cache for session photos
  static CacheManager get photoCache => CacheManager(
    Config(
      _photoKey,
      // Session photos cached for 14 days
      stalePeriod: const Duration(days: 14),
      // Larger cache for session photos - 1000 items
      maxNrOfCacheObjects: 1000,
    ),
  );

  /// Preload a list of image URLs for better perceived performance
  static Future<void> preloadImages(
    List<String> imageUrls, {
    CacheManager? cacheManager,
    int maxConcurrent = 3,
  }) async {
    if (imageUrls.isEmpty) return;

    final manager = cacheManager ?? instance;
    final semaphore = Semaphore(maxConcurrent);
    
    try {
      await Future.wait(
        imageUrls.map((url) async {
          await semaphore.acquire();
          try {
            await manager.downloadFile(url);
          } catch (e) {
            // Silently handle preload failures
            debugPrint('Preload failed for $url: $e');
          } finally {
            semaphore.release();
          }
        }),
      );
    } catch (e) {
      debugPrint('Batch preload error: $e');
    }
  }

  /// Preload profile pictures specifically
  static Future<void> preloadProfilePictures(List<String> avatarUrls) async {
    await preloadImages(avatarUrls, cacheManager: profileCache);
  }

  /// Preload session photos specifically  
  static Future<void> preloadSessionPhotos(List<String> photoUrls) async {
    await preloadImages(photoUrls, cacheManager: photoCache, maxConcurrent: 2);
  }

  /// Clear all image caches
  static Future<void> clearAllCaches() async {
    await Future.wait([
      instance.emptyCache(),
      profileCache.emptyCache(), 
      photoCache.emptyCache(),
    ]);
  }

  /// Clear only profile picture cache
  static Future<void> clearProfileCache() async {
    await profileCache.emptyCache();
  }

  /// Clear only session photo cache
  static Future<void> clearPhotoCache() async {
    await photoCache.emptyCache();
  }

  /// Get cache statistics for debugging
  static Future<Map<String, dynamic>> getCacheStats() async {
    try {
      return {
        'main_cache': 'Cache statistics not available',
        'profile_cache': 'Cache statistics not available', 
        'photo_cache': 'Cache statistics not available',
        'message': 'Cache managers are configured and operational'
      };
    } catch (e) {
      return {
        'error': 'Failed to get cache stats: $e',
      };
    }
  }

  /// Get optimized cache key for URLs
  static String getCacheKey(String url) {
    // Extract meaningful part of URL for stable caching
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    
    // Use path segments for stable keys
    final segments = uri.pathSegments;
    return segments.isNotEmpty ? segments.last : url;
  }
}

/// Simple semaphore for controlling concurrent operations
class Semaphore {
  final int maxCount;
  int _currentCount;
  final List<Completer<void>> _waitQueue = [];

  Semaphore(this.maxCount) : _currentCount = maxCount;

  Future<void> acquire() async {
    if (_currentCount > 0) {
      _currentCount--;
      return;
    }
    
    final completer = Completer<void>();
    _waitQueue.add(completer);
    return completer.future;
  }

  void release() {
    if (_waitQueue.isNotEmpty) {
      final completer = _waitQueue.removeAt(0);
      completer.complete();
    } else {
      _currentCount++;
    }
  }
}
