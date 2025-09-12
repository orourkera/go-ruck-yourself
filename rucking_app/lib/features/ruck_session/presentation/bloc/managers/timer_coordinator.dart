import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';

/// Coordinates all session timers with sophisticated timing logic
class TimerCoordinator {
  // Core session timer
  Timer? _mainTimer;

  // Specialized timers
  Timer? _watchdogTimer;
  Timer? _sessionPersistenceTimer;
  Timer? _batchUploadTimer;
  Timer? _connectivityCheckTimer;
  Timer? _memoryCheckTimer;

  // Timer state tracking
  bool _isTimerSystemActive = false;
  DateTime? _timerSystemStartTime;
  int _mainTickCount = 0;
  int _paceTickCounter = 0;

  // Timer intervals (configurable)
  Duration _mainInterval = const Duration(seconds: 1);
  Duration _watchdogInterval = const Duration(seconds: 30);
  Duration _persistenceInterval = const Duration(minutes: 1);
  Duration _batchUploadInterval = const Duration(minutes: 2);
  Duration _connectivityCheckInterval = const Duration(seconds: 15);
  Duration _memoryCheckInterval = const Duration(seconds: 30);

  // Timer health monitoring
  DateTime? _lastMainTick;
  DateTime? _lastWatchdogTick;
  DateTime? _lastPersistenceTick;
  DateTime? _lastBatchUploadTick;
  int _timerHealthCheckCount = 0;

  // Callbacks
  VoidCallback? _onMainTick;
  VoidCallback? _onWatchdogTick;
  VoidCallback? _onPersistenceTick;
  VoidCallback? _onBatchUploadTick;
  VoidCallback? _onConnectivityCheck;
  VoidCallback? _onMemoryCheck;
  VoidCallback? _onPaceCalculation;

  TimerCoordinator({
    VoidCallback? onMainTick,
    VoidCallback? onWatchdogTick,
    VoidCallback? onPersistenceTick,
    VoidCallback? onBatchUploadTick,
    VoidCallback? onConnectivityCheck,
    VoidCallback? onMemoryCheck,
    VoidCallback? onPaceCalculation,
  }) {
    _onMainTick = onMainTick;
    _onWatchdogTick = onWatchdogTick;
    _onPersistenceTick = onPersistenceTick;
    _onBatchUploadTick = onBatchUploadTick;
    _onConnectivityCheck = onConnectivityCheck;
    _onMemoryCheck = onMemoryCheck;
    _onPaceCalculation = onPaceCalculation;
  }

  /// Start the coordinated timer system
  void startTimerSystem() {
    if (_isTimerSystemActive) {
      AppLogger.warning('[TIMER_COORDINATOR] Timer system already active');
      return;
    }

    _isTimerSystemActive = true;
    _timerSystemStartTime = DateTime.now();
    _mainTickCount = 0;
    _paceTickCounter = 0;

    AppLogger.info('[TIMER_COORDINATOR] Starting coordinated timer system');

    // Start main timer (1 second interval)
    _startMainTimer();

    // Start specialized timers
    _startWatchdogTimer();
    _startPersistenceTimer();
    _startBatchUploadTimer();
    _startConnectivityCheckTimer();
    _startMemoryCheckTimer();

    // Start timer health monitoring
    _startTimerHealthMonitoring();

    AppLogger.info('[TIMER_COORDINATOR] All timers started successfully');
  }

  /// Pause the coordinated timer system
  void pauseTimerSystem() {
    if (!_isTimerSystemActive) {
      AppLogger.debug(
          '[TIMER_COORDINATOR] Timer system not active - cannot pause');
      return;
    }

    AppLogger.info('[TIMER_COORDINATOR] Pausing coordinated timer system');

    // Cancel main timer only - keep other monitoring timers running
    _mainTimer?.cancel();
    _mainTimer = null;

    AppLogger.info('[TIMER_COORDINATOR] Main timer paused successfully');
  }

  /// Resume the coordinated timer system
  void resumeTimerSystem() {
    if (!_isTimerSystemActive) {
      AppLogger.debug(
          '[TIMER_COORDINATOR] Timer system not active - cannot resume');
      return;
    }

    AppLogger.info('[TIMER_COORDINATOR] Resuming coordinated timer system');

    // Restart main timer
    _startMainTimer();

    AppLogger.info('[TIMER_COORDINATOR] Main timer resumed successfully');
  }

  /// Stop the coordinated timer system
  void stopTimerSystem() {
    if (!_isTimerSystemActive) {
      AppLogger.debug('[TIMER_COORDINATOR] Timer system already stopped');
      return;
    }

    AppLogger.info('[TIMER_COORDINATOR] Stopping coordinated timer system');

    // Cancel all timers
    _mainTimer?.cancel();
    _watchdogTimer?.cancel();
    _sessionPersistenceTimer?.cancel();
    _batchUploadTimer?.cancel();
    _connectivityCheckTimer?.cancel();
    _memoryCheckTimer?.cancel();

    // Reset timer references
    _mainTimer = null;
    _watchdogTimer = null;
    _sessionPersistenceTimer = null;
    _batchUploadTimer = null;
    _connectivityCheckTimer = null;
    _memoryCheckTimer = null;

    // Reset state
    _isTimerSystemActive = false;
    _timerSystemStartTime = null;
    _mainTickCount = 0;
    _paceTickCounter = 0;

    AppLogger.info('[TIMER_COORDINATOR] Timer system stopped successfully');
  }

  /// Start main timer with sophisticated tick processing
  void _startMainTimer() {
    _mainTimer?.cancel();
    _mainTimer = Timer.periodic(_mainInterval, (timer) {
      _mainTickCount++;
      _paceTickCounter++;
      _lastMainTick = DateTime.now();

      // Execute main tick callback
      _onMainTick?.call();

      // Execute pace calculation every 5 seconds for performance
      if (_paceTickCounter % 5 == 0) {
        _onPaceCalculation?.call();
      }

      // Log timer health every 60 seconds
      if (_mainTickCount % 60 == 0) {
        _logTimerHealth();
      }
    });
  }

  /// Start watchdog timer for GPS and system monitoring
  void _startWatchdogTimer() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(_watchdogInterval, (timer) {
      _lastWatchdogTick = DateTime.now();
      _onWatchdogTick?.call();
    });
  }

  /// Start session persistence timer
  void _startPersistenceTimer() {
    _sessionPersistenceTimer?.cancel();
    _sessionPersistenceTimer = Timer.periodic(_persistenceInterval, (timer) {
      _lastPersistenceTick = DateTime.now();
      _onPersistenceTick?.call();
    });
  }

  /// Start batch upload timer
  void _startBatchUploadTimer() {
    _batchUploadTimer?.cancel();
    _batchUploadTimer = Timer.periodic(_batchUploadInterval, (timer) {
      _lastBatchUploadTick = DateTime.now();
      _onBatchUploadTick?.call();
    });
  }

  /// Start connectivity check timer
  void _startConnectivityCheckTimer() {
    _connectivityCheckTimer?.cancel();
    _connectivityCheckTimer =
        Timer.periodic(_connectivityCheckInterval, (timer) {
      _onConnectivityCheck?.call();
    });
  }

  /// Start memory check timer
  void _startMemoryCheckTimer() {
    _memoryCheckTimer?.cancel();
    _memoryCheckTimer = Timer.periodic(_memoryCheckInterval, (timer) {
      _onMemoryCheck?.call();
    });
  }

  /// Start timer health monitoring
  void _startTimerHealthMonitoring() {
    Timer.periodic(const Duration(minutes: 1), (timer) {
      if (!_isTimerSystemActive) {
        timer.cancel();
        return;
      }

      _timerHealthCheckCount++;
      _performTimerHealthCheck();
    });
  }

  /// Perform timer health check
  void _performTimerHealthCheck() {
    final now = DateTime.now();
    bool hasUnhealthyTimers = false;

    // Check main timer health
    if (_lastMainTick != null &&
        now.difference(_lastMainTick!).inSeconds > 10) {
      AppLogger.warning(
          '[TIMER_COORDINATOR] Main timer appears unhealthy - last tick was ${now.difference(_lastMainTick!).inSeconds}s ago');
      hasUnhealthyTimers = true;
    }

    // Check watchdog timer health
    if (_lastWatchdogTick != null &&
        now.difference(_lastWatchdogTick!).inSeconds > 60) {
      AppLogger.warning(
          '[TIMER_COORDINATOR] Watchdog timer appears unhealthy - last tick was ${now.difference(_lastWatchdogTick!).inSeconds}s ago');
      hasUnhealthyTimers = true;
    }

    // Check persistence timer health
    if (_lastPersistenceTick != null &&
        now.difference(_lastPersistenceTick!).inSeconds > 120) {
      AppLogger.warning(
          '[TIMER_COORDINATOR] Persistence timer appears unhealthy - last tick was ${now.difference(_lastPersistenceTick!).inSeconds}s ago');
      hasUnhealthyTimers = true;
    }

    // Restart unhealthy timers
    if (hasUnhealthyTimers) {
      AppLogger.info('[TIMER_COORDINATOR] Restarting unhealthy timers');
      _restartUnhealthyTimers();
    }
  }

  /// Restart unhealthy timers
  void _restartUnhealthyTimers() {
    final now = DateTime.now();

    // Don't restart main timer if session is paused - this prevents automatic resume
    // The main timer should only run when session is actively running
    bool isSessionPaused = false;
    try {
      if (GetIt.I.isRegistered<ActiveSessionBloc>()) {
        final bloc = GetIt.I<ActiveSessionBloc>();
        final state = bloc.state;
        isSessionPaused =
            state is ActiveSessionRunning ? state.isPaused : false;
      }
    } catch (e) {
      // If we can't determine pause state, err on the side of caution
      AppLogger.debug(
          '[TIMER_COORDINATOR] Could not determine pause state: $e');
    }

    // Restart main timer if unhealthy AND not paused
    if (_lastMainTick != null &&
        now.difference(_lastMainTick!).inSeconds > 10 &&
        !isSessionPaused) {
      AppLogger.info('[TIMER_COORDINATOR] Restarting main timer');
      _startMainTimer();
    } else if (isSessionPaused) {
      AppLogger.debug(
          '[TIMER_COORDINATOR] Skipping main timer restart - session is paused');
    }

    // Restart watchdog timer if unhealthy
    if (_lastWatchdogTick != null &&
        now.difference(_lastWatchdogTick!).inSeconds > 60) {
      AppLogger.info('[TIMER_COORDINATOR] Restarting watchdog timer');
      _startWatchdogTimer();
    }

    // Restart persistence timer if unhealthy
    if (_lastPersistenceTick != null &&
        now.difference(_lastPersistenceTick!).inSeconds > 120) {
      AppLogger.info('[TIMER_COORDINATOR] Restarting persistence timer');
      _startPersistenceTimer();
    }
  }

  /// Log timer health status
  void _logTimerHealth() {
    final uptime = _timerSystemStartTime != null
        ? DateTime.now().difference(_timerSystemStartTime!).inSeconds
        : 0;

    AppLogger.debug(
        '[TIMER_COORDINATOR] Timer health check #$_timerHealthCheckCount - '
        'Uptime: ${uptime}s, Main ticks: $_mainTickCount, Pace ticks: $_paceTickCounter');
  }

  /// Get timer system statistics
  Map<String, dynamic> getTimerStats() {
    final now = DateTime.now();
    final uptime = _timerSystemStartTime != null
        ? now.difference(_timerSystemStartTime!).inSeconds
        : 0;

    return {
      'isActive': _isTimerSystemActive,
      'uptime': uptime,
      'mainTicks': _mainTickCount,
      'paceTickCounter': _paceTickCounter,
      'healthChecks': _timerHealthCheckCount,
      'lastMainTick': _lastMainTick?.toIso8601String(),
      'lastWatchdogTick': _lastWatchdogTick?.toIso8601String(),
      'lastPersistenceTick': _lastPersistenceTick?.toIso8601String(),
      'lastBatchUploadTick': _lastBatchUploadTick?.toIso8601String(),
    };
  }

  /// Update timer intervals for performance optimization
  void updateTimerIntervals({
    Duration? mainInterval,
    Duration? watchdogInterval,
    Duration? persistenceInterval,
    Duration? batchUploadInterval,
    Duration? connectivityCheckInterval,
    Duration? memoryCheckInterval,
  }) {
    bool needsRestart = false;

    if (mainInterval != null && mainInterval != _mainInterval) {
      _mainInterval = mainInterval;
      needsRestart = true;
    }

    if (watchdogInterval != null && watchdogInterval != _watchdogInterval) {
      _watchdogInterval = watchdogInterval;
      needsRestart = true;
    }

    if (persistenceInterval != null &&
        persistenceInterval != _persistenceInterval) {
      _persistenceInterval = persistenceInterval;
      needsRestart = true;
    }

    if (batchUploadInterval != null &&
        batchUploadInterval != _batchUploadInterval) {
      _batchUploadInterval = batchUploadInterval;
      needsRestart = true;
    }

    if (connectivityCheckInterval != null &&
        connectivityCheckInterval != _connectivityCheckInterval) {
      _connectivityCheckInterval = connectivityCheckInterval;
      needsRestart = true;
    }

    if (memoryCheckInterval != null &&
        memoryCheckInterval != _memoryCheckInterval) {
      _memoryCheckInterval = memoryCheckInterval;
      needsRestart = true;
    }

    if (needsRestart && _isTimerSystemActive) {
      AppLogger.info(
          '[TIMER_COORDINATOR] Timer intervals updated, restarting system');
      stopTimerSystem();
      startTimerSystem();
    }
  }

  /// Get current tick counters
  int get mainTickCount => _mainTickCount;
  int get paceTickCounter => _paceTickCounter;
  bool get isActive => _isTimerSystemActive;

  /// Dispose of all resources
  void dispose() {
    stopTimerSystem();
    _onMainTick = null;
    _onWatchdogTick = null;
    _onPersistenceTick = null;
    _onBatchUploadTick = null;
    _onConnectivityCheck = null;
    _onMemoryCheck = null;
    _onPaceCalculation = null;
  }
}
