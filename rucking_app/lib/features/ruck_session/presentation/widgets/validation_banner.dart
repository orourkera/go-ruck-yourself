import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';

/// Displays a temporary banner when the [ActiveSessionRunning.validationMessage]
/// in the bloc state is non-null.
class ValidationBanner extends StatelessWidget {
  const ValidationBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocSelector<ActiveSessionBloc, ActiveSessionState, String?>(
      selector: (state) {
        return state is ActiveSessionRunning ? state.validationMessage : null;
      },
      builder: (context, message) {
        if (message == null) return const SizedBox.shrink();
        return Material(
          color: Colors.transparent,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.accentLight,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
            ),
            child: Text(
              message,
              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
        );
      },
    );
  }
}
