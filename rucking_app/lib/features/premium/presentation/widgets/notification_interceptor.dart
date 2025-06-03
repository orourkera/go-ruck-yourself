import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/premium/presentation/bloc/premium_bloc.dart';
import 'package:rucking_app/features/premium/presentation/bloc/premium_state.dart';
import 'package:rucking_app/features/premium/presentation/screens/premium_paywall_screen.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

/// Intercepts notification taps for free users and shows premium upsell instead
class NotificationInterceptor extends StatelessWidget {
  final String notificationType;
  final Map<String, dynamic> notificationData;
  final VoidCallback? onPremiumNavigation;
  final Widget? fallbackWidget;

  const NotificationInterceptor({
    Key? key,
    required this.notificationType,
    required this.notificationData,
    this.onPremiumNavigation,
    this.fallbackWidget,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PremiumBloc, PremiumState>(
      builder: (context, state) {
        if (state is PremiumLoaded && state.isPremium) {
          // Premium users get full access - execute the intended navigation
          if (onPremiumNavigation != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              onPremiumNavigation!();
            });
          }
          return fallbackWidget ?? const SizedBox.shrink();
        }

        // Free users see the engagement teaser instead
        return _buildEngagementTeaser(context);
      },
    );
  }

  Widget _buildEngagementTeaser(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceDark,
        title: Text(
          'Notification',
          style: AppTextStyles.titleMedium.copyWith(
            color: AppColors.textLight,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.close, color: AppColors.textLight),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Notification preview card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surfaceDark,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.primary.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  // Blurred avatar and notification content
                  Row(
                    children: [
                      // Blurred profile picture
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary.withOpacity(0.2),
                        ),
                        child: Icon(
                          Icons.person,
                          color: AppColors.primary.withOpacity(0.5),
                          size: 30,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _getNotificationTitle(),
                              style: AppTextStyles.bodyLarge.copyWith(
                                color: AppColors.textLight,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _getNotificationPreview(),
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.textLightSecondary,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Engagement stats (blurred/hidden)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.backgroundDark,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildBlurredStat('👍', '${notificationData['likeCount'] ?? '?'}', 'Likes'),
                        _buildBlurredStat('💬', '${notificationData['commentCount'] ?? '?'}', 'Comments'),
                        _buildBlurredStat('👥', '${notificationData['viewCount'] ?? '?'}', 'Views'),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Upgrade message
            Text(
              'See who\'s engaging with your rucks!',
              style: AppTextStyles.headlineSmall.copyWith(
                color: AppColors.textLight,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 16),

            Text(
              'Upgrade to premium to see who liked and commented on your sessions, and join the conversation!',
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
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => PremiumPaywallScreen(
                        featureTitle: 'Community Engagement',
                        featureDescription: 'See who\'s cheering you on and join the conversation with fellow ruckers.',
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Upgrade to Premium',
                  style: AppTextStyles.labelLarge.copyWith(
                    color: AppColors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlurredStat(String emoji, String count, String label) {
    return Column(
      children: [
        Text(
          emoji,
          style: const TextStyle(fontSize: 24),
        ),
        const SizedBox(height: 4),
        Text(
          count,
          style: AppTextStyles.bodyLarge.copyWith(
            color: AppColors.textLight,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textLightSecondary,
          ),
        ),
      ],
    );
  }

  String _getNotificationTitle() {
    switch (notificationType) {
      case 'like':
        return 'Someone liked your ruck!';
      case 'comment':
        return 'New comment on your ruck!';
      case 'follow':
        return 'You have a new follower!';
      case 'achievement':
        return 'Ruckers are celebrating your achievement!';
      default:
        return 'New community engagement!';
    }
  }

  String _getNotificationPreview() {
    switch (notificationType) {
      case 'like':
        return 'A fellow rucker appreciated your session. Tap to see who!';
      case 'comment':
        return '"${notificationData['commentPreview'] ?? 'Great work! How do you...'}" - Upgrade to reply';
      case 'follow':
        return 'Someone wants to follow your ruck journey!';
      case 'achievement':
        return 'The community is cheering you on for your latest milestone!';
      default:
        return 'Something exciting happened with your ruck session!';
    }
  }
}

/// Static helper for handling notification taps
class NotificationHandler {
  static void handleNotificationTap(
    BuildContext context, {
    required String notificationType,
    required Map<String, dynamic> notificationData,
    VoidCallback? onPremiumNavigation,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => NotificationInterceptor(
          notificationType: notificationType,
          notificationData: notificationData,
          onPremiumNavigation: onPremiumNavigation,
        ),
      ),
    );
  }
}