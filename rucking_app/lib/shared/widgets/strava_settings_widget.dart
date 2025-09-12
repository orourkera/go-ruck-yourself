import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../core/services/strava_service.dart';
import '../../core/utils/app_logger.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class StravaSettingsWidget extends StatefulWidget {
  const StravaSettingsWidget({super.key});

  @override
  State<StravaSettingsWidget> createState() => _StravaSettingsWidgetState();
}

class _StravaSettingsWidgetState extends State<StravaSettingsWidget>
    with WidgetsBindingObserver {
  final StravaService _stravaService = StravaService();
  StravaConnectionStatus? _connectionStatus;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadConnectionStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // When returning from external Strava OAuth, the app resumes. Refresh status.
    if (state == AppLifecycleState.resumed) {
      _loadConnectionStatus();
    }
  }

  Future<void> _loadConnectionStatus() async {
    setState(() => _isLoading = true);

    try {
      final status = await _stravaService.getConnectionStatus();
      if (mounted) {
        setState(() {
          _connectionStatus = status;
          _isLoading = false;
        });
      }
    } catch (e) {
      AppLogger.error('[STRAVA_SETTINGS] Failed to load status: $e');

      // Handle authentication errors gracefully - show as disconnected
      // The API client will handle token refresh automatically
      if (e.toString().contains('401') ||
          e.toString().contains('Unauthorized')) {
        AppLogger.info(
            '[STRAVA_SETTINGS] Authentication error - showing as disconnected');
        if (mounted) {
          setState(() {
            _connectionStatus = StravaConnectionStatus(connected: false);
            _isLoading = false;
          });
        }
      } else {
        // For other errors, show loading failed state
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<void> _connectToStrava() async {
    setState(() => _isLoading = true);

    try {
      final success = await _stravaService.connectToStrava();

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Opening Strava authorization...'),
            backgroundColor: Colors.green,
          ),
        );

        // Reload status after a short delay to allow OAuth flow
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            _loadConnectionStatus();
          }
        });
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to open Strava authorization'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      AppLogger.error('[STRAVA_SETTINGS] Connect error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error connecting to Strava'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _disconnectFromStrava() async {
    // Show confirmation dialog
    final shouldDisconnect = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect Strava'),
        content: const Text(
          'Are you sure you want to disconnect your Strava account? '
          'You will no longer be able to export ruck sessions to Strava.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (shouldDisconnect != true) return;

    setState(() => _isLoading = true);

    try {
      final success = await _stravaService.disconnect();

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Successfully disconnected from Strava'),
            backgroundColor: Colors.green,
          ),
        );
        _loadConnectionStatus();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to disconnect from Strava'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      AppLogger.error('[STRAVA_SETTINGS] Disconnect error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error disconnecting from Strava'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _connectionStatus == null) {
      return const Card(
        child: ListTile(
          leading: CircularProgressIndicator(),
          title: Text('Loading Strava connection...'),
        ),
      );
    }

    final isConnected = _connectionStatus?.connected ?? false;

    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/images/btn_strava_connect_with_orange.png',
                  width: 40,
                  height: 40,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            title: const Text(
              'Strava Integration',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              isConnected
                  ? 'Connected • Export your rucks to Strava'
                  : 'Connect to automatically export ruck sessions',
            ),
            trailing: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : isConnected
                    ? Icon(
                        Icons.check_circle,
                        color: Colors.green[600],
                        size: 24,
                      )
                    : const Icon(
                        Icons.link,
                        color: Colors.grey,
                        size: 24,
                      ),
          ),
          if (isConnected) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_connectionStatus?.athleteId != null)
                    Text(
                      'Athlete ID: ${_connectionStatus!.athleteId}',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                  if (_connectionStatus?.connectedAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Connected: ${_formatDate(_connectionStatus!.connectedAt!)}',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isLoading ? null : _disconnectFromStrava,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                          ),
                          child: const Text('Disconnect'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Export your ruck sessions to Strava to share with friends and track your progress across platforms.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _connectToStrava,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: EdgeInsets.zero,
                          ),
                          child: Image.asset(
                            'assets/images/btn_strava_connect_with_orange.png',
                            height: 48,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}
