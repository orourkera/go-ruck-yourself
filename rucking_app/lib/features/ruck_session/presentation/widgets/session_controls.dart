import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';


/// Reusable widget showing Pause/Resume and End Session buttons.
///
/// Delegates state changes to [ActiveSessionBloc] instead of handling
/// business logic locally in the screen.
class SessionControls extends StatelessWidget {
  final VoidCallback? onTogglePause;
  final VoidCallback? onEndSession;
  final bool isPaused;

  const SessionControls({
    super.key,
    this.onTogglePause,
    this.onEndSession,
    required this.isPaused,
  });

  // Helper method to get the appropriate color based on user gender
  Color _getLadyModeColor(BuildContext context) {
    try {
      final authState = context.read<AuthBloc>().state;
      if (authState is Authenticated && authState.user.gender == 'female') {
        return AppColors.ladyPrimary;
      }
    } catch (e) {
      // If we can't access the AuthBloc, fall back to default color
    }
    return AppColors.primary;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0), // Match the padding of stats widgets
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: <Widget>[
          // Pause/Resume button
          SizedBox(
            width: 60,
            height: 60,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _getLadyModeColor(context),
                shape: const CircleBorder(),
                padding: EdgeInsets.zero,
                elevation: 2,
              ),
              onPressed: () {
                HapticFeedback.heavyImpact();
                debugPrint('[PAUSE_DEBUG] SessionControls: Pause/Resume button pressed on PHONE UI. Current isPaused state (on UI): $isPaused');
                if (onTogglePause != null) onTogglePause!();
              },
              child: Icon(
                isPaused ? Icons.play_arrow : Icons.pause,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
          // Stop button
          SizedBox(
            width: 60,
            height: 60,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                shape: const CircleBorder(),
                padding: EdgeInsets.zero,
                elevation: 2,
              ),
              onPressed: () {
                HapticFeedback.heavyImpact();
                if (onEndSession != null) onEndSession!();
              },
              child: const Icon(
                Icons.stop,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
