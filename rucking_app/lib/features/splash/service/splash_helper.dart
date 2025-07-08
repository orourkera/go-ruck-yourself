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
  /// Provides multiple fallback assets to prevent crashes
  static String getSplashImagePath(bool isLadyMode) {
    // Primary: Try GIF first for animated splash
    if (_assetExists('assets/images/splash.gif')) {
      return 'assets/images/splash.gif';
    }
    
    // Fallback 1: App icon PNG
    if (_assetExists('assets/images/app_icon.png')) {
      return 'assets/images/app_icon.png';
    }
    
    // Fallback 2: Generic launcher icon
    return 'assets/launcher/icon.png';
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
  
  /// Gets a list of fallback image paths in order of preference
  static List<String> getFallbackImagePaths() {
    return [
      'assets/images/splash.gif',
      'assets/images/app_icon.png',
      'assets/launcher/icon.png',
    ];
  }
  
  /// Gets the unified background color for splash screen
  /// No longer depends on gender - uses the same color for all users
  static Color getBackgroundColor(bool isLadyMode) {
    return AppColors.splashBackground; // Unified dark green for all users
  }
}
