import 'package:flutter/material.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

/// Reusable widget showing Pause/Resume and End Session buttons.
///
/// Delegates state changes to [ActiveSessionBloc] instead of handling
/// business logic locally in the screen.
class SessionControls extends StatelessWidget {
  final VoidCallback? onTogglePause;
  final VoidCallback? onEndSession;
  final bool isPaused;

  SessionControls({
    super.key,
    this.onTogglePause,
    this.onEndSession,
    required this.isPaused,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        Expanded(
          child: ElevatedButton.icon(
            icon: Icon(isPaused ? Icons.play_arrow : Icons.pause, color: AppColors.white, size: 20),
            label: Text(isPaused ? 'RESUME' : 'PAUSE', style: AppTextStyles.labelLarge.copyWith(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary, 
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: onTogglePause, 
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton.icon(
            icon: Icon(Icons.stop, color: AppColors.white, size: 20),
            label: Text('STOP', style: AppTextStyles.labelLarge.copyWith(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error, 
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: onEndSession, 
          ),
        ),
      ],
    );
  }
}
