import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rucking_app/core/config/app_config.dart';
import 'package:rucking_app/core/config/social_feature_toggles.dart';
import 'package:rucking_app/core/utils/measurement_utils.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_session.dart';
import 'package:rucking_app/features/social_sharing/screens/share_preview_screen.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/widgets/stat_row.dart';

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
    // Format date - use MeasurementUtils to ensure consistent timezone handling
    final formattedDate =
        '${MeasurementUtils.formatDate(session.startTime)} • ${MeasurementUtils.formatTime(session.startTime)}';

    // Format duration
    final hours = session.duration.inHours;
    final minutes = session.duration.inMinutes % 60;
    final durationText = hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';

    // Format distance
    final distanceValue =
        MeasurementUtils.formatDistance(session.distance, metric: preferMetric);

    // Format calories as whole numbers for display
    final calories = session.caloriesBurned.round().toString();

    // Format weight
    final weightDisplay = MeasurementUtils.formatWeight(session.ruckWeightKg,
        metric: preferMetric);

    // Format elevation gain/loss: use finalElevationGain/finalElevationLoss if available, otherwise fallback to elevationGain/elevationLoss, then 0.0
    final elevationGain =
        session.finalElevationGain ?? session.elevationGain ?? 0.0;
    final elevationLoss =
        session.finalElevationLoss ?? session.elevationLoss ?? 0.0;
    final elevationDisplay = MeasurementUtils.formatElevationCompact(
      elevationGain,
      elevationLoss,
      metric: preferMetric,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      color:
          Theme.of(context).brightness == Brightness.dark ? Colors.black : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: Theme.of(context).brightness == Brightness.dark
            ? BorderSide(color: Theme.of(context).primaryColor, width: 1)
            : BorderSide.none,
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
                    child: StatRow(
                      icon: Icons.timer,
                      label: 'Duration',
                      value: durationText,
                    ),
                  ),
                  Expanded(
                    child: StatRow(
                      icon: Icons.straighten,
                      label: 'Distance',
                      value: distanceValue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: StatRow(
                      icon: Icons.local_fire_department,
                      label: 'Calories',
                      value: calories,
                    ),
                  ),
                  Expanded(
                    child: StatRow(
                      icon: Icons.terrain,
                      label: 'Elevation',
                      value: elevationDisplay,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: StatRow(
                      icon: Icons.fitness_center,
                      label: 'Weight',
                      value: weightDisplay,
                    ),
                  ),
                  if (SocialFeatureToggles.instagramSharingEnabled)
                    IconButton(
                      icon: Icon(
                        Icons.share,
                        color: Theme.of(context).primaryColor,
                      ),
                      onPressed: () {
                        if (session.id == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Session not ready for sharing yet.')),
                          );
                          return;
                        }
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => SharePreviewScreen(
                              sessionId: session.id!,
                            ),
                          ),
                        );
                      },
                      tooltip: 'Share Session',
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
