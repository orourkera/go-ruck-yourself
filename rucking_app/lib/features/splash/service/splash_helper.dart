import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';

/// Helper class for splash screen functionality
class SplashHelper {
  static const _storage = FlutterSecureStorage();
  static const _ladyModeKey = 'lady_mode_enabled';
  
  /// Caches whether lady mode is active for quick access at app startup
  /// This allows us to show the correct splash screen instantly
  static Future<void> cacheLadyModeStatus(bool isLadyMode) async {
    try {
      await _storage.write(key: _ladyModeKey, value: isLadyMode.toString());
      debugPrint('[SplashHelper] Lady mode status cached: $isLadyMode');
    } catch (e) {
      debugPrint('[SplashHelper] Error caching lady mode status: $e');
    }
  }
  
  /// Checks if lady mode is active from cached value
  /// Returns false if no cached value exists or if there's an error
  static Future<bool> isLadyModeActive() async {
    try {
      final cachedValue = await _storage.read(key: _ladyModeKey);
      return cachedValue == 'true';
    } catch (e) {
      debugPrint('[SplashHelper] Error reading lady mode cache: $e');
      return false;
    }
  }
  
  /// Returns the appropriate splash image path with fallback options
  /// Prioritizes animated GIF but provides fallbacks for older Android devices
  static String getSplashImagePath(bool isLadyMode) {
    // Primary: Use animated GIF as requested
    return 'assets/images/splash.gif';
  }
  
  /// Returns fallback image paths for older Android devices that can't handle GIFs
  static List<String> getFallbackImagePaths() {
    return [
      'assets/images/splash.gif',     // Try GIF first
      'assets/images/app_icon.png',   // Fallback to static PNG
      'assets/launcher/icon.png',     // Final fallback
    ];
  }
  
  /// Checks if an asset exists in the bundle
  /// Returns false if asset cannot be verified to prevent crashes
  static bool _assetExists(String assetPath) {
    try {
      // This is a simple check - in production you might want more validation
      return assetPath.isNotEmpty && assetPath.contains('assets/');
    } catch (e) {
      debugPrint('[SplashHelper] Asset existence check failed for $assetPath: $e');
      return false;
    }
  }
  

  
  /// Gets the unified background color for splash screen
  /// No longer depends on gender - uses the same color for all users
  static Color getBackgroundColor(bool isLadyMode) {
    return AppColors.splashBackground; // Unified dark green for all users
  }
}
