import 'package:flutter/material.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/features/auth/presentation/screens/register_screen.dart';
import 'package:rucking_app/core/services/analytics_service.dart';
import 'package:rucking_app/features/auth/data/services/guest_session_service.dart';

/// Dialog shown to guest users after completing their first ruck,
/// encouraging them to create an account to save their progress
class GuestConversionDialog extends StatelessWidget {
  final VoidCallback? onContinueAsGuest;

  const GuestConversionDialog({
    Key? key,
    this.onContinueAsGuest,
  }) : super(key: key);

  /// Show the guest conversion dialog
  static Future<bool?> show(
    BuildContext context, {
    VoidCallback? onContinueAsGuest,
  }) async {
    // Track prompt shown
    final sessionCount = await GuestSessionService.getGuestSessionCount();
    AnalyticsService.trackGuestConversionPromptShown(sessionCount: sessionCount);

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => GuestConversionDialog(
        onContinueAsGuest: onContinueAsGuest,
      ),
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
            // Celebration icon
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.celebration,
                size: 48,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),

            // Title
            Text(
              'Great First Ruck!',
              style: AppTextStyles.headlineMedium.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            // Message
            Text(
              'Create a free account to unlock the full rucking experience!',
              style: AppTextStyles.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Benefits list
            _buildBenefit(Icons.people, 'See and interact with ruck buddies'),
            const SizedBox(height: 12),
            _buildBenefit(Icons.favorite, 'Like & comment on rucks'),
            const SizedBox(height: 12),
            _buildBenefit(Icons.local_fire_department, 'Precise calorie tracking (with gender/age)'),
            const SizedBox(height: 12),
            _buildBenefit(Icons.emoji_events, 'Earn achievements & compete'),
            const SizedBox(height: 12),
            _buildBenefit(Icons.save, 'Save & track all your rucks'),
            const SizedBox(height: 32),

            // Sign Up button
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
                  // Track conversion
                  final count = await GuestSessionService.getGuestSessionCount();
                  AnalyticsService.trackGuestConvertedToAccount(migratedSessions: count);

                  Navigator.of(context).pop(true); // Return true = user chose to sign up
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => RegisterScreen(),
                    ),
                  );
                },
                child: Text(
                  'Sign Up Now',
                  style: AppTextStyles.buttonText.copyWith(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Continue as guest button
            TextButton(
              onPressed: () async {
                // Track that they chose to stay as guest
                final count = await GuestSessionService.getGuestSessionCount();
                AnalyticsService.trackGuestContinuedAsGuest(sessionCount: count);

                Navigator.of(context).pop(false); // Return false = continue as guest
                onContinueAsGuest?.call();
              },
              child: Text(
                'Continue as Guest',
                style: TextStyle(
                  color: AppColors.grey,
                  fontSize: 14,
                ),
              ),
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
