import 'package:flutter/material.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/core/utils/measurement_utils.dart';

/// Widget that shows AI coaching plan recommendations for the current session
class PlanSessionRecommendations extends StatelessWidget {
  /// Current coaching plan data
  final Map<String, dynamic>? coachingPlan;
  
  /// Next recommended session details
  final Map<String, dynamic>? nextSession;
  
  /// Whether user prefers metric units
  final bool preferMetric;
  
  /// Callback when user taps "Use Recommended" button
  final VoidCallback? onUseRecommended;

  const PlanSessionRecommendations({
    Key? key,
    this.coachingPlan,
    this.nextSession,
    required this.preferMetric,
    this.onUseRecommended,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Only show if user has an active coaching plan with next session details
    if (coachingPlan == null || nextSession == null) {
      return const SizedBox.shrink();
    }

    final planName = coachingPlan!['name'] as String? ?? 'Your Plan';
    final weekNumber = coachingPlan!['current_week'] as int? ?? 1;
    final totalWeeks = coachingPlan!['duration_weeks'] as int? ?? 8;
    final phase = coachingPlan!['phase'] as String? ?? 'Base Building';
    
    final sessionType = nextSession!['type'] as String? ?? 'Base Ruck';
    final distanceKm = nextSession!['distance_km'] as double?;
    final durationMinutes = nextSession!['duration_minutes'] as int?;
    final recommendedWeightKg = nextSession!['weight_kg'] as double?;
    final notes = nextSession!['notes'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with plan context
          Row(
            children: [
              Icon(
                Icons.psychology,
                color: AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$planName · Week $weekNumber/$totalWeeks',
                  style: AppTextStyles.labelLarge.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$phase Phase',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 12),
          
          // Session recommendation
          Text(
            'Recommended Session: $sessionType',
            style: AppTextStyles.titleSmall.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          
          // Session details
          _buildRecommendationDetails(
            distanceKm: distanceKm,
            durationMinutes: durationMinutes,
            recommendedWeightKg: recommendedWeightKg,
            notes: notes,
          ),
          
          const SizedBox(height: 16),
          
          // Action button
          if (onUseRecommended != null)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onUseRecommended,
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('Use Recommended Settings'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRecommendationDetails({
    double? distanceKm,
    int? durationMinutes,
    double? recommendedWeightKg,
    String? notes,
  }) {
    final List<Widget> details = [];

    // Distance
    if (distanceKm != null && distanceKm > 0) {
      final distance = preferMetric 
          ? '${distanceKm.toStringAsFixed(1)} km'
          : '${MeasurementUtils.kmToMiles(distanceKm).toStringAsFixed(1)} miles';
      details.add(_buildDetailChip(Icons.straighten, 'Distance: $distance'));
    }

    // Duration
    if (durationMinutes != null && durationMinutes > 0) {
      final duration = durationMinutes >= 60 
          ? '${(durationMinutes / 60).floor()}h ${durationMinutes % 60}m'
          : '${durationMinutes}m';
      details.add(_buildDetailChip(Icons.schedule, 'Target: $duration'));
    }

    // Weight
    if (recommendedWeightKg != null && recommendedWeightKg > 0) {
      final weight = preferMetric
          ? '${recommendedWeightKg.toStringAsFixed(0)} kg'
          : '${MeasurementUtils.kgToLbs(recommendedWeightKg).toStringAsFixed(0)} lbs';
      details.add(_buildDetailChip(Icons.fitness_center, 'Weight: $weight'));
    }

    // Notes
    if (notes != null && notes.trim().isNotEmpty) {
      details.add(
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.background.withOpacity(0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.lightbulb_outline,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  notes,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (details.isEmpty) {
      return Text(
        'Follow your plan guidelines',
        style: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textSecondary,
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: details,
    );
  }

  Widget _buildDetailChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.background.withOpacity(0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.border.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: AppColors.primary,
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: AppTextStyles.bodySmall.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}