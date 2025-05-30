import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Custom cache manager for images with longer cache duration
class ImageCacheManager {
  static const String _key = 'RuckImageCache';
  
  /// Cache manager with extended duration for better user experience
  static CacheManager get instance => CacheManager(
    Config(
      _key,
      // Cache for 30 days instead of default 7 days
      stalePeriod: const Duration(days: 30),
      // Keep maximum 500 cached images (default is 200)
      maxNrOfCacheObjects: 500,
    ),
  );
  
  /// Clear the image cache if needed
  static Future<void> clearCache() async {
    await instance.emptyCache();
  }
}
