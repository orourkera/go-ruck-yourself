import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/services/service_locator.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';

class AppUpdateService {
  static const String _dismissedVersionKey = 'update_dismissed_version';
  static const String _lastPromptedVersionKey = 'last_prompted_version';
  static const String _lastCheckTimeKey = 'last_update_check_time';
  
  // App Store URLs
  static const String _iosAppStoreUrl = 'https://apps.apple.com/app/ruck-app/id6738063624';
  static const String _androidPlayStoreUrl = 'https://play.google.com/store/apps/details?id=com.getrucky.rucking_app';
  
  final ApiClient _apiClient;
  
  AppUpdateService(this._apiClient);
  
  /// Check if an app update is available
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      
      AppLogger.info('[UPDATE_SERVICE] Current app version: $currentVersion');
      
      // Check if we recently checked (avoid spamming the API)
      if (await _wasRecentlyChecked()) {
        AppLogger.debug('[UPDATE_SERVICE] Update check was done recently, skipping');
        return null;
      }
      
      // Get latest version from backend
      final latestVersion = await _getLatestVersionFromBackend();
      if (latestVersion == null) return null;
      
      AppLogger.info('[UPDATE_SERVICE] Latest available version: $latestVersion');
      
      // Save check time
      await _markCheckTime();
      
      // Compare versions
      if (_isNewerVersion(latestVersion, currentVersion)) {
        return UpdateInfo(
          currentVersion: currentVersion,
          latestVersion: latestVersion,
          updateUrl: _getAppStoreUrl(),
          isForced: await _isForceUpdateRequired(currentVersion),
        );
      }
      
      return null;
    } catch (e) {
      AppLogger.error('[UPDATE_SERVICE] Error checking for updates: $e');
      return null;
    }
  }
  
  /// Get the latest version from your backend
  Future<String?> _getLatestVersionFromBackend() async {
    try {
      final platform = Platform.isIOS ? 'ios' : 'android';
      final response = await _apiClient.get('/app/version-info', queryParams: {'platform': platform});
      return response['latest_version'] as String?;
    } catch (e) {
      AppLogger.warning('[UPDATE_SERVICE] Failed to get version from backend: $e');
      return null;
    }
  }
  
  /// Check if there's an active ruck session that would be disrupted by an update
  bool _hasActiveSession() {
    try {
      if (!getIt.isRegistered<ActiveSessionBloc>()) {
        return false;
      }
      
      final activeSessionBloc = getIt<ActiveSessionBloc>();
      final state = activeSessionBloc.state;
      
      // Consider ActiveSessionRunning as active, even if paused (user may resume)
      final isActive = state is ActiveSessionRunning;
      
      if (isActive) {
        final sessionState = state as ActiveSessionRunning;
        final statusText = sessionState.isPaused ? 'PAUSED' : 'RUNNING';
        AppLogger.warning('[UPDATE_SERVICE] 🚫 Active ruck session detected ($statusText) - blocking updates');
        AppLogger.info('[UPDATE_SERVICE] Session ID: ${sessionState.sessionId}, Duration: ${sessionState.elapsedSeconds}s, Distance: ${sessionState.distanceKm.toStringAsFixed(2)}km');
      }
      
      return isActive;
    } catch (e) {
      AppLogger.warning('[UPDATE_SERVICE] Error checking active session: $e');
      return false; // Assume no active session if we can't check
    }
  }

  /// Check if a force update is required for the current version
  Future<bool> _isForceUpdateRequired(String currentVersion) async {
    try {
      final platform = Platform.isIOS ? 'ios' : 'android';
      final response = await _apiClient.get('/app/version-info', queryParams: {'platform': platform});
      final minRequiredVersion = response['min_required_version'] as String?;
      final forceUpdate = response['force_update'] as bool? ?? false;
      
      if (minRequiredVersion == null) return false;
      
      // CRITICAL: Never force update during active ruck sessions
      if (forceUpdate && _hasActiveSession()) {
        AppLogger.critical('[UPDATE_SERVICE] 🛡️ BLOCKING force update - active ruck session in progress');
        return false; // Override force update if session is active
      }
      
      return _isVersionBelow(currentVersion, minRequiredVersion);
    } catch (e) {
      AppLogger.warning('[UPDATE_SERVICE] Failed to check force update requirement: $e');
      return false;
    }
  }
  
  /// Check if we should show the update prompt for a specific version
  Future<bool> shouldShowUpdatePrompt(String latestVersion) async {
    try {
      // CRITICAL: Never show update prompts during active sessions
      if (_hasActiveSession()) {
        AppLogger.info('[UPDATE_SERVICE] 🚫 Skipping update prompt - active ruck session in progress');
        return false;
      }
      
      final prefs = await SharedPreferences.getInstance();
      
      // Don't show if user dismissed this version
      final dismissedVersion = prefs.getString(_dismissedVersionKey);
      if (dismissedVersion == latestVersion) {
        AppLogger.debug('[UPDATE_SERVICE] User dismissed version $latestVersion');
        return false;
      }
      
      // Don't spam - only show once per version per day
      final lastPromptedVersion = prefs.getString(_lastPromptedVersionKey);
      if (lastPromptedVersion == latestVersion) {
        AppLogger.debug('[UPDATE_SERVICE] Already prompted for version $latestVersion');
        return false;
      }
      
      AppLogger.info('[UPDATE_SERVICE] Should show update prompt for version $latestVersion');
      return true;
    } catch (e) {
      AppLogger.error('[UPDATE_SERVICE] Error checking if should show prompt: $e');
      return false;
    }
  }
  
  /// Mark that we showed the update prompt for a version
  Future<void> markPromptShown(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastPromptedVersionKey, version);
      AppLogger.debug('[UPDATE_SERVICE] Marked prompt shown for version $version');
    } catch (e) {
      AppLogger.error('[UPDATE_SERVICE] Error marking prompt shown: $e');
    }
  }
  
  /// Mark that user dismissed the update for a version
  Future<void> dismissUpdate(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_dismissedVersionKey, version);
      AppLogger.info('[UPDATE_SERVICE] User dismissed update for version $version');
    } catch (e) {
      AppLogger.error('[UPDATE_SERVICE] Error dismissing update: $e');
    }
  }
  
  /// Open the appropriate app store for the current platform
  Future<void> openAppStore() async {
    try {
      final url = _getAppStoreUrl();
      AppLogger.info('[UPDATE_SERVICE] Opening app store: $url');
      
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
      } else {
        AppLogger.error('[UPDATE_SERVICE] Cannot launch app store URL: $url');
      }
    } catch (e) {
      AppLogger.error('[UPDATE_SERVICE] Error opening app store: $e');
    }
  }
  
  /// Get the app store URL for the current platform
  String _getAppStoreUrl() {
    if (Platform.isIOS) {
      return _iosAppStoreUrl;
    } else if (Platform.isAndroid) {
      return _androidPlayStoreUrl;
    } else {
      // Fallback to iOS for other platforms
      return _iosAppStoreUrl;
    }
  }
  
  /// Check if we recently checked for updates (within last 4 hours)
  Future<bool> _wasRecentlyChecked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCheckTime = prefs.getInt(_lastCheckTimeKey);
      
      if (lastCheckTime == null) return false;
      
      final now = DateTime.now().millisecondsSinceEpoch;
      final fourHoursAgo = now - (4 * 60 * 60 * 1000); // 4 hours in milliseconds
      
      return lastCheckTime > fourHoursAgo;
    } catch (e) {
      return false;
    }
  }
  
  /// Mark the time we checked for updates
  Future<void> _markCheckTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastCheckTimeKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      AppLogger.warning('[UPDATE_SERVICE] Failed to mark check time: $e');
    }
  }
  
  /// Compare version strings to see if the first is newer than the second
  bool _isNewerVersion(String version1, String version2) {
    try {
      final v1Parts = version1.split('.').map(int.parse).toList();
      final v2Parts = version2.split('.').map(int.parse).toList();
      
      // Pad with zeros if needed
      while (v1Parts.length < 3) v1Parts.add(0);
      while (v2Parts.length < 3) v2Parts.add(0);
      
      for (int i = 0; i < 3; i++) {
        if (v1Parts[i] > v2Parts[i]) return true;
        if (v1Parts[i] < v2Parts[i]) return false;
      }
      
      return false; // Versions are equal
    } catch (e) {
      AppLogger.warning('[UPDATE_SERVICE] Error comparing versions: $e');
      return false;
    }
  }
  
  /// Check if version1 is below version2
  bool _isVersionBelow(String version1, String version2) {
    return _isNewerVersion(version2, version1);
  }
  
  /// Clear all update-related preferences (for testing)
  Future<void> clearUpdatePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_dismissedVersionKey);
      await prefs.remove(_lastPromptedVersionKey);
      await prefs.remove(_lastCheckTimeKey);
      AppLogger.info('[UPDATE_SERVICE] Cleared all update preferences');
    } catch (e) {
      AppLogger.error('[UPDATE_SERVICE] Error clearing update preferences: $e');
    }
  }
}

/// Data class for update information
class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String updateUrl;
  final bool isForced;
  
  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.updateUrl,
    required this.isForced,
  });
  
  @override
  String toString() {
    return 'UpdateInfo(current: $currentVersion, latest: $latestVersion, forced: $isForced)';
  }
}
