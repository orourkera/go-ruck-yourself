import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/theme/app_text_styles.dart';
import '../../../../core/utils/measurement_utils.dart';

/// Dialog shown when user tries to start a new session but has an existing active session
class ActiveSessionDialog extends StatelessWidget {
  final Map<String, dynamic> activeSession;
  final VoidCallback onContinueExisting;
  final VoidCallback onForceNewSession;
  final VoidCallback onCancel;

  const ActiveSessionDialog({
    super.key,
    required this.activeSession,
    required this.onContinueExisting,
    required this.onForceNewSession,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final startedAt = activeSession['started_at'] as String?;
    final ruckWeight = activeSession['rucking_weight_kg'] as double?;
    
    final startedTime = startedAt != null 
        ? DateTime.tryParse(startedAt.replaceAll('Z', '+00:00'))
        : null;
    
    final duration = startedTime != null 
        ? DateTime.now().difference(startedTime)
        : null;
    
    final formattedWeight = ruckWeight != null && ruckWeight > 0
        ? MeasurementUtils.formatWeight(ruckWeight, metric: true)
        : 'Hike';

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: AppColors.warning,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Active Session Found',
              style: AppTextStyles.titleLarge.copyWith(
                color: AppColors.warning,
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You have an active ruck session that was started ${_formatDuration(duration)}.',
            style: AppTextStyles.bodyMedium,
          ),
          const SizedBox(height: 16),
          
          // Session details card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.warning.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.fitness_center_rounded,
                      size: 20,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formattedWeight,
                      style: AppTextStyles.labelLarge.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (startedTime != null) ...[
                  Row(
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 16,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Started ${DateFormat('MMM d, h:mm a').format(startedTime)}',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
                Row(
                  children: [
                    Icon(
                      Icons.timer_rounded,
                      size: 16,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Running for ${_formatDuration(duration)}',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          Text(
            'What would you like to do?',
            style: AppTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: onCancel,
          child: Text(
            'Cancel',
            style: AppTextStyles.labelLarge.copyWith(
              color: Colors.grey[600],
            ),
          ),
        ),
        TextButton(
          onPressed: onForceNewSession,
          child: Text(
            'End & Start New',
            style: AppTextStyles.labelLarge.copyWith(
              color: AppColors.warning,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: onContinueExisting,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          child: Text(
            'Continue Session',
            style: AppTextStyles.labelLarge.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return 'some time ago';
    
    if (duration.inMinutes < 1) {
      return 'just now';
    } else if (duration.inHours < 1) {
      return '${duration.inMinutes} minute${duration.inMinutes == 1 ? '' : 's'} ago';
    } else {
      final hours = duration.inHours;
      final minutes = duration.inMinutes % 60;
      
      if (minutes == 0) {
        return '$hours hour${hours == 1 ? '' : 's'} ago';
      } else {
        return '${hours}h ${minutes}m ago';
      }
    }
  }
}
