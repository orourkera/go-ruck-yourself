import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../../core/services/strava_service.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/theme/app_text_styles.dart';
import '../../../../shared/widgets/styled_snackbar.dart';

class StravaOnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;
  final VoidCallback? onSkip;

  const StravaOnboardingScreen({
    Key? key,
    required this.onComplete,
    this.onSkip,
  }) : super(key: key);

  @override
  State<StravaOnboardingScreen> createState() => _StravaOnboardingScreenState();
}

class _StravaOnboardingScreenState extends State<StravaOnboardingScreen>
    with WidgetsBindingObserver {
  final StravaService _stravaService = StravaService();
  bool _isConnecting = false;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkExistingConnection();
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
    if (state == AppLifecycleState.resumed) {
      _checkConnectionAfterOAuth();
    }
  }

  Future<void> _checkExistingConnection() async {
    try {
      final status = await _stravaService.getConnectionStatus();
      if (status.connected && mounted) {
        setState(() => _isConnected = true);
        // Auto-proceed if already connected
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) widget.onComplete();
        });
      }
    } catch (e) {
      AppLogger.error('[STRAVA_ONBOARDING] Failed to check connection: $e');
    }
  }

  Future<void> _checkConnectionAfterOAuth() async {
    if (!_isConnecting) return;

    // Wait a bit for OAuth callback to process
    await Future.delayed(const Duration(seconds: 2));

    try {
      final status = await _stravaService.getConnectionStatus();
      if (status.connected && mounted) {
        setState(() {
          _isConnected = true;
          _isConnecting = false;
        });

        AnalyticsService.trackStravaConnection(connected: true, source: 'onboarding');

        StyledSnackBar.showSuccess(
          context: context,
          message: 'Successfully connected to Strava!',
          duration: const Duration(seconds: 2),
        );

        // Proceed after showing success
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) widget.onComplete();
        });
      }
    } catch (e) {
      AppLogger.error('[STRAVA_ONBOARDING] Failed to verify connection: $e');
    }
  }

  Future<void> _connectToStrava() async {
    setState(() => _isConnecting = true);

    try {
      final success = await _stravaService.connectToStrava();

      if (success && mounted) {
        StyledSnackBar.showInfo(
          context: context,
          message: 'Opening Strava authorization...',
          duration: const Duration(seconds: 2),
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
      AppLogger.error('[STRAVA_ONBOARDING] Connect error: $e');
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

  void _skipStrava() {
    AnalyticsService.trackStravaConnection(connected: false, source: 'onboarding_skipped');

    if (widget.onSkip != null) {
      widget.onSkip!();
    } else {
      widget.onComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: Text(
          'Connect to Strava',
          style: AppTextStyles.headlineMedium.copyWith(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // Strava Logo
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.asset(
                          'assets/images/btn_strava_connect_with_orange.png',
                          height: 80,
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Title
                      Text(
                        'Share Your Rucks with the World',
                        style: AppTextStyles.headlineMedium.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),

                      // Success Rate Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.green.withOpacity(0.3)),
                        ),
                        child: Text(
                          '🚀 2X MORE LIKELY TO SUCCEED',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: Colors.green[700],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Description
                      Text(
                        'When you connect Strava, we automatically publish your rucks with:',
                        style: AppTextStyles.bodyLarge.copyWith(
                          color: Colors.grey[600],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),

                      // Features
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.primary.withOpacity(0.2),
                          ),
                        ),
                        child: Column(
                          children: [
                            _buildFeatureRow('Full GPS route maps with elevation'),
                            const SizedBox(height: 12),
                            _buildFeatureRow('Detailed ruck summaries and stats'),
                            const SizedBox(height: 12),
                            _buildFeatureRow('Weight carried and calories burned'),
                            const SizedBox(height: 12),
                            _buildFeatureRow('Automatic activity syncing'),
                            const SizedBox(height: 12),
                            _buildFeatureRow('Share with your fitness community'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Stats
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.insights,
                              color: Colors.blue[700],
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Users who connect Strava complete 50% more sessions in their first week',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: Colors.blue[700],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Action Buttons
              const SizedBox(height: 24),

              // Connect Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isConnecting || _isConnected ? null : _connectToStrava,
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
                      : _isConnected
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.check_circle, color: Colors.green[600]),
                                const SizedBox(width: 8),
                                Text(
                                  'Connected to Strava',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green[600],
                                  ),
                                ),
                              ],
                            )
                          : Image.asset(
                              'assets/images/btn_strava_connect_with_orange.png',
                              height: 56,
                              fit: BoxFit.contain,
                            ),
                ),
              ),

              // Skip Button
              if (!_isConnected)
                TextButton(
                  onPressed: _isConnecting ? null : _skipStrava,
                  child: Text(
                    'Skip for now',
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

  Widget _buildFeatureRow(String text) {
    return Row(
      children: [
        Icon(
          Icons.check_circle,
          color: AppColors.primary,
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.bodyMedium.copyWith(
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}