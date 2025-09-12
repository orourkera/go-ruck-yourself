import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/services/app_update_service.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/shared/widgets/app_update_widgets.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

/// Manages app update checks and prompts with smart timing
class AppUpdateManager {
  static AppUpdateManager? _instance;
  static AppUpdateManager get instance => _instance ??= AppUpdateManager._();

  AppUpdateManager._();

  final AppUpdateService _updateService = AppUpdateService(
    GetIt.instance<ApiClient>(),
  );

  UpdateInfo? _latestUpdateInfo;
  bool _isCheckingForUpdate = false;

  /// Check for updates and show appropriate prompt based on context
  Future<void> checkAndPromptForUpdate(
    BuildContext context, {
    UpdatePromptContext promptContext = UpdatePromptContext.automatic,
    List<String>? releaseFeatures,
  }) async {
    if (_isCheckingForUpdate) return;

    try {
      _isCheckingForUpdate = true;
      AppLogger.info('[UPDATE_MANAGER] Checking for updates...');

      final updateInfo = await _updateService.checkForUpdate();
      if (updateInfo == null) {
        AppLogger.debug('[UPDATE_MANAGER] No update available');
        return;
      }

      _latestUpdateInfo = updateInfo;
      AppLogger.info(
          '[UPDATE_MANAGER] Update available: ${updateInfo.latestVersion}');

      // Check if we should show the prompt
      if (!await _updateService
          .shouldShowUpdatePrompt(updateInfo.latestVersion)) {
        AppLogger.debug(
            '[UPDATE_MANAGER] Skipping update prompt based on user preferences');
        return;
      }

      // Show appropriate prompt based on context and force status
      if (updateInfo.isForced) {
        await _showForceUpdateDialog(context, updateInfo);
      } else {
        await _showUpdatePrompt(
            context, updateInfo, promptContext, releaseFeatures);
      }

      // Mark that we showed the prompt
      await _updateService.markPromptShown(updateInfo.latestVersion);
    } catch (e) {
      AppLogger.error('[UPDATE_MANAGER] Error checking for updates: $e');
    } finally {
      _isCheckingForUpdate = false;
    }
  }

  /// Show update prompt based on context
  Future<void> _showUpdatePrompt(
    BuildContext context,
    UpdateInfo updateInfo,
    UpdatePromptContext promptContext,
    List<String>? features,
  ) async {
    // Always show modal for better UX - no more banner pushing content down
    await _showUpdateBottomSheet(context, updateInfo, features);
  }

  /// Show update bottom sheet
  Future<void> _showUpdateBottomSheet(
    BuildContext context,
    UpdateInfo updateInfo,
    List<String>? features,
  ) async {
    if (!context.mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => UpdateBottomSheet(
        updateInfo: updateInfo,
        features: features ?? _getDefaultFeatures(),
        onUpdate: () {
          Navigator.of(context).pop();
          handleUpdatePressed(updateInfo);
        },
        onDismiss: () {
          Navigator.of(context).pop();
          handleUpdateDismissed(updateInfo);
        },
      ),
    );
  }

  /// Show blocking force update dialog
  Future<void> _showForceUpdateDialog(
    BuildContext context,
    UpdateInfo updateInfo,
  ) async {
    if (!context.mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ForceUpdateDialog(
        updateInfo: updateInfo,
        onUpdate: () => handleUpdatePressed(updateInfo),
      ),
    );
  }

  /// Handle when user presses update button
  void handleUpdatePressed(UpdateInfo updateInfo) {
    AppLogger.info(
        '[UPDATE_MANAGER] User chose to update to ${updateInfo.latestVersion}');
    _updateService.openAppStore();
  }

  /// Handle when user dismisses update prompt
  Future<void> handleUpdateDismissed(UpdateInfo updateInfo) async {
    AppLogger.info(
        '[UPDATE_MANAGER] User dismissed update for ${updateInfo.latestVersion}');
    await _updateService.dismissUpdate(updateInfo.latestVersion);
  }

  /// Get default features list when none provided
  List<String> _getDefaultFeatures() {
    return [
      '🚀 Performance improvements',
      '🐛 Bug fixes and stability',
      '✨ Enhanced user experience',
    ];
  }

  /// Check if there's a pending update that should be shown on home screen
  Future<UpdateInfo?> getPendingUpdate() async {
    if (_latestUpdateInfo == null) {
      _latestUpdateInfo = await _updateService.checkForUpdate();
    }

    if (_latestUpdateInfo == null) return null;

    // Check if we should show it
    final shouldShow = await _updateService.shouldShowUpdatePrompt(
      _latestUpdateInfo!.latestVersion,
    );

    return shouldShow ? _latestUpdateInfo : null;
  }

  /// Get current update info (if any)
  UpdateInfo? get currentUpdateInfo => _latestUpdateInfo;

  /// Manually trigger update check (for settings screen)
  Future<UpdateInfo?> manualUpdateCheck() async {
    AppLogger.info('[UPDATE_MANAGER] Manual update check requested');

    // Force a fresh check by clearing cache
    await _updateService.clearUpdatePreferences();

    return await _updateService.checkForUpdate();
  }

  /// Clear all update preferences (for testing/debugging)
  Future<void> clearUpdatePreferences() async {
    await _updateService.clearUpdatePreferences();
    _latestUpdateInfo = null;
    AppLogger.info('[UPDATE_MANAGER] Cleared all update preferences');
  }
}

/// Context for where the update prompt is being shown
enum UpdatePromptContext {
  homeScreen, // Banner on home screen
  afterSession, // After completing a ruck session
  manual, // User manually checked for updates
  automatic, // Automatic check on app launch
}

/// Mixin for screens that want to show update prompts
mixin UpdatePromptMixin<T extends StatefulWidget> on State<T> {
  /// Check for updates when appropriate (e.g., after session completion)
  Future<void> checkForUpdatesIfAppropriate({
    UpdatePromptContext context = UpdatePromptContext.automatic,
    List<String>? features,
  }) async {
    if (!mounted) return;

    // Add a small delay to avoid interfering with other UI
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    await AppUpdateManager.instance.checkAndPromptForUpdate(
      this.context,
      promptContext: context,
      releaseFeatures: features,
    );
  }
}
