import 'package:flutter/material.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

/// Overlay widget that shows current distance, pace, elapsed time, heart rate and calories.
class SessionStatsOverlay extends StatelessWidget {
  const SessionStatsOverlay({Key? key, required this.state}) : super(key: key);

  final ActiveSessionRunning state;

  String _format(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _StatTile(label: 'DIST', value: '${state.distanceKm.toStringAsFixed(2)} km'),
          _StatTile(label: 'PACE', value: state.pace.toStringAsFixed(1)),
          _StatTile(label: 'TIME', value: _format(Duration(seconds: state.elapsedSeconds))),
          if (state.latestHeartRate != null)
            _StatTile(label: 'HR', value: '${state.latestHeartRate} bpm'),
          _StatTile(label: 'CAL', value: state.calories.toStringAsFixed(0)),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary)),
        const SizedBox(height: 4),
        Text(value, style: AppTextStyles.titleLarge),
      ],
    );
  }
}
