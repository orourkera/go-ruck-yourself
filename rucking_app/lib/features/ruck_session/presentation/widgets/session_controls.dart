import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import '../bloc/active_session_bloc.dart';

/// Reusable widget showing Pause/Resume and End Session buttons.
///
/// Delegates state changes to [ActiveSessionBloc] instead of handling
/// business logic locally in the screen.
class SessionControls extends StatelessWidget {
  const SessionControls({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ActiveSessionBloc, ActiveSessionState>(
      builder: (context, state) {
        if (state is! ActiveSessionRunning) {
          // Hide controls if session not running
          return const SizedBox.shrink();
        }

        final running = state as ActiveSessionRunning;
        final bloc = context.read<ActiveSessionBloc>();

        return Row(
          children: [
            // Pause / Resume
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  if (running.isPaused) {
                    bloc.add(const SessionResumed());
                  } else {
                    bloc.add(const SessionPaused());
                  }
                },
                icon: Icon(running.isPaused ? Icons.play_arrow : Icons.pause),
                label: Text(
                  running.isPaused ? 'RESUME' : 'PAUSE',
                  style: AppTextStyles.labelLarge.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            // End Session
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  bloc.add(const SessionCompleted());
                },
                icon: const Icon(Icons.stop),
                label: const Text(
                  'END SESSION',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
