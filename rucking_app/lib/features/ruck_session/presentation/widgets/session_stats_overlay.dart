import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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

  String _formatMinutesSeconds(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _formatHoursMinutesSeconds(Duration d) {
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
              value: state.pace != null ? MeasurementUtils.formatDistance(state.distanceKm, metric: preferMetric) : '--',
            ),
            _StatTile(
              label: 'PACE',
              value: state.pace != null ? MeasurementUtils.formatPaceSeconds(state.pace!, metric: preferMetric) : '--',
            ),
            _ElapsedTimeDisplay(isCardLayout: false),
            _HeartRateTile(preferMetric: preferMetric, isCardLayout: false),
            _StatTile(
              label: 'CAL',
              value: state.calories.toStringAsFixed(0),
              color: _calColor(state.calories.toDouble()),
            ),
            _StatTile(
              label: 'ELEV',
              value: '${state.elevationGain.toStringAsFixed(0)}/${state.elevationLoss.toStringAsFixed(0)} m',
            ),
          ],
        ),
      );
    }
    final List<_StatTile> statTiles = [
      _StatTile(
        label: 'Distance',
        value: MeasurementUtils.formatDistance(state.distanceKm, metric: preferMetric),
        icon: Icons.straighten,
      ),
      _StatTile(
        label: 'Pace',
        value: state.pace != null ? MeasurementUtils.formatPaceSeconds(state.pace!, metric: preferMetric) : '--',
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
        const SizedBox(height: 8.0),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _ElapsedTimeDisplay(isCardLayout: true, textStyle: AppTextStyles.timerDisplay.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
                          fontSize: 36,
                        )),
                        if (state.plannedDuration != null && state.plannedDuration! > state.elapsedSeconds)
                          Padding(
                            padding: const EdgeInsets.only(top: 2.0),
                            child: Center(
                              child: Text(
                                '${_formatMinutesSeconds(Duration(seconds: state.plannedDuration! - state.elapsedSeconds))} remaining',
                                style: AppTextStyles.bodyMedium.copyWith(color: Colors.black54, fontSize: 15),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.favorite,
                              color: Colors.red,
                              size: 36,
                            ),
                            const SizedBox(width: 8),
                            _HeartRateTile(preferMetric: preferMetric, isCardLayout: true),
                          ],
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
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.2,
          mainAxisSpacing: 4,
          crossAxisSpacing: 8,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 5),
          children: statTiles
              .map((tile) => Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
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
    return AppColors.primary;
  }

  static Widget placeholder() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: const [
          _PlaceholderTile(label: 'DIST'),
          _PlaceholderTile(label: 'PACE'),
          _PlaceholderTile(label: 'TIME'),
          _PlaceholderTile(label: 'HR'),
          _PlaceholderTile(label: 'CAL'),
          _PlaceholderTile(label: 'ELEV'),
        ],
      ),
    );
  }
}

class _PlaceholderTile extends StatelessWidget {
  const _PlaceholderTile({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label, style: AppTextStyles.labelSmall.copyWith(color: Colors.black45)),
        const SizedBox(height: 4),
        const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, this.color, this.icon, this.isHealthKit = false});

  final String label;
  final String value;
  final Color? color;
  final IconData? icon;
  final bool isHealthKit;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          isHealthKit ? 
          // If it's HealthKit data, show the health icon badge
          Stack(
            children: [
              Icon(icon, color: color ?? AppColors.primary, size: 18),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  padding: const EdgeInsets.all(1),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey.shade300, width: 0.5),
                  ),
                  child: const Icon(
                    Icons.medical_services,
                    color: Colors.green,
                    size: 8,
                  ),
                ),
              ),
            ],
          ) :
          Icon(icon, color: color ?? AppColors.primary, size: 18),
          const SizedBox(height: 2),
        ],
        // Add a small medical icon for HealthKit if no primary icon
        if (icon == null && isHealthKit) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label.toUpperCase(), style: AppTextStyles.labelSmall.copyWith(fontSize: 11, color: AppColors.primary)),
              const SizedBox(width: 2),
              Container(
                padding: const EdgeInsets.all(1),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const Icon(
                  Icons.medical_services,
                  color: Colors.white,
                  size: 8,
                ),
              ),
            ],
          ),
        ] else ...[
          Text(label.toUpperCase(), style: AppTextStyles.labelSmall.copyWith(fontSize: 11, color: AppColors.primary)),
        ],
        const SizedBox(height: 2),
        Text(value, style: AppTextStyles.titleLarge.copyWith(fontSize: 22, color: color)),
      ],
    );
  }
}

class _HeartRateTile extends StatelessWidget {
  final bool preferMetric;
  final bool isCardLayout;

  const _HeartRateTile({Key? key, required this.preferMetric, this.isCardLayout = false}) : super(key: key);

  Color _determineHrColor(int bpm) {
    if (bpm < 100) return AppColors.success;
    if (bpm < 140) return AppColors.warning;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    return BlocSelector<ActiveSessionBloc, ActiveSessionState, int?>(
      selector: (state) {
        if (state is ActiveSessionRunning) {
          return state.latestHeartRate;
        }
        return null;
      },
      builder: (context, latestHeartRate) {
        final int currentBpm = latestHeartRate ?? 0;
        if (!isCardLayout) {
          if (currentBpm > 0) {
            return _StatTile(
              label: 'HR',
              value: '$currentBpm bpm',
              color: _determineHrColor(currentBpm),
            );
          }
          return const SizedBox.shrink();
        }
        return Text(
          currentBpm > 0 ? '$currentBpm' : '--',
          style: AppTextStyles.timerDisplay.copyWith(
            color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 36,
          ),
        );
      },
    );
  }
}

class _ElapsedTimeDisplay extends StatelessWidget {
  final bool isCardLayout;
  final TextStyle? textStyle;

  const _ElapsedTimeDisplay({Key? key, required this.isCardLayout, this.textStyle}) : super(key: key);

  String _formatDuration(Duration duration, bool forCard) {
    if (forCard) {
      String twoDigits(int n) => n.toString().padLeft(2, '0');
      String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
      String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
      if (duration.inHours > 0) {
        return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
      }
      return "$twoDigitMinutes:$twoDigitSeconds";
    } else {
      String twoDigits(int n) => n.toString().padLeft(2, "0");
      String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
      String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
      if (duration.inHours > 0) {
        return "${duration.inHours}:$twoDigitMinutes:$twoDigitSeconds";
      } else {
        return "${duration.inMinutes}:$twoDigitSeconds";
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocSelector<ActiveSessionBloc, ActiveSessionState, int>(
      selector: (state) {
        if (state is ActiveSessionRunning) {
          return state.elapsedSeconds;
        }
        return 0;
      },
      builder: (context, elapsedSeconds) {
        final formattedTime = _formatDuration(Duration(seconds: elapsedSeconds), isCardLayout);
        if (!isCardLayout) {
          return _StatTile(label: 'TIME', value: formattedTime);
        }
        return Text(
          formattedTime,
          style: textStyle ?? AppTextStyles.timerDisplay.copyWith(
            color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 36,
          ),
        );
      },
    );
  }
}
