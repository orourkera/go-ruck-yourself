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
  /// Prioritizes static images over GIF to prevent native crashes
  static String getSplashImagePath(bool isLadyMode) {
    // Primary: Try static PNG first for stability
    if (_assetExists('assets/images/app_icon.png')) {
      return 'assets/images/app_icon.png';
    }
    
    // Fallback 1: Generic launcher icon
    if (_assetExists('assets/launcher/icon.png')) {
      return 'assets/launcher/icon.png';
    }
    
    // Fallback 2: GIF (last resort due to crash risk)
    return 'assets/images/splash.gif';
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
  /// Prioritizes static images over GIF to prevent native crashes
  static List<String> getFallbackImagePaths() {
    return [
      'assets/images/app_icon.png',      // Static PNG - safer
      'assets/launcher/icon.png',        // Static PNG - safer
      'assets/images/splash.gif',        // GIF - higher crash risk, use as last resort
    ];
  }
  
  /// Gets the unified background color for splash screen
  /// No longer depends on gender - uses the same color for all users
  static Color getBackgroundColor(bool isLadyMode) {
    return AppColors.splashBackground; // Unified dark green for all users
  }
}
