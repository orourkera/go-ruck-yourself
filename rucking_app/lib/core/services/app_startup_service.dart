import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/services/active_session_storage.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/active_session_page.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/services/duel_completion_service.dart';

/// Service to handle app startup logic including session recovery
class AppStartupService {
  final ActiveSessionStorage _activeSessionStorage;
  final GetIt getIt = GetIt.instance;

  AppStartupService(this._activeSessionStorage);

  /// Check for session recovery and navigate to active session if needed
  /// Call this after successful authentication
  Future<bool> checkAndRecoverSession(BuildContext context) async {
    try {
      AppLogger.info('[STARTUP] Checking for recoverable session...');
      
      final shouldRecover = await _activeSessionStorage.shouldRecoverSession();
      
      if (shouldRecover) {
        AppLogger.info('[STARTUP] Found recoverable session, triggering recovery...');
        
        // Trigger session recovery
        if (context.mounted) {
          context.read<ActiveSessionBloc>().add(const SessionRecoveryRequested());
          
          // Navigate to active session screen
          await _navigateToActiveSession(context);
          return true;
        }
      }
      
      return false;
    } catch (e) {
      AppLogger.error('[STARTUP] Error during session recovery check: $e');
      return false;
    }
  }

  /// Navigate to the active session screen
  Future<void> _navigateToActiveSession(BuildContext context) async {
    try {
      if (context.mounted) {
        // Get stored session data to create ActiveSessionArgs
        final sessionData = await _activeSessionStorage.recoverSession();
        if (sessionData == null) {
          AppLogger.error('[STARTUP] No session data available for recovery navigation');
          return;
        }

        // Get current user weight from AuthBloc
        final authState = context.read<AuthBloc>().state;
        double userWeightKg = 70.0; // Default fallback
        if (authState is Authenticated) {
          userWeightKg = authState.user.weightKg ?? 70.0;
        }

        // Create ActiveSessionArgs from recovered session data
        final activeSessionArgs = ActiveSessionArgs(
          ruckWeight: sessionData['ruck_weight_kg'] as double? ?? 20.0, // Default if missing
          userWeightKg: userWeightKg,
          notes: null, // Notes aren't stored in session data
          plannedDuration: null, // Planned duration isn't stored in session data  
          initialCenter: null, // Initial center isn't stored in session data
        );

        // Clear the navigation stack and go directly to active session with proper arguments
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/active_session',
          (route) => false,
          arguments: activeSessionArgs,
        );
        
        AppLogger.info('[STARTUP] Navigated to active session screen for recovery with args: ruckWeight=${activeSessionArgs.ruckWeight}kg, userWeight=${activeSessionArgs.userWeightKg}kg');
      }
    } catch (e) {
      AppLogger.error('[STARTUP] Failed to navigate to active session: $e');
    }
  }

  /// Show a dialog to confirm session recovery
  Future<bool> _showRecoveryDialog(BuildContext context) async {
    if (!context.mounted) return false;
    
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Session Recovery'),
          content: const Text(
            'We found an unfinished rucking session from your last app usage. '
            'Would you like to continue where you left off?'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Start Fresh'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Continue Session'),
            ),
          ],
        );
      },
    );
    
    return result ?? false;
  }

  Future<void> _initializeDuelCompletionService() async {
    try {
      final duelCompletionService = getIt<DuelCompletionService>();
      duelCompletionService.startCompletionChecking();
      AppLogger.info('Duel completion service started');
    } catch (e) {
      AppLogger.error('Failed to start duel completion service: $e');
    }
  }
}
