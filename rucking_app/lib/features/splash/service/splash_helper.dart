import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:rucking_app/core/config/app_config.dart';
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
  
  /// Determines which splash image to use based on gender status
  static String getSplashImagePath(bool isLadyMode) {
    return isLadyMode
        ? 'assets/images/go_ruck_yourself_lady.png' // Female version
        : 'assets/images/go ruck yourself.png'; // Default/male version
  }
  
  /// Gets the appropriate background color based on gender
  static Color getBackgroundColor(bool isLadyMode) {
    return isLadyMode ? AppColors.ladyPrimary : AppColors.primary;
  }
}
