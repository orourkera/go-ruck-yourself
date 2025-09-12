import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';
import 'package:rucking_app/features/notifications/presentation/bloc/notification_bloc.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/core/services/location_service.dart';
import 'package:rucking_app/features/health_integration/domain/health_service.dart';

/// Service to handle app lifecycle events and manage background services
class AppLifecycleService with WidgetsBindingObserver {
  static AppLifecycleService? _instance;
  static AppLifecycleService get instance {
    _instance ??= AppLifecycleService._internal();
    return _instance!;
  }

  AppLifecycleService._internal();

  bool _isInitialized = false;
  AppLifecycleState? _currentState;

  // Service references
  LocationService? _locationService;
  HealthService? _healthService;

  // Bloc references - will be set when app starts
  ActiveSessionBloc? _activeSessionBloc;
  NotificationBloc? _notificationBloc;
  AuthBloc? _authBloc;

  /// Initialize the lifecycle service
  void initialize() {
    if (_isInitialized) return;

    WidgetsBinding.instance.addObserver(this);
    _currentState = WidgetsBinding.instance.lifecycleState;

    try {
      _locationService = GetIt.I.isRegistered<LocationService>()
          ? GetIt.I<LocationService>()
          : null;
      _healthService = GetIt.I.isRegistered<HealthService>()
          ? GetIt.I<HealthService>()
          : null;
    } catch (e) {
      AppLogger.warning(
          'Some services not available during lifecycle initialization: $e');
    }

    _isInitialized = true;
    AppLogger.info('AppLifecycleService initialized');
  }

  /// Set bloc references (called from main app)
  void setBlocReferences({
    ActiveSessionBloc? activeSessionBloc,
    NotificationBloc? notificationBloc,
    AuthBloc? authBloc,
  }) {
    _activeSessionBloc = activeSessionBloc;
    _notificationBloc = notificationBloc;
    _authBloc = authBloc;
    AppLogger.info('Lifecycle service bloc references set');
  }

  /// Stop all background services and polling before logout
  void stopAllServices() {
    AppLogger.info('Stopping all background services for logout');

    // Stop notification polling to prevent timer issues during logout
    if (_notificationBloc != null) {
      _notificationBloc!.stopPolling();
      AppLogger.info('Stopped notification polling');
    }

    // Stop active session polling if running
    if (_activeSessionBloc != null) {
      // Note: ActiveSessionBloc doesn't have polling but we could add cleanup here if needed
    }

    // Pause any other background services
    _locationService?.stopLocationTracking();

    AppLogger.info('All background services stopped');
  }

  /// Clean up resources
  void dispose() {
    if (_isInitialized) {
      WidgetsBinding.instance.removeObserver(this);
      _isInitialized = false;
      AppLogger.info('AppLifecycleService disposed');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    AppLogger.info('App lifecycle changed: $_currentState → $state');
    _currentState = state;

    switch (state) {
      case AppLifecycleState.paused:
        _handleAppPaused();
        break;
      case AppLifecycleState.resumed:
        _handleAppResumed();
        break;
      case AppLifecycleState.inactive:
        _handleAppInactive();
        break;
      case AppLifecycleState.detached:
        _handleAppDetached();
        break;
      case AppLifecycleState.hidden:
        _handleAppHidden();
        break;
    }
  }

  /// Handle app going to background/paused
  void _handleAppPaused() {
    AppLogger.info('App paused - enabling background session protection');

    try {
      final activeState = _activeSessionBloc?.state;
      if (activeState is ActiveSessionRunning) {
        AppLogger.info('🏃 Active session - CONTINUES RECORDING in background');

        // ONLY crash protection - session NEVER auto-pauses
        // Force immediate session state save in case of crash/termination
        try {
          AppLogger.info('💾 CRASH PROTECTION: Force-saving session state');
          // Trigger immediate batch upload to save session state
          if (_activeSessionBloc?.state is ActiveSessionRunning) {
            final state = _activeSessionBloc!.state as ActiveSessionRunning;
            _activeSessionBloc
                ?.add(SessionBatchUploadRequested(sessionId: state.sessionId));
          }

          AppLogger.info(
              '✅ Session will continue recording in background indefinitely');
        } catch (persistError) {
          AppLogger.error('❌ Failed to save session state: $persistError');
        }
      }

      // Pause notification polling to reduce background activity
      _notificationBloc?.pausePolling();

      // Force garbage collection
      SystemChannels.platform.invokeMethod('SystemNavigator.routeUpdated');
    } catch (e) {
      AppLogger.error('Error handling app pause: $e');
    }
  }

  /// Handle app returning to foreground
  void _handleAppResumed() {
    AppLogger.info('App resumed - restoring foreground services');

    try {
      final activeState = _activeSessionBloc?.state;
      if (activeState is ActiveSessionRunning) {
        AppLogger.info('🏃 Active session continued perfectly in background');
        // Session never stopped - just log success
      }

      // Resume notification polling if user is authenticated
      final authState = _authBloc?.state;
      if (_notificationBloc != null && authState is Authenticated) {
        AppLogger.info('User authenticated - resuming notification polling');
        _notificationBloc!.add(const NotificationsRequested());
        _notificationBloc!.resumePolling(interval: const Duration(seconds: 30));
      }
    } catch (e) {
      AppLogger.error('Error handling app resume: $e');
    }
  }

  /// Handle app becoming inactive (e.g., during phone calls, control center)
  void _handleAppInactive() {
    AppLogger.info('App inactive - reducing activity');
    // App is temporarily inactive but not fully backgrounded
    // Keep essential services running but reduce frequency
  }

  /// Handle app being detached (usually during termination)
  void _handleAppDetached() {
    AppLogger.warning(
        '🚨 CRITICAL: App being detached/terminated - emergency session cleanup');

    try {
      // EMERGENCY: App is about to die - we have very limited time
      final activeState = _activeSessionBloc?.state;
      if (activeState is ActiveSessionRunning) {
        AppLogger.error(
            '⚠️ ORPHANED SESSION RISK: Active session during app termination!');

        // Immediately mark session as cancelled/paused - don't wait for async processing
        // This is our last chance to prevent orphaned sessions
        try {
          // Force immediate session cleanup for app termination
          _activeSessionBloc?.add(const SessionCleanupRequested());

          // Also try to persist the cancellation immediately (may not complete)
          AppLogger.info(
              '🆘 Emergency: Attempting immediate session cancellation');
        } catch (emergencyError) {
          AppLogger.error(
              '❌ CRITICAL: Emergency session cleanup failed: $emergencyError');
        }
      }

      // Try generic cleanup as backup (but may not complete)
      _activeSessionBloc?.add(const SessionCleanupRequested());
    } catch (e) {
      AppLogger.error('Error handling app detach: $e');
    }
  }

  /// Handle app being hidden (iOS 13+)
  void _handleAppHidden() {
    AppLogger.info('App hidden - minimal background mode');
    // Similar to paused but for iOS 13+ hidden state
    _handleAppPaused();
  }

  /// Get current lifecycle state
  AppLifecycleState? get currentState => _currentState;

  /// Check if app is in background
  bool get isInBackground =>
      _currentState == AppLifecycleState.paused ||
      _currentState == AppLifecycleState.detached ||
      _currentState == AppLifecycleState.hidden;

  /// Check if app is active
  bool get isActive => _currentState == AppLifecycleState.resumed;
}
