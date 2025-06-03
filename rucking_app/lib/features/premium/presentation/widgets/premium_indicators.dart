import 'package:flutter/material.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';

/// Collection of premium visual indicators for the app
class PremiumIndicators {
  
  /// Crown icon for premium features
  static Widget crownIcon({
    double size = 20,
    Color? color,
  }) {
    return Icon(
      Icons.crown,
      size: size,
      color: color ?? AppColors.premium,
    );
  }

  /// Lock icon for disabled features
  static Widget lockIcon({
    double size = 20,
    Color? color,
  }) {
    return Icon(
      Icons.lock_outline,
      size: size,
      color: color ?? AppColors.textLightSecondary,
    );
  }

  /// Sparkle effect for premium content
  static Widget sparkleIcon({
    double size = 16,
    Color? color,
  }) {
    return Icon(
      Icons.auto_awesome,
      size: size,
      color: color ?? AppColors.premium,
    );
  }

  /// Premium badge widget
  static Widget premiumBadge({
    String text = 'PRO',
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.premium, AppColors.secondary],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// Gradient border for premium users' content
  static Widget gradientBorder({
    required Widget child,
    double borderWidth = 2,
    double borderRadius = 12,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: const LinearGradient(
          colors: [AppColors.premium, AppColors.secondary],
        ),
      ),
      child: Container(
        margin: EdgeInsets.all(borderWidth),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius - borderWidth),
          color: AppColors.surfaceDark,
        ),
        child: child,
      ),
    );
  }

  /// Animated shimmer effect for premium content
  static Widget shimmerEffect({
    required Widget child,
    Duration duration = const Duration(seconds: 2),
  }) {
    return _ShimmerWidget(
      duration: duration,
      child: child,
    );
  }

  /// Premium feature button with crown icon
  static Widget premiumButton({
    required String text,
    required VoidCallback onTap,
    bool isEnabled = true,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
  }) {
    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          gradient: isEnabled 
            ? const LinearGradient(colors: [AppColors.premium, AppColors.secondary])
            : null,
          color: !isEnabled ? AppColors.surfaceDark : null,
          borderRadius: BorderRadius.circular(12),
          border: !isEnabled ? Border.all(color: AppColors.textLightSecondary.withOpacity(0.3)) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isEnabled) ...[
              crownIcon(color: AppColors.white, size: 18),
              const SizedBox(width: 8),
            ] else ...[
              lockIcon(size: 18),
              const SizedBox(width: 8),
            ],
            Text(
              text,
              style: TextStyle(
                color: isEnabled ? AppColors.white : AppColors.textLightSecondary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Blurred overlay for locked content
  static Widget blurredOverlay({
    required Widget child,
    String? lockText,
    VoidCallback? onTap,
  }) {
    return Stack(
      children: [
        // Blurred background
        ColorFiltered(
          colorFilter: ColorFilter.mode(
            AppColors.backgroundDark.withOpacity(0.7),
            BlendMode.srcOver,
          ),
          child: child,
        ),
        
        // Lock overlay
        Positioned.fill(
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.backgroundDark.withOpacity(0.8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  lockIcon(size: 32, color: AppColors.textLight),
                  if (lockText != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      lockText,
                      style: const TextStyle(
                        color: AppColors.textLight,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// FOMO notification badge
  static Widget fomoNotificationBadge({
    required int count,
    String suffix = '',
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.error,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count$suffix',
        style: const TextStyle(
          color: AppColors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Shimmer animation widget for premium content
class _ShimmerWidget extends StatefulWidget {
  final Widget child;
  final Duration duration;

  const _ShimmerWidget({
    required this.child,
    required this.duration,
  });

  @override
  State<_ShimmerWidget> createState() => _ShimmerWidgetState();
}

class _ShimmerWidgetState extends State<_ShimmerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );
    _animation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_controller);
    
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.premium.withOpacity(0.3),
                AppColors.secondary.withOpacity(0.8),
                AppColors.premium.withOpacity(0.3),
              ],
              stops: [
                _animation.value - 0.3,
                _animation.value,
                _animation.value + 0.3,
              ].map((stop) => stop.clamp(0.0, 1.0)).toList(),
            ).createShader(bounds);
          },
          child: widget.child,
        );
      },
    );
  }
}

/// Extension to add premium indicators to any widget
extension PremiumIndicatorExtension on Widget {
  /// Adds a crown badge to the widget
  Widget withCrownBadge() {
    return Stack(
      children: [
        this,
        Positioned(
          top: 0,
          right: 0,
          child: PremiumIndicators.crownIcon(size: 16),
        ),
      ],
    );
  }

  /// Adds a lock overlay for non-premium users
  Widget withLockOverlay({String? lockText, VoidCallback? onTap}) {
    return PremiumIndicators.blurredOverlay(
      child: this,
      lockText: lockText,
      onTap: onTap,
    );
  }

  /// Adds gradient border for premium content
  Widget withPremiumBorder() {
    return PremiumIndicators.gradientBorder(child: this);
  }

  /// Adds shimmer effect
  Widget withShimmer() {
    return PremiumIndicators.shimmerEffect(child: this);
  }
}
