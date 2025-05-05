import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rucking_app/core/config/app_config.dart';
import 'package:rucking_app/core/utils/measurement_utils.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_session.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';

/// A card widget that displays session information
class SessionCard extends StatelessWidget {
  final RuckSession session;
  final VoidCallback onTap;
  final bool preferMetric;

  const SessionCard({
    Key? key,
    required this.session,
    required this.onTap, 
    this.preferMetric = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Format date
    final formattedDate = DateFormat('MMMM d, yyyy • h:mm a').format(session.startTime);
      
    // Format duration
    final hours = session.duration.inHours;
    final minutes = session.duration.inMinutes % 60;
    final durationText = hours > 0 
        ? '${hours}h ${minutes}m' 
        : '${minutes}m';
    
    // Format distance
    final distanceValue = MeasurementUtils.formatDistance(
      session.distance, 
      metric: preferMetric
    );
    
    // Format calories
    final calories = session.caloriesBurned.toString();
    
    // Format weight
    final weightDisplay = MeasurementUtils.formatWeight(
      session.ruckWeightKg, 
      metric: preferMetric
    );
    
    // Format elevation gain/loss: use final_elevation_gain/loss if available, otherwise fallback
    final elevationGain = session.finalElevationGain ?? session.elevationGain;
    final elevationLoss = session.finalElevationLoss ?? session.elevationLoss;
    final elevationDisplay = MeasurementUtils.formatElevationCompact(
      elevationGain,
      elevationLoss,
      metric: preferMetric,
    );
      
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                formattedDate,
                style: AppTextStyles.titleSmall.copyWith(
                  color: AppColors.textDarkSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildSessionStat(
                      Icons.timer,
                      'Duration',
                      durationText,
                    ),
                  ),
                  Expanded(
                    child: _buildSessionStat(
                      Icons.straighten,
                      'Distance',
                      distanceValue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildSessionStat(
                      Icons.local_fire_department,
                      'Calories',
                      calories,
                    ),
                  ),
                  Expanded(
                    child: _buildSessionStat(
                      Icons.terrain,
                      'Elevation',
                      elevationDisplay,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildSessionStat(
                      Icons.fitness_center,
                      'Weight',
                      weightDisplay,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildSessionStat(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: AppColors.primary,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textDarkSecondary,
                ),
              ),
              Text(
                value,
                style: AppTextStyles.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
