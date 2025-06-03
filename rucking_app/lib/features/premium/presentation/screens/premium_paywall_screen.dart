import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/premium/presentation/bloc/premium_bloc.dart';
import 'package:rucking_app/features/premium/presentation/bloc/premium_event.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/custom_button.dart';

/// Premium paywall screen shown when free users try to access premium features
class PremiumPaywallScreen extends StatelessWidget {
  final String feature;
  final String description;

  const PremiumPaywallScreen({
    Key? key,
    required this.feature,
    required this.description,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Premium icon
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.star,
                  size: 60,
                  color: AppColors.primary,
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Feature title
              Text(
                'Unlock $feature',
                style: AppTextStyles.headlineLarge.copyWith(
                  color: AppColors.textLight,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 16),
              
              // Feature description
              Text(
                description,
                style: AppTextStyles.bodyLarge.copyWith(
                  color: AppColors.textLightSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 48),
              
              // Upgrade button
              CustomButton(
                text: 'Upgrade to Premium',
                onPressed: () {
                  context.read<PremiumBloc>().add(PurchasePremium());
                },
                color: AppColors.primary,
                textColor: AppColors.white,
              ),
              
              const SizedBox(height: 16),
              
              // Cancel button
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text(
                  'Maybe Later',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textLightSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}