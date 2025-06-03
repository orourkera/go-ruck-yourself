import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/premium/presentation/bloc/premium_bloc.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/custom_button.dart';

/// Universal premium feature gate widget
/// Shows locked overlay for free users and allows access for premium users
class PremiumGate extends StatelessWidget {
  final Widget child;
  final String feature;
  final String description;
  final VoidCallback? onUpgradePressed;

  const PremiumGate({
    super.key,
    required this.child,
    required this.feature,
    required this.description,
    this.onUpgradePressed,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PremiumBloc, PremiumState>(
      builder: (context, state) {
        if (state is PremiumLoadedState && state.status.isActive) {
          // Premium user - show content
          return child;
        }
        
        // Free user - show gate
        return _PremiumLockedOverlay(
          child: child,
          feature: feature,
          description: description,
          onUpgradePressed: onUpgradePressed ?? () => _showPremiumPaywall(context),
        );
      },
    );
  }

  void _showPremiumPaywall(BuildContext context) {
    Navigator.pushNamed(
      context,
      '/premium-paywall',
      arguments: {
        'source': 'premium_gate',
        'feature': feature,
      },
    );
  }
}

/// Locked overlay widget for premium features
class _PremiumLockedOverlay extends StatelessWidget {
  final Widget child;
  final String feature;
  final String description;
  final VoidCallback onUpgradePressed;

  const _PremiumLockedOverlay({
    required this.child,
    required this.feature,
    required this.description,
    required this.onUpgradePressed,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Blurred/dimmed content
        ColorFiltered(
          colorFilter: ColorFilter.mode(
            AppColors.backgroundDark.withValues(alpha: 0.3),
            BlendMode.srcOver,
          ),
          child: Opacity(
            opacity: 0.3,
            child: child,
          ),
        ),
        
        // Lock overlay
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.backgroundDark.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Lock icon with premium styling
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [AppColors.premium, AppColors.secondary],
                    ),
                  ),
                  child: Icon(
                    Icons.workspace_premium,
                    size: 40,
                    color: AppColors.white,
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Feature title
                Text(
                  'Premium Feature',
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.textLight,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                
                const SizedBox(height: 8),
                
                // Feature description
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    description,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textLightSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // Upgrade button
                _buildUpgradeButton(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUpgradeButton() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.premium, AppColors.secondary],
        ),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onUpgradePressed,
          borderRadius: BorderRadius.circular(25),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.workspace_premium,
                  size: 20,
                  color: AppColors.white,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Upgrade to Premium',
                  style: TextStyle(
                    color: AppColors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
