import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/premium/presentation/bloc/premium_bloc.dart';
import 'package:rucking_app/features/premium/presentation/bloc/premium_state.dart';
import 'package:rucking_app/features/premium/presentation/screens/premium_paywall_screen.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

/// Universal widget for gating premium features
/// Wraps any widget and shows paywall for free users
class PremiumGate extends StatelessWidget {
  final Widget child;
  final String feature;
  final Widget? lockedWidget;
  final String? lockedTitle;
  final String? lockedDescription;
  final VoidCallback? onLockTap;

  const PremiumGate({
    Key? key,
    required this.child,
    required this.feature,
    this.lockedWidget,
    this.lockedTitle,
    this.lockedDescription,
    this.onLockTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PremiumBloc, PremiumState>(
      builder: (context, state) {
        if (state is PremiumLoaded && state.isPremium) {
          return child;
        }

        // Show locked overlay for free users
        return lockedWidget ?? PremiumLockedOverlay(
          feature: feature,
          title: lockedTitle,
          description: lockedDescription,
          onUpgrade: onLockTap ?? () => _showUpgradeScreen(context),
        );
      },
    );
  }

  void _showUpgradeScreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PremiumPaywallScreen(
          featureTitle: lockedTitle ?? _getFeatureTitle(feature),
          featureDescription: lockedDescription ?? _getFeatureDescription(feature),
        ),
      ),
    );
  }

  String _getFeatureTitle(String feature) {
    switch (feature) {
      case 'stats':
      case 'analytics':
        return 'Advanced Analytics';
      case 'ruck_buddies':
      case 'community':
        return 'Ruck Community';
      case 'engagement':
      case 'likes':
      case 'comments':
        return 'Community Engagement';
      case 'sharing':
        return 'Advanced Sharing';
      default:
        return 'Premium Feature';
    }
  }

  String _getFeatureDescription(String feature) {
    switch (feature) {
      case 'stats':
      case 'analytics':
        return 'Get detailed insights into your ruck performance, trends, and progress tracking.';
      case 'ruck_buddies':
      case 'community':
        return 'Connect with fellow ruckers, find ruck buddies, and join group challenges.';
      case 'engagement':
      case 'likes':
      case 'comments':
        return 'See who\'s engaging with your sessions and join the conversation.';
      case 'sharing':
        return 'Share your achievements with advanced customization options.';
      default:
        return 'Unlock premium features to enhance your rucking experience.';
    }
  }
}

/// Locked overlay widget that shows when feature is gated
class PremiumLockedOverlay extends StatelessWidget {
  final String feature;
  final String? title;
  final String? description;
  final VoidCallback onUpgrade;

  const PremiumLockedOverlay({
    Key? key,
    required this.feature,
    this.title,
    this.description,
    required this.onUpgrade,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.backgroundDark.withOpacity(0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primary.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Stack(
        children: [
          // Blurred background effect
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primary.withOpacity(0.1),
                    AppColors.secondary.withOpacity(0.1),
                  ],
                ),
              ),
            ),
          ),

          // Lock content
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Crown/Lock icon
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary,
                          AppColors.secondary,
                        ],
                      ),
                    ),
                    child: const Icon(
                      Icons.crown,
                      color: AppColors.white,
                      size: 40,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Title
                  Text(
                    title ?? _getDefaultTitle(),
                    style: AppTextStyles.headlineSmall.copyWith(
                      color: AppColors.textLight,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 12),

                  // Description
                  Text(
                    description ?? _getDefaultDescription(),
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: AppColors.textLightSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 32),

                  // Upgrade button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: onUpgrade,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.crown,
                            color: AppColors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Upgrade to Premium',
                            style: AppTextStyles.labelLarge.copyWith(
                              color: AppColors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getDefaultTitle() {
    switch (feature) {
      case 'stats':
      case 'analytics':
        return 'Premium Analytics';
      case 'ruck_buddies':
      case 'community':
        return 'Join the Community';
      case 'engagement':
      case 'likes':
      case 'comments':
        return 'See Engagement';
      case 'sharing':
        return 'Advanced Sharing';
      default:
        return 'Premium Feature';
    }
  }

  String _getDefaultDescription() {
    switch (feature) {
      case 'stats':
      case 'analytics':
        return 'Unlock detailed analytics and performance insights';
      case 'ruck_buddies':
      case 'community':
        return 'Connect with fellow ruckers and join the community';
      case 'engagement':
      case 'likes':
      case 'comments':
        return 'See who\'s engaging with your sessions';
      case 'sharing':
        return 'Share your achievements with enhanced features';
      default:
        return 'Upgrade to access this premium feature';
    }
  }
}
