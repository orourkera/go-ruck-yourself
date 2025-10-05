import 'package:flutter/material.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/features/auth/presentation/screens/register_screen.dart';
import 'package:rucking_app/core/services/analytics_service.dart';

/// Dialog shown when browse-mode user tries to perform an action
class BrowseModeBlockerDialog extends StatelessWidget {
  final String action;
  final String actionDescription;

  const BrowseModeBlockerDialog({
    Key? key,
    required this.action,
    required this.actionDescription,
  }) : super(key: key);

  /// Show the browse mode blocker dialog
  static Future<void> show(
    BuildContext context, {
    required String action,
    String? actionDescription,
  }) {
    // Track blocked action
    AnalyticsService.trackBrowseActionBlocked(action: action);

    return showDialog<void>(
      context: context,
      builder: (context) => BrowseModeBlockerDialog(
        action: action,
        actionDescription: actionDescription ?? 'perform this action',
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
            Icon(
              Icons.lock_outline,
              size: 60,
              color: AppColors.primary,
            ),
            const SizedBox(height: 20),
            Text(
              'Sign Up Required',
              style: AppTextStyles.headlineMedium.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Create a free account to $actionDescription and unlock all features!',
              style: AppTextStyles.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  // Track conversion
                  AnalyticsService.trackBrowseConvertedToAccount(triggeredBy: action);

                  Navigator.of(context).pop();
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => RegisterScreen()),
                  );
                },
                child: Text(
                  'Create Free Account',
                  style: AppTextStyles.labelLarge.copyWith(color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(
                'Continue Browsing',
                style: TextStyle(color: AppColors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
