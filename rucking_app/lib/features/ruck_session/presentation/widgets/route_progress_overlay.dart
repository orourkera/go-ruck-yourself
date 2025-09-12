import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/theme/app_text_styles.dart';
import '../../../../core/utils/measurement_utils.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';

/// Widget that displays route navigation progress during an active ruck session
class RouteProgressOverlay extends StatelessWidget {
  final double? plannedRouteDistance; // Total planned distance in km
  final int? plannedRouteDuration; // Total planned duration in minutes
  final double currentDistance; // Current distance traveled in km
  final int elapsedSeconds; // Current elapsed time in seconds

  const RouteProgressOverlay({
    Key? key,
    required this.plannedRouteDistance,
    required this.plannedRouteDuration,
    required this.currentDistance,
    required this.elapsedSeconds,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Only show if we have planned route data
    if (plannedRouteDistance == null || plannedRouteDistance! <= 0) {
      return const SizedBox.shrink();
    }

    // Get user preferences for units
    bool preferMetric = true;
    try {
      final authState = context.read<AuthBloc>().state;
      if (authState is Authenticated) {
        preferMetric = authState.user.preferMetric ?? true;
      }
    } catch (e) {
      // Default to metric if we can't get user preference
      preferMetric = true;
    }

    final distanceRemaining = (plannedRouteDistance! - currentDistance)
        .clamp(0.0, plannedRouteDistance!);
    final elapsedMinutes = elapsedSeconds / 60;

    // Calculate time remaining (estimate if no planned duration)
    final double timeRemaining;
    if (plannedRouteDuration != null) {
      timeRemaining = (plannedRouteDuration! - elapsedMinutes)
          .clamp(0.0, plannedRouteDuration!.toDouble());
    } else {
      // Estimate remaining time based on current pace
      if (currentDistance > 0 && elapsedMinutes > 0) {
        final currentPaceMinutesPerKm = elapsedMinutes / currentDistance;
        timeRemaining = (distanceRemaining / currentPaceMinutesPerKm)
            .clamp(0.0, double.infinity);
      } else {
        timeRemaining = 0.0;
      }
    }

    final progressPercentage =
        (currentDistance / plannedRouteDistance!).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.backgroundLight.withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.greyLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Progress bar
          Row(
            children: [
              Icon(
                Icons.route,
                size: 16,
                color: AppColors.textDarkSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: LinearProgressIndicator(
                  value: progressPercentage,
                  backgroundColor: AppColors.greyLight,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                  minHeight: 6,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(progressPercentage * 100).toStringAsFixed(0)}%',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textDarkSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Distance and time remaining
          Row(
            children: [
              // Distance remaining
              Expanded(
                child: _buildProgressItem(
                  icon: Icons.straighten,
                  label: 'Remaining',
                  value: MeasurementUtils.formatDistance(distanceRemaining,
                      metric: preferMetric),
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 16),

              // Time remaining
              Expanded(
                child: _buildProgressItem(
                  icon: Icons.schedule,
                  label: 'ETA',
                  value: _formatTimeRemaining(timeRemaining),
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textDarkSecondary,
                  fontSize: 11,
                ),
              ),
              Text(
                value,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textDark,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatTimeRemaining(double minutes) {
    if (minutes <= 0) return '0m';

    final totalMinutes = minutes.round();
    if (totalMinutes < 60) {
      return '${totalMinutes}m';
    }

    final hours = totalMinutes ~/ 60;
    final remainingMinutes = totalMinutes % 60;
    return '${hours}h ${remainingMinutes}m';
  }
}
