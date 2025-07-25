import 'package:flutter/material.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

/// Banner widget to display urgent rucks (overdue and today's rucks)
class UrgentRucksBanner extends StatelessWidget {
  final int overdueCount;
  final int todayCount;
  final VoidCallback? onTap;
  final bool showDismiss;
  final VoidCallback? onDismiss;

  const UrgentRucksBanner({
    super.key,
    required this.overdueCount,
    required this.todayCount,
    this.onTap,
    this.showDismiss = false,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    if (overdueCount == 0 && todayCount == 0) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.all(16),
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: _getGradient(),
            ),
            child: Row(
              children: [
                // Icon
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _getIcon(),
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),

                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getTitle(),
                        style: AppTextStyles.subtitle1.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _getMessage(),
                        style: AppTextStyles.body2.copyWith(
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ],
                  ),
                ),

                // Action button or dismiss
                if (showDismiss && onDismiss != null)
                  IconButton(
                    onPressed: onDismiss,
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 20,
                    ),
                    tooltip: 'Dismiss',
                  )
                else
                  Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.white.withOpacity(0.8),
                    size: 16,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  LinearGradient _getGradient() {
    if (overdueCount > 0) {
      return LinearGradient(
        colors: [
          AppColors.error,
          AppColors.error.withOpacity(0.8),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    } else {
      return LinearGradient(
        colors: [
          AppColors.warning,
          AppColors.warning.withOpacity(0.8),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }
  }

  IconData _getIcon() {
    if (overdueCount > 0) {
      return Icons.warning_rounded;
    } else {
      return Icons.today_rounded;
    }
  }

  String _getTitle() {
    if (overdueCount > 0 && todayCount > 0) {
      return 'Urgent Rucks';
    } else if (overdueCount > 0) {
      return 'Overdue Rucks';
    } else {
      return 'Today\'s Rucks';
    }
  }

  String _getMessage() {
    if (overdueCount > 0 && todayCount > 0) {
      return '$overdueCount overdue, $todayCount planned for today';
    } else if (overdueCount > 0) {
      final plural = overdueCount > 1 ? 'rucks are' : 'ruck is';
      return '$overdueCount $plural overdue';
    } else {
      final plural = todayCount > 1 ? 'rucks' : 'ruck';
      return '$todayCount $plural planned for today';
    }
  }
}

/// Compact version of the urgent rucks banner
class CompactUrgentRucksBanner extends StatelessWidget {
  final int urgentCount;
  final String message;
  final VoidCallback? onTap;
  final Color? backgroundColor;

  const CompactUrgentRucksBanner({
    super.key,
    required this.urgentCount,
    required this.message,
    this.onTap,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    if (urgentCount == 0) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: backgroundColor ?? AppColors.warning.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: backgroundColor ?? AppColors.warning,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.warning_rounded,
                size: 16,
                color: backgroundColor ?? AppColors.warning,
              ),
              const SizedBox(width: 6),
              Text(
                message,
                style: AppTextStyles.caption.copyWith(
                  color: backgroundColor ?? AppColors.warning,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 12,
                  color: (backgroundColor ?? AppColors.warning).withOpacity(0.7),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Animated banner that can slide in/out
class AnimatedUrgentRucksBanner extends StatefulWidget {
  final int overdueCount;
  final int todayCount;
  final VoidCallback? onTap;
  final VoidCallback? onDismiss;
  final Duration animationDuration;

  const AnimatedUrgentRucksBanner({
    super.key,
    required this.overdueCount,
    required this.todayCount,
    this.onTap,
    this.onDismiss,
    this.animationDuration = const Duration(milliseconds: 300),
  });

  @override
  State<AnimatedUrgentRucksBanner> createState() => _AnimatedUrgentRucksBannerState();
}

class _AnimatedUrgentRucksBannerState extends State<AnimatedUrgentRucksBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;
  bool _isDismissed = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    );
    
    _slideAnimation = Tween<double>(
      begin: -1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));

    if (_shouldShow()) {
      _animationController.forward();
    }
  }

  @override
  void didUpdateWidget(AnimatedUrgentRucksBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (_shouldShow() && !_isDismissed) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  bool _shouldShow() {
    return widget.overdueCount > 0 || widget.todayCount > 0;
  }

  void _dismiss() {
    setState(() {
      _isDismissed = true;
    });
    _animationController.reverse().then((_) {
      widget.onDismiss?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_shouldShow() || _isDismissed) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _slideAnimation.value * 100),
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: UrgentRucksBanner(
              overdueCount: widget.overdueCount,
              todayCount: widget.todayCount,
              onTap: widget.onTap,
              showDismiss: true,
              onDismiss: _dismiss,
            ),
          ),
        );
      },
    );
  }
}
