import 'package:flutter/material.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/core/utils/measurement_utils.dart';

/// Overlay widget that shows current distance, pace, elapsed time, heart rate and calories.
class SessionStatsOverlay extends StatelessWidget {
  const SessionStatsOverlay({Key? key, required this.state, required this.preferMetric, this.useCardLayout = false}) : super(key: key);

  final ActiveSessionRunning state;
  final bool preferMetric;
  final bool useCardLayout;

  String _format(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (!useCardLayout) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _StatTile(
              label: 'DIST',
              value: MeasurementUtils.formatDistance(state.distanceKm, metric: preferMetric),
            ),
            _StatTile(
              label: 'PACE',
              value: MeasurementUtils.formatPaceSeconds(state.pace * 60, metric: preferMetric),
            ),
            _StatTile(label: 'TIME', value: _format(Duration(seconds: state.elapsedSeconds))),
            if (state.latestHeartRate != null)
              _StatTile(
                label: 'HR',
                value: '${state.latestHeartRate} bpm',
                color: _hrColor(state.latestHeartRate!),
              ),
            _StatTile(
              label: 'CAL',
              value: state.calories.toStringAsFixed(0),
              color: _calColor(state.calories),
            ),
            _StatTile(
              label: 'ELEV',
              value: '${state.elevationGain.toStringAsFixed(0)}/${state.elevationLoss.toStringAsFixed(0)} m',
            ),
          ],
        ),
      );
    }
    // Card layout: 2x2 grid
    final List<_StatTile> statTiles = [
      _StatTile(
        label: 'Distance',
        value: MeasurementUtils.formatDistance(state.distanceKm, metric: preferMetric),
        icon: Icons.straighten,
      ),
      _StatTile(
        label: 'Pace',
        value: MeasurementUtils.formatPaceSeconds(state.pace * 60, metric: preferMetric),
        icon: Icons.speed,
      ),
      _StatTile(
        label: 'Calories',
        value: '${state.calories.toStringAsFixed(0)} KCAL',
        color: _calColor(state.calories),
        icon: Icons.local_fire_department,
      ),
      _StatTile(
        label: 'Elevation',
        value: '+${state.elevationGain.toStringAsFixed(0)}/${state.elevationLoss.toStringAsFixed(0)}',
        icon: Icons.terrain,
      ),
    ];
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Time (big)
            Expanded(
                flex: 2,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Timer and info (left)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _format(Duration(seconds: state.elapsedSeconds)),
                            style: AppTextStyles.timerDisplay.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                              fontSize: 48,
                            ),
                          ),
                          if (state.plannedDuration != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'REMAINING: ' + _format(Duration(seconds: (state.plannedDuration! - state.elapsedSeconds).clamp(0, state.plannedDuration!).toInt())),
                                style: AppTextStyles.statLabel.copyWith(color: Colors.grey[700]),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              preferMetric
                                  ? '${state.ruckWeightKg.toStringAsFixed(0)} KG'
                                  : '${(state.ruckWeightKg * 2.20462).toStringAsFixed(0)} LBS',
                              style: AppTextStyles.statLabel.copyWith(color: Colors.grey[700]),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Heart rate (right)
                    if (state.latestHeartRate != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 16.0, bottom: 4.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Icon(Icons.favorite, color: _hrColor(state.latestHeartRate!), size: 44),
                            Text(
                              '${state.latestHeartRate}',
                              style: AppTextStyles.timerDisplay.copyWith(
                                color: _hrColor(state.latestHeartRate!),
                                fontWeight: FontWeight.bold,
                                fontSize: 36,
                              ),
                            ),
                            Text(
                              'BPM',
                              style: AppTextStyles.labelLarge.copyWith(
                                color: _hrColor(state.latestHeartRate!),
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          physics: const NeverScrollableScrollPhysics(),
          children: statTiles
              .map((tile) => Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
                      child: tile,
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }

  Color _hrColor(int bpm) {
    if (bpm < 100) return AppColors.success;
    if (bpm < 140) return AppColors.warning;
    return AppColors.error;
  }

  Color _calColor(double cal) {
    if (cal < 100) return AppColors.warning;
    return Colors.white;
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, this.color, this.icon});

  final String label;
  final String value;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, color: color ?? AppColors.primary, size: 24),
          const SizedBox(height: 4),
        ],
        Text(label.toUpperCase(), style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary)),
        const SizedBox(height: 4),
        Text(value, style: AppTextStyles.titleLarge.copyWith(color: color)),
      ],
    );
  }
}
