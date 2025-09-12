import 'package:flutter/material.dart';
import 'package:rucking_app/core/managers/app_update_manager.dart';
import 'package:rucking_app/core/services/app_update_service.dart';
import 'package:rucking_app/shared/widgets/app_update_widgets.dart';

/// Widget to show update banner on home screen
class UpdateBannerWidget extends StatefulWidget {
  const UpdateBannerWidget({Key? key}) : super(key: key);

  @override
  State<UpdateBannerWidget> createState() => _UpdateBannerWidgetState();
}

class _UpdateBannerWidgetState extends State<UpdateBannerWidget> {
  UpdateInfo? _updateInfo;
  bool _isDismissed = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    try {
      final updateInfo = await AppUpdateManager.instance.getPendingUpdate();
      if (mounted) {
        setState(() {
          _updateInfo = updateInfo;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox.shrink(); // Don't show loading state
    }

    if (_updateInfo == null || _isDismissed) {
      return const SizedBox.shrink();
    }

    return UpdateAvailableBanner(
      updateInfo: _updateInfo!,
      features: _getLatestFeatures(),
      onUpdate: () {
        AppUpdateManager.instance.handleUpdatePressed(_updateInfo!);
        setState(() {
          _isDismissed = true;
        });
      },
      onDismiss: () async {
        await AppUpdateManager.instance.handleUpdateDismissed(_updateInfo!);
        setState(() {
          _isDismissed = true;
        });
      },
    );
  }

  List<String> _getLatestFeatures() {
    // You can customize these based on the version
    return [
      '🔧 Fixed elevation recovery in crash system',
      '📱 Improved app stability and performance',
      '✨ Enhanced user experience',
      '🐛 Various bug fixes',
    ];
  }
}

/// Example integration for home screen
class HomeScreenUpdateIntegration extends StatefulWidget {
  final Widget child;

  const HomeScreenUpdateIntegration({
    Key? key,
    required this.child,
  }) : super(key: key);

  @override
  State<HomeScreenUpdateIntegration> createState() =>
      _HomeScreenUpdateIntegrationState();
}

class _HomeScreenUpdateIntegrationState
    extends State<HomeScreenUpdateIntegration> with UpdatePromptMixin {
  @override
  void initState() {
    super.initState();

    // Check for updates on home screen load (with delay to not interfere with loading)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          checkForUpdatesIfAppropriate(
            context: UpdatePromptContext.homeScreen,
          );
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Update banner at the top
        const UpdateBannerWidget(),
        // Main content
        Expanded(child: widget.child),
      ],
    );
  }
}

/// Settings screen update check button
class UpdateCheckButton extends StatefulWidget {
  const UpdateCheckButton({Key? key}) : super(key: key);

  @override
  State<UpdateCheckButton> createState() => _UpdateCheckButtonState();
}

class _UpdateCheckButtonState extends State<UpdateCheckButton> {
  bool _isChecking = false;

  Future<void> _checkForUpdates() async {
    setState(() {
      _isChecking = true;
    });

    try {
      final updateInfo = await AppUpdateManager.instance.manualUpdateCheck();

      if (!mounted) return;

      if (updateInfo != null) {
        // Show update prompt
        await AppUpdateManager.instance.checkAndPromptForUpdate(
          context,
          promptContext: UpdatePromptContext.manual,
        );
      } else {
        // Show "no updates" message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ You\'re running the latest version!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Failed to check for updates'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isChecking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.system_update),
      title: const Text('Check for Updates'),
      subtitle: const Text('Check if a newer version is available'),
      trailing: _isChecking
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right),
      onTap: _isChecking ? null : _checkForUpdates,
    );
  }
}
