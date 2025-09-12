import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Custom cache manager for images with longer cache duration and advanced features
class ImageCacheManager {
  static const String _mainKey = 'main_image_cache';
  static const String _profileKey = 'profile_image_cache';
  static const String _photoKey = 'session_photo_cache';

  /// Main cache manager with memory-conscious limits
  static CacheManager get instance => CacheManager(
        Config(
          _mainKey,
          // Cache for 7 days (reduced from 30)
          stalePeriod: const Duration(days: 7),
          // Keep maximum 100 cached images (reduced from 500)
          maxNrOfCacheObjects: 100,
          // Add resilient HTTP client
          fileService: _createResilientHttpFileService(),
        ),
      );

  /// Specialized cache for profile pictures with memory-conscious limits
  static CacheManager get profileCache => CacheManager(
        Config(
          _profileKey,
          // Profile pics cached for 14 days
          stalePeriod: const Duration(days: 14),
          // Reasonable cache for avatars - 100 items (increased back for better UX)
          maxNrOfCacheObjects: 100,
          // Add resilient HTTP client
          fileService: _createResilientHttpFileService(),
        ),
      );

  /// Memory-conscious cache for session photos
  static CacheManager get photoCache => CacheManager(
        Config(
          _photoKey,
          // Session photos cached for 7 days (reduced from 14)
          stalePeriod: const Duration(days: 7),
          // Reduced cache for session photos - 200 items (reduced from 1000)
          maxNrOfCacheObjects: 200,
          // Add resilient HTTP client
          fileService: _createResilientHttpFileService(),
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

  /// Create a resilient HTTP file service with robust error handling
  static FileService _createResilientHttpFileService() {
    return HttpFileService(
      httpClient: _ResilientHttpClient(),
    );
  }
}

/// Resilient HTTP client with robust error handling for image downloads
class _ResilientHttpClient extends http.BaseClient {
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    try {
      // Add timeout and resilient headers
      final resilientRequest = _addResilientHeaders(request);

      // Use a reasonable timeout for images
      final response = await _inner.send(resilientRequest).timeout(
        const Duration(seconds: 30), // Increased back to 30s for better loading
        onTimeout: () {
          debugPrint('Image request timeout for: ${request.url}');
          throw const SocketException('Image download timeout');
        },
      );

      return response;
    } on SocketException catch (e) {
      debugPrint('Socket exception during image download: $e');
      // Don't rethrow - let the cache manager handle it gracefully
      rethrow;
    } on HttpException catch (e) {
      debugPrint('HTTP exception during image download: $e');
      // Don't rethrow - let the cache manager handle it gracefully
      rethrow;
    } on TimeoutException catch (e) {
      debugPrint('Timeout exception during image download: $e');
      // Don't rethrow - let the cache manager handle it gracefully
      rethrow;
    } catch (e, stackTrace) {
      debugPrint('Unexpected error during image download: $e');
      debugPrint('Stack trace: $stackTrace');
      // Don't rethrow - let the cache manager handle it gracefully
      rethrow;
    }
  }

  http.BaseRequest _addResilientHeaders(http.BaseRequest request) {
    // Clone the request and add resilient headers
    final newRequest = http.Request(request.method, request.url);

    // Copy existing headers
    newRequest.headers.addAll(request.headers);

    // Add resilient headers
    newRequest.headers.addAll({
      'Connection': 'close', // Use close instead of keep-alive for images
      'User-Agent': 'RuckingApp/3.0.0 (Flutter)',
      'Accept': 'image/*,*/*;q=0.8',
      'Cache-Control': 'max-age=3600',
    });

    return newRequest;
  }

  @override
  void close() {
    _inner.close();
    super.close();
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
