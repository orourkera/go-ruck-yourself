import 'package:flutter/material.dart';
import 'package:rucking_app/core/models/planned_ruck.dart';
import 'package:rucking_app/core/models/route.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/core/widgets/difficulty_badge.dart';
import 'package:rucking_app/core/widgets/status_badge.dart';

/// Card widget for displaying a planned ruck
class PlannedRuckCard extends StatelessWidget {
  final PlannedRuck plannedRuck;
  final VoidCallback? onTap;
  final VoidCallback? onStartPressed;
  final VoidCallback? onEditPressed;
  final VoidCallback? onDeletePressed;
  final bool isCompleted;

  const PlannedRuckCard({
    super.key,
    required this.plannedRuck,
    this.onTap,
    this.onStartPressed,
    this.onEditPressed,
    this.onDeletePressed,
    this.isCompleted = false,
  });

  @override
  Widget build(BuildContext context) {
    final route = plannedRuck.route;
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: _getBorderSide(),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          route?.name ?? 'Unnamed Route',
                          style: AppTextStyles.titleLarge.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          plannedRuck.formattedPlannedDate,
                          style: AppTextStyles.titleSmall.copyWith(
                            color: _getDateTextColor(),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  StatusBadge(status: plannedRuck.status.name),
                ],
              ),

              const SizedBox(height: 12),

              // Route details
              if (route != null) ...[
                Row(
                  children: [
                    if (route.trailDifficulty != null) ...[
                      DifficultyBadge(difficulty: route.trailDifficulty!),
                      const SizedBox(width: 8),
                    ],
                    Icon(
                      Icons.straighten,
                      size: 16,
                      color: AppColors.textDarkSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      route.formattedDistance,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textDarkSecondary,
                      ),
                    ),
                    if (route.elevationGainM != null) ...[
                      const SizedBox(width: 16),
                      Icon(
                        Icons.trending_up,
                        size: 16,
                        color: AppColors.textDarkSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        route.formattedElevationGain,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textDarkSecondary,
                        ),
                      ),
                    ],

                  ],
                ),
                const SizedBox(height: 8),
              ],

              // Location
              if (route?.source?.isNotEmpty == true) ...[
                Row(
                  children: [
                    Icon(
                      Icons.location_on,
                      size: 16,
                      color: AppColors.textDarkSecondary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Source: ${route?.source ?? 'Unknown'}',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textDarkSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],

              // Notes
              if (plannedRuck.notes?.isNotEmpty == true) ...[
                Text(
                  plannedRuck.notes!,
                  style: AppTextStyles.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
              ],

              // Progress indicator for in-progress rucks
              if (plannedRuck.status == PlannedRuckStatus.inProgress) ...[
                LinearProgressIndicator(
                  value: 0.0 / 100,
                  backgroundColor: AppColors.greyLight,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
                const SizedBox(height: 8),
                Text(
                  '${0.0.toInt()}% complete',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // Overdue warning
              if (plannedRuck.isOverdue) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.warning_rounded,
                        size: 16,
                        color: AppColors.error,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Overdue',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.error,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // Action buttons
              if (!isCompleted) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (onEditPressed != null)
                      TextButton.icon(
                        onPressed: onEditPressed,
                        icon: const Icon(Icons.edit, size: 16),
                        label: const Text('Edit'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textDarkSecondary,
                          minimumSize: const Size(0, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                    if (onDeletePressed != null) ...[
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: onDeletePressed,
                        icon: const Icon(Icons.delete, size: 16),
                        label: const Text('Delete'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.error,
                          minimumSize: const Size(0, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                    ],
                    if (onStartPressed != null) ...[
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: onStartPressed,
                        icon: const Icon(Icons.play_arrow, size: 16),
                        label: Text(_getStartButtonText()),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _getStartButtonColor(),
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                      ),
                    ],
                  ],
                ),
              ],

              // Completion info for completed rucks
              if (isCompleted && plannedRuck.completedAt != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 20,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Completed',
                              style: AppTextStyles.titleSmall.copyWith(
                                color: AppColors.success,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (plannedRuck.completedAt != null)
                              Text(
                                plannedRuck.completedAt?.toString() ?? 'N/A',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.success.withOpacity(0.8),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Get border side based on ruck status and urgency
  BorderSide _getBorderSide() {
    if (plannedRuck.isOverdue) {
      return BorderSide(color: AppColors.error.withOpacity(0.3), width: 2);
    }
    
    if (plannedRuck.isToday && plannedRuck.status == PlannedRuckStatus.planned) {
      return BorderSide(color: AppColors.warning.withOpacity(0.3), width: 2);
    }
    
    if (plannedRuck.status == PlannedRuckStatus.inProgress) {
      return BorderSide(color: AppColors.primary.withOpacity(0.3), width: 2);
    }
    
    return BorderSide.none;
  }

  /// Get date text color based on urgency
  Color _getDateTextColor() {
    if (plannedRuck.isOverdue) {
      return AppColors.error;
    }
    
    if (plannedRuck.isToday) {
      return AppColors.warning;
    }
    
    return AppColors.textDarkSecondary;
  }

  /// Get start button text based on status
  String _getStartButtonText() {
    switch (plannedRuck.status) {
      case PlannedRuckStatus.planned:
        return 'Start';
      case PlannedRuckStatus.inProgress:
        return 'Resume';
      case PlannedRuckStatus.planned:
        return 'Resume';
      default:
        return 'Start';
    }
  }

  /// Get start button color based on status and urgency
  Color _getStartButtonColor() {
    if (plannedRuck.isOverdue) {
      return AppColors.error;
    }
    
    if (plannedRuck.isToday) {
      return AppColors.warning;
    }
    
    return AppColors.primary;
  }
}
