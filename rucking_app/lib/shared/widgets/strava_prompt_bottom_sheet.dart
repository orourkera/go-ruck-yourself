import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../core/services/strava_service.dart';
import '../../core/services/strava_prompt_service.dart';
import '../../core/services/analytics_service.dart';
import '../../core/utils/app_logger.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'styled_snackbar.dart';

class StravaPromptBottomSheet extends StatefulWidget {
  const StravaPromptBottomSheet({Key? key}) : super(key: key);

  static Future<void> show(BuildContext context) async {
    final promptService = StravaPromptService();

    // Record that we're showing the prompt
    await promptService.recordPromptShown();

    // Track analytics
    AnalyticsService.trackEvent('strava_prompt_shown', {
      'source': 'bottom_sheet',
      'timestamp': DateTime.now().toIso8601String(),
    });

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const StravaPromptBottomSheet(),
    );
  }

  @override
  State<StravaPromptBottomSheet> createState() => _StravaPromptBottomSheetState();
}

class _StravaPromptBottomSheetState extends State<StravaPromptBottomSheet>
    with WidgetsBindingObserver {
  final StravaService _stravaService = StravaService();
  final StravaPromptService _promptService = StravaPromptService();
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // When returning from Strava OAuth, check connection status
    if (state == AppLifecycleState.resumed && _isConnecting) {
      _checkConnectionAfterOAuth();
    }
  }

  Future<void> _checkConnectionAfterOAuth() async {
    // Wait a bit for OAuth callback to process
    await Future.delayed(const Duration(seconds: 2));

    try {
      final status = await _stravaService.getConnectionStatus();
      if (status.connected && mounted) {
        AnalyticsService.trackStravaConnection(
          connected: true,
          source: 'bottom_sheet_prompt'
        );

        Navigator.of(context).pop();

        StyledSnackBar.showSuccess(
          context: context,
          message: 'Successfully connected to Strava! 🎉',
          duration: const Duration(seconds: 3),
        );
      }
    } catch (e) {
      AppLogger.error('[STRAVA_PROMPT] Failed to verify connection: $e');
    }
  }

  Future<void> _connectToStrava() async {
    setState(() => _isConnecting = true);

    // Record acceptance
    await _promptService.recordPromptAccepted();

    // Track analytics
    AnalyticsService.trackEvent('strava_prompt_connect_clicked', {
      'source': 'bottom_sheet',
      'timestamp': DateTime.now().toIso8601String(),
    });

    try {
      final success = await _stravaService.connectToStrava();

      if (success && mounted) {
        StyledSnackBar.show(
          context: context,
          message: 'Opening Strava authorization...',
          duration: const Duration(seconds: 2),
          type: SnackBarType.normal,
        );
      } else if (mounted) {
        setState(() => _isConnecting = false);
        StyledSnackBar.showError(
          context: context,
          message: 'Failed to open Strava authorization',
          duration: const Duration(seconds: 3),
        );
      }
    } catch (e) {
      AppLogger.error('[STRAVA_PROMPT] Connect error: $e');
      if (mounted) {
        setState(() => _isConnecting = false);
        StyledSnackBar.showError(
          context: context,
          message: 'Error connecting to Strava',
          duration: const Duration(seconds: 3),
        );
      }
    }
  }

  void _dismissPrompt() async {
    // Record dismissal
    await _promptService.recordPromptDismissed();

    // Track analytics
    AnalyticsService.trackEvent('strava_prompt_dismissed', {
      'source': 'bottom_sheet',
      'timestamp': DateTime.now().toIso8601String(),
    });

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),

              // Title with emoji
              Text(
                '🚀 Double Your Success Rate!',
                style: AppTextStyles.headlineMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // Success metric
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Text(
                  '50% more rucks in week 1 with Strava',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: Colors.green[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Description
              Text(
                'Connect Strava to automatically share your rucks with detailed maps, stats, and achievements.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: Colors.grey[700],
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Benefits with icons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildBenefit(Icons.map_outlined, 'Route\nMaps'),
                  _buildBenefit(Icons.fitness_center, 'Weight\nCarried'),
                  _buildBenefit(Icons.people_outline, 'Social\nSharing'),
                ],
              ),
              const SizedBox(height: 28),

              // Connect Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isConnecting ? null : _connectToStrava,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(double.infinity, 56),
                  ),
                  child: _isConnecting
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                          ),
                        )
                      : Image.asset(
                          'assets/images/btn_strava_connect_with_orange.png',
                          height: 56,
                          fit: BoxFit.contain,
                        ),
                ),
              ),
              const SizedBox(height: 12),

              // Maybe Later Button
              TextButton(
                onPressed: _isConnecting ? null : _dismissPrompt,
                child: Text(
                  'Maybe later',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBenefit(IconData icon, String label) {
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: AppColors.primary,
            size: 24,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            color: Colors.grey[700],
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}