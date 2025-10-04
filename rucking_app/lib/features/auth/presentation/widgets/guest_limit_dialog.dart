import 'package:flutter/material.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/features/auth/presentation/screens/register_screen.dart';
import 'package:rucking_app/core/services/analytics_service.dart';
import 'package:rucking_app/features/auth/data/services/guest_session_service.dart';

/// Dialog shown when guest tries to start a 3rd ruck
/// Forces them to create an account to continue
class GuestLimitDialog extends StatelessWidget {
  const GuestLimitDialog({Key? key}) : super(key: key);

  /// Show the guest limit dialog
  static Future<void> show(BuildContext context) async {
    // Track that guest hit the limit
    final sessionCount = await GuestSessionService.getGuestSessionCount();
    AnalyticsService.trackEvent('guest_limit_reached', {
      'session_count': sessionCount,
      'timestamp': DateTime.now().toIso8601String(),
    });

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const GuestLimitDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Lock icon
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.lock_outline,
                size: 48,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(height: 24),

            // Title
            Text(
              'Trial Complete!',
              style: AppTextStyles.headlineMedium.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            // Message
            Text(
              'You\'ve completed 2 rucks as a guest. Create a free account to continue rucking and unlock all features!',
              style: AppTextStyles.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // What they'll get
            _buildBenefit(Icons.all_inclusive, 'Unlimited rucking'),
            const SizedBox(height: 12),
            _buildBenefit(Icons.people, 'Ruck buddies & social feed'),
            const SizedBox(height: 12),
            _buildBenefit(Icons.emoji_events, 'Achievements & leaderboards'),
            const SizedBox(height: 12),
            _buildBenefit(Icons.save, 'Save your 2 trial rucks + all future rucks'),
            const SizedBox(height: 32),

            // Sign Up button (primary action)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () async {
                  // Track conversion from limit
                  final count = await GuestSessionService.getGuestSessionCount();
                  AnalyticsService.trackGuestConvertedToAccount(migratedSessions: count);

                  Navigator.of(context).pop();
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => RegisterScreen(),
                    ),
                  );
                },
                child: Text(
                  'Create Free Account',
                  style: AppTextStyles.buttonText.copyWith(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // No back button - must sign up to continue
            Text(
              'Free forever. No credit card required.',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBenefit(IconData icon, String text) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: AppColors.primary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.bodyMedium,
          ),
        ),
      ],
    );
  }
}
