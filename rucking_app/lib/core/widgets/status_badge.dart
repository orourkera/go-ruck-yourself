import 'package:flutter/material.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

/// Widget for displaying status as a styled badge
class StatusBadge extends StatelessWidget {
  final String status;
  final bool compact;

  const StatusBadge({
    super.key,
    required this.status,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final config = _getStatusConfig(status);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: config.backgroundColor,
        borderRadius: BorderRadius.circular(compact ? 4 : 6),
        border: Border.all(
          color: config.borderColor,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (config.icon != null) ...[
            Icon(
              config.icon,
              size: compact ? 12 : 14,
              color: config.textColor,
            ),
            SizedBox(width: compact ? 2 : 4),
          ],
          Text(
            config.displayText,
            style: AppTextStyles.bodySmall.copyWith(
              color: config.textColor,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  _StatusConfig _getStatusConfig(String status) {
    switch (status.toLowerCase()) {
      case 'planned':
      case 'upcoming':
        return _StatusConfig(
          displayText: 'PLANNED',
          textColor: AppColors.info,
          backgroundColor: AppColors.info.withOpacity(0.1),
          borderColor: AppColors.info.withOpacity(0.3),
          icon: Icons.schedule,
        );
      case 'active':
      case 'in_progress':
        return _StatusConfig(
          displayText: 'ACTIVE',
          textColor: AppColors.success,
          backgroundColor: AppColors.success.withOpacity(0.1),
          borderColor: AppColors.success.withOpacity(0.3),
          icon: Icons.play_arrow,
        );
      case 'completed':
      case 'finished':
        return _StatusConfig(
          displayText: 'COMPLETED',
          textColor: AppColors.primary,
          backgroundColor: AppColors.primary.withOpacity(0.1),
          borderColor: AppColors.primary.withOpacity(0.3),
          icon: Icons.check_circle,
        );
      case 'cancelled':
      case 'canceled':
        return _StatusConfig(
          displayText: 'CANCELLED',
          textColor: AppColors.error,
          backgroundColor: AppColors.error.withOpacity(0.1),
          borderColor: AppColors.error.withOpacity(0.3),
          icon: Icons.cancel,
        );
      case 'postponed':
      case 'delayed':
        return _StatusConfig(
          displayText: 'POSTPONED',
          textColor: AppColors.warning,
          backgroundColor: AppColors.warning.withOpacity(0.1),
          borderColor: AppColors.warning.withOpacity(0.3),
          icon: Icons.pause_circle,
        );
      default:
        return _StatusConfig(
          displayText: status.toUpperCase(),
          textColor: AppColors.greyDark,
          backgroundColor: AppColors.greyLight.withOpacity(0.5),
          borderColor: AppColors.greyDark.withOpacity(0.3),
          icon: Icons.help_outline,
        );
    }
  }
}

class _StatusConfig {
  final String displayText;
  final Color textColor;
  final Color backgroundColor;
  final Color borderColor;
  final IconData? icon;

  const _StatusConfig({
    required this.displayText,
    required this.textColor,
    required this.backgroundColor,
    required this.borderColor,
    this.icon,
  });
}

/// Utility function to get status display text
String getStatusDisplayText(String? status) {
  if (status == null || status.isEmpty) {
    return 'Unknown';
  }

  switch (status.toLowerCase()) {
    case 'planned':
    case 'upcoming':
      return 'Planned';
    case 'active':
    case 'in_progress':
      return 'Active';
    case 'completed':
    case 'finished':
      return 'Completed';
    case 'cancelled':
    case 'canceled':
      return 'Cancelled';
    case 'postponed':
    case 'delayed':
      return 'Postponed';
    default:
      return status;
  }
}
