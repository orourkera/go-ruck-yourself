import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

class UpdateService {
  static Future<void> checkForUpdates(BuildContext context) async {
    try {
      final info = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(info.buildNumber) ?? 0;

      final rc = FirebaseRemoteConfig.instance;
      await rc.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 5),
        minimumFetchInterval: const Duration(hours: 1),
      ));
      await rc.setDefaults(const {
        'min_supported_build': 0,
        'latest_build': 0,
        'release_notes': '',
        'update_url_ios': '',
        'update_url_android': '',
      });
      await rc.fetchAndActivate();

      final minSupported = rc.getInt('min_supported_build');
      final latest = rc.getInt('latest_build');
      final notes = rc.getString('release_notes');
      final updateUrlIos = rc.getString('update_url_ios');
      final updateUrlAndroid = rc.getString('update_url_android');

      AppLogger.info(
          '[UPDATE] build=$currentBuild, min=$minSupported, latest=$latest');

      if (currentBuild < minSupported) {
        _showBlockingDialog(context, notes, updateUrlIos, updateUrlAndroid);
      } else if (currentBuild < latest) {
        _showSoftDialog(context, notes, updateUrlIos, updateUrlAndroid);
      }
    } catch (e) {
      AppLogger.warning('[UPDATE] Update check failed: $e');
    }
  }

  static void _showBlockingDialog(
      BuildContext context, String notes, String iosUrl, String androidUrl) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Update Required'),
        content: Text(notes.isEmpty ? 'Please update to continue.' : notes),
        actions: [
          TextButton(
            onPressed: () => _launchStore(iosUrl, androidUrl),
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  static void _showSoftDialog(
      BuildContext context, String notes, String iosUrl, String androidUrl) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Update Available'),
        content: Text(notes.isEmpty ? 'A new version is available.' : notes),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Later')),
          TextButton(
            onPressed: () => _launchStore(iosUrl, androidUrl),
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  static Future<void> _launchStore(String iosUrl, String androidUrl) async {
    try {
      // Use a simple launcher via GetIt if available; fallback no-op
      final launcher = GetIt.I.isRegistered<Function(String)>()
          ? GetIt.I<Function(String)>()
          : null;
      final uri = iosUrl.isNotEmpty ? iosUrl : androidUrl;
      if (launcher != null && uri.isNotEmpty) {
        await launcher(uri);
      }
    } catch (_) {}
  }
}
