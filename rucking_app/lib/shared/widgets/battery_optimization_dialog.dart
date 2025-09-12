import 'package:flutter/material.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

class BatteryOptimizationDialog extends StatelessWidget {
  final VoidCallback onAllow;
  final VoidCallback onDeny;

  const BatteryOptimizationDialog({
    super.key,
    required this.onAllow,
    required this.onDeny,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(20),
        constraints: BoxConstraints(
          // Ensure the dialog never exceeds 80% of screen height
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF2A2A2A)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(40),
                ),
                child: Icon(
                  Icons.battery_saver,
                  size: 40,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 16),

              // Title
              Text(
                'Enable Background Tracking',
                style: AppTextStyles.headlineMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : AppColors.textDark,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // First paragraph
              Text(
                'Hey Rucker! We need some help with Android battery settings in order to effectively track your ruck sessions.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white70
                      : AppColors.textDarkSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // Second paragraph
              Text(
                'We optimize battery settings on our own. By allowing Ruck! to run in the background you won\'t lose GPS tracking while the app is in the background. Click Allow below to continue.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white70
                      : AppColors.textDarkSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Feature list
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF3A3A3A)
                      : AppColors.primary.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primary.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    _buildFeatureItem(
                      context,
                      Icons.location_on,
                      'Track your route accurately',
                      'Even when your phone screen is off',
                    ),
                    const SizedBox(height: 12),
                    _buildFeatureItem(
                      context,
                      Icons.timeline,
                      'Record distance & pace',
                      'Continuous GPS tracking for precise stats',
                    ),
                    const SizedBox(height: 12),
                    _buildFeatureItem(
                      context,
                      Icons.notifications_active,
                      'Session notifications',
                      'Get updates during your ruck session',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Instructions
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.orange.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.orange,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Next: Find "Ruck" in the list and tap "Don\'t optimize"',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: Colors.orange.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: onDeny,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                    ? Colors.white30
                                    : Colors.grey.shade300,
                          ),
                        ),
                      ),
                      child: Text(
                        'Not Now',
                        style: AppTextStyles.labelMedium.copyWith(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white70
                              : AppColors.textDarkSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: onAllow,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Continue',
                        style: AppTextStyles.labelMedium.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureItem(
      BuildContext context, IconData icon, String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(
            icon,
            size: 20,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : AppColors.textDark,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: AppTextStyles.bodySmall.copyWith(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white60
                      : AppColors.textDarkSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
