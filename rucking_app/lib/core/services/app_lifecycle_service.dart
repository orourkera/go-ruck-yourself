import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';
import 'package:rucking_app/features/notifications/presentation/bloc/notification_bloc.dart';
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
  
  /// Initialize the lifecycle service
  void initialize() {
    if (_isInitialized) return;
    
    WidgetsBinding.instance.addObserver(this);
    _currentState = WidgetsBinding.instance.lifecycleState;
    
    try {
      _locationService = GetIt.I.isRegistered<LocationService>() ? GetIt.I<LocationService>() : null;
      _healthService = GetIt.I.isRegistered<HealthService>() ? GetIt.I<HealthService>() : null;
    } catch (e) {
      AppLogger.warning('Some services not available during lifecycle initialization: $e');
    }
    
    _isInitialized = true;
    AppLogger.info('AppLifecycleService initialized');
  }
  
  /// Set bloc references (called from main app)
  void setBlocReferences({
    ActiveSessionBloc? activeSessionBloc,
    NotificationBloc? notificationBloc,
  }) {
    _activeSessionBloc = activeSessionBloc;
    _notificationBloc = notificationBloc;
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
    AppLogger.info('App paused - pausing background services');
    
    try {
      // Pause notification polling to reduce background activity
      _notificationBloc?.pausePolling();
      
      // Don't stop active session services, but reduce their frequency
      // Active sessions need to continue for workout tracking
      final activeState = _activeSessionBloc?.state;
      if (activeState is ActiveSessionRunning) {
        AppLogger.info('Active session detected - maintaining minimal background services');
        // Session continues but we could reduce update frequency here if needed
      } else {
        // No active session - can pause more aggressively
        AppLogger.info('No active session - pausing all non-essential services');
      }
      
      // Force garbage collection
      SystemChannels.platform.invokeMethod('SystemNavigator.routeUpdated');
      
    } catch (e) {
      AppLogger.error('Error handling app pause: $e');
    }
  }
  
  /// Handle app returning to foreground
  void _handleAppResumed() {
    AppLogger.info('App resumed - resuming background services');
    
    try {
      // Immediately check for new notifications and resume polling
      if (_notificationBloc != null) {
        _notificationBloc!.add(const NotificationsRequested());
        _notificationBloc!.resumePolling(interval: const Duration(seconds: 30)); // More frequent polling
      }
      
      // Check if we need to recover any services
      final activeState = _activeSessionBloc?.state;
      if (activeState is ActiveSessionRunning) {
        AppLogger.info('Active session detected - ensuring all services are running');
        // Could trigger a session recovery check here if needed
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
    AppLogger.info('App detached - cleaning up resources');
    
    try {
      // Ensure any pending data is saved
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
  bool get isInBackground => _currentState == AppLifecycleState.paused || 
                            _currentState == AppLifecycleState.detached ||
                            _currentState == AppLifecycleState.hidden;
  
  /// Check if app is active
  bool get isActive => _currentState == AppLifecycleState.resumed;
}
