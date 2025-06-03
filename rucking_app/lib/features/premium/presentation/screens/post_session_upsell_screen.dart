import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/premium/presentation/bloc/premium_bloc.dart';
import 'package:rucking_app/features/premium/presentation/bloc/premium_event.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_session.dart';
import 'package:rucking_app/core/utils/measurement_utils.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/custom_button.dart';

/// Post-session upsell screen shown to free users after completing a ruck session
class PostSessionUpsellScreen extends StatefulWidget {
  final RuckSession session;

  const PostSessionUpsellScreen({
    Key? key,
    required this.session,
  }) : super(key: key);

  @override
  State<PostSessionUpsellScreen> createState() => _PostSessionUpsellScreenState();
}

class _PostSessionUpsellScreenState extends State<PostSessionUpsellScreen> {
  int _countdown = 5;
  Timer? _timer;
  bool _canSkip = false;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _countdown--;
        if (_countdown <= 0) {
          _canSkip = true;
          timer.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              // Skip button (only shown after countdown)
              Align(
                alignment: Alignment.topRight,
                child: _canSkip
                    ? TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                          'Skip',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textLightSecondary,
                          ),
                        ),
                      )
                    : Text(
                        'Skip in $_countdown',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textLightSecondary,
                        ),
                      ),
              ),

              const Spacer(),

              // Celebration content
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Trophy icon
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.emoji_events,
                      size: 50,
                      color: AppColors.primary,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Congratulations
                  Text(
                    'Great Ruck!',
                    style: AppTextStyles.headlineLarge.copyWith(
                      color: AppColors.textLight,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 16),

                  // Session stats
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceDark,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        _buildStatRow(
                          'Distance',
                          MeasurementUtils.formatDistance(widget.session.distance, metric: true),
                        ),
                        const SizedBox(height: 8),
                        _buildStatRow(
                          'Duration',
                          MeasurementUtils.formatDuration(widget.session.duration),
                        ),
                        const SizedBox(height: 8),
                        _buildStatRow(
                          'Weight',
                          MeasurementUtils.formatWeight(widget.session.ruckWeightKg, metric: true),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Upsell message
                  Text(
                    'Want to see detailed analytics,\nconnect with other ruckers,\nand track your progress?',
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: AppColors.textLightSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 32),

                  // Premium benefits
                  _buildBenefitsList(),

                  const SizedBox(height: 32),

                  // Upgrade button
                  CustomButton(
                    text: 'Upgrade to Premium',
                    onPressed: () {
                      context.read<PremiumBloc>().add(PurchasePremium());
                    },
                    color: AppColors.primary,
                    textColor: AppColors.white,
                  ),
                ],
              ),

              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textLightSecondary,
          ),
        ),
        Text(
          value,
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textLight,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildBenefitsList() {
    final benefits = [
      'Detailed session analytics and charts',
      'Connect with the Ruck Buddies community',
      'See who liked and commented on your rucks',
      'Track your progress over time',
    ];

    return Column(
      children: benefits.map((benefit) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(
              Icons.check_circle,
              color: AppColors.primary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                benefit,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textLight,
                ),
              ),
            ),
          ],
        ),
      )).toList(),
    );
  }
}