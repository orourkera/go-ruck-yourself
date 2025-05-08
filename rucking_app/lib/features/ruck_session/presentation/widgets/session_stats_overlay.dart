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
              color: _calColor(state.calories.toDouble()),
            ),
            _StatTile(
              label: 'ELEV',
              value: '${state.elevationGain.toStringAsFixed(0)}/${state.elevationLoss.toStringAsFixed(0)} m',
            ),
            // Removed duplicate 'remaining' display from row layout

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
        color: _calColor(state.calories.toDouble()),
        icon: Icons.local_fire_department,
      ),
      _StatTile(
        label: 'Elevation',
        value: '+${state.elevationGain.toStringAsFixed(0)}/${state.elevationLoss.toStringAsFixed(0)}',
        icon: Icons.terrain,
      ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        const SizedBox(height: 16.0), 
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Time (big)
            Expanded(
                flex: 2,
                child: Row(
                  children: [
                    // Left half: Timer (centered)
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(height: 4),
                          Text(
                            _format(Duration(seconds: state.elapsedSeconds)),
                            style: AppTextStyles.timerDisplay.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                              fontSize: 36, // Changed to 36 to match HR value
                            ),
                          ),
                          if (state.plannedDuration != null && state.plannedDuration! > state.elapsedSeconds)
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text(
                                '${_format(Duration(seconds: state.plannedDuration! - state.elapsedSeconds))} remaining',
                                style: AppTextStyles.bodyMedium.copyWith(color: Colors.black54),
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Right half: Heart rate (centered)
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Removed extra vertical space here
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(Icons.favorite, color: Colors.red, size: 36),
                              SizedBox(width: 8),
                              // Removed Baseline widget for simpler vertical centering
                              Text(
                                state.latestHeartRate != null ? '${state.latestHeartRate}' : '--',
                                style: AppTextStyles.timerDisplay.copyWith(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 36,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            state.latestHeartRate != null 
                              ? 'BPM'
                              : '', 
                            style: AppTextStyles.labelSmall.copyWith(fontSize: 10, color: AppColors.primary)
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 0.0), 
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true, // Added shrinkWrap back
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.2, // Adjusted for taller tiles
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), 
          children: statTiles
              .map((tile) => Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
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
          Icon(icon, color: color ?? AppColors.primary, size: 18),
          const SizedBox(height: 2),
        ],
        Text(label.toUpperCase(), style: AppTextStyles.labelSmall.copyWith(fontSize: 11, color: AppColors.primary)),
        const SizedBox(height: 2),
        Text(value, style: AppTextStyles.titleLarge.copyWith(fontSize: 22, color: color)), 
      ],
    );
  }
}
