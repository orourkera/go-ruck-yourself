import 'dart:async';

import 'package:rucking_app/core/services/watch_service.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/services/app_error_handler.dart';
import 'package:rucking_app/features/health_integration/domain/health_service.dart';
import 'package:rucking_app/features/ruck_session/domain/models/heart_rate_sample.dart';

/// Service that centralizes heart rate data handling from multiple sources
/// (Apple Watch and HealthKit) and provides a unified stream of heart rate updates.
class HeartRateService {
  final WatchService _watchService;
  final HealthService _healthService;

  // Stream controllers to expose heart rate data
  StreamController<HeartRateSample> _heartRateController = StreamController<HeartRateSample>.broadcast();
  StreamController<List<HeartRateSample>> _bufferController = StreamController<List<HeartRateSample>>.broadcast();

  // Subscriptions to source streams
  StreamSubscription? _watchHeartRateSubscription;
  StreamSubscription? _healthHeartRateSubscription;

  // Buffer for heart rate samples
  final List<HeartRateSample> _hrBuffer = [];
  
  // Last flush time for buffer
  DateTime? _lastHrFlush;
  
  // Current heart rate value
  int _latestHeartRate = 0;
  
  // Flag to track if we're currently attempting a reconnection
  bool _isReconnecting = false;
  
  // Flag to track if monitoring has been started
  bool _isMonitoringStarted = false;
  
  // Timer to detect and recover from lost connections
  Timer? _watchdogTimer;
  
  // Track the last time we received a heart rate update
  DateTime? _lastHeartRateTime;
  
  // Track the last time we saved a heart rate sample (for downsampling)
  DateTime? _lastSavedSampleTime;
  
  // Downsampling interval (20 seconds)
  static const Duration _samplingInterval = Duration(seconds: 20);

  /// Stream of individual heart rate updates
  Stream<HeartRateSample> get heartRateStream => _heartRateController.stream;

  /// Stream of buffered heart rate samples
  Stream<List<HeartRateSample>> get heartRateBufferStream => _bufferController.stream;

  /// The most recent heart rate value
  int get latestHeartRate => _latestHeartRate;

  /// The current heart rate buffer
  List<HeartRateSample> get heartRateBuffer => List.unmodifiable(_hrBuffer);

  HeartRateService({
    required WatchService watchService,
    required HealthService healthService,
  })  : _watchService = watchService,
        _healthService = healthService;

  /// Start monitoring heart rate from all available sources
  Future<void> startHeartRateMonitoring() async {
    AppLogger.info('HeartRateService: Starting heart rate monitoring...');
    
    // Reset monitoring state to ensure fresh start for new session
    if (_isMonitoringStarted) {
      AppLogger.info('HeartRateService: Heart rate monitoring already active, resetting for new session');
      stopHeartRateMonitoring(); // Stop existing monitoring first
    }
    
    // Ensure HealthKit permissions are granted once per app session.
    // IMPORTANT: Even if HealthKit is denied, we still start the Watch feed.
    if (!_healthService.isAuthorized) {
      final granted = await _healthService.requestAuthorization();
      if (!granted) {
        AppLogger.warning('HeartRateService: Health authorization denied – proceeding with Watch-only heart-rate stream');
        // Continue; we will skip HealthKit subscription but keep Watch updates.
      }
    }
    
    // Make sure we're not maintaining stale subscriptions
    _resetSubscriptions();
    
    // Set up watch subscription with auto-reconnect capability
    _setupWatchHeartRateSubscription();
    
    // Subscribe to HealthKit heart rate updates only if authorized
    if (_healthService.isAuthorized) {
      _setupHealthKitHeartRateSubscription();
    } else {
      AppLogger.info('HeartRateService: Skipping HealthKit heart rate subscription (not authorized)');
    }
    
    // Set up check to detect and recover from lost connections
    _startConnectionWatchdog();
    
    // Get initial heart rate from HealthKit if available
    await _fetchInitialHeartRate();
    
    // Mark monitoring as started
    _isMonitoringStarted = true;
    AppLogger.info('HeartRateService: Heart rate monitoring successfully started');
  }
  
  /// Stop heart rate monitoring
  void stopHeartRateMonitoring() {
    _watchHeartRateSubscription?.cancel();
    _healthHeartRateSubscription?.cancel();
    
    // Cancel the watchdog timer
    _watchdogTimer?.cancel();
    
    _watchHeartRateSubscription = null;
    _healthHeartRateSubscription = null;
    _watchdogTimer = null;
    
    // Reset monitoring flag and downsampling state
    _isMonitoringStarted = false;
    _lastSavedSampleTime = null;
    
    AppLogger.info('HeartRateService: Heart rate monitoring stopped');
  }
  
  /// Reset all subscriptions to ensure clean state
  void _resetSubscriptions() {
    AppLogger.info('HeartRateService: Resetting all subscriptions');
    _watchHeartRateSubscription?.cancel();
    _healthHeartRateSubscription?.cancel();
    _watchHeartRateSubscription = null;
    _healthHeartRateSubscription = null;
  }
  
  /// Set up subscription to watch heart rate updates with auto-reconnect
  void _setupWatchHeartRateSubscription() {
    AppLogger.info('HeartRateService: Setting up watch heart rate subscription');
    
    // Cancel existing subscription if present to avoid duplicates
    _watchHeartRateSubscription?.cancel();
    
    // Log current heart rate from WatchService to debug timing issues
    final currentHR = _watchService.getCurrentHeartRate();
    AppLogger.info('HeartRateService: [HR_DEBUG] Current WatchService HR at subscription: $currentHR');
    
    _watchHeartRateSubscription = _watchService.onHeartRateUpdate.listen(
      (heartRate) {
        AppLogger.info('HeartRateService: Raw heart rate from WatchService: $heartRate BPM');
        // Validate heart rate before processing
        if (heartRate <= 0) {
          AppLogger.warning('HeartRateService: Invalid heart rate received from watch: $heartRate');
          return;
        }
        
        final sample = HeartRateSample(
          timestamp: DateTime.now(),
          bpm: heartRate.toInt(),
        );
        AppLogger.info('HeartRateService: Processing heart rate sample: ${sample.bpm} BPM');
        _processHeartRateSample(sample, 'Watch');
      },
      onError: (error) {
        AppLogger.error('HeartRateService: Error in watch heart rate stream: $error');
        // Auto-reconnect after error
        _tryReconnectWatchService();
      },
      onDone: () {
        AppLogger.warning('HeartRateService: Watch heart rate stream closed');
        // Auto-reconnect when stream closes unexpectedly
        _tryReconnectWatchService();
      },
      cancelOnError: false, // Don't cancel on error to handle reconnects
    );
    
    // If there's already a current heart rate, process it immediately
    if (currentHR != null && currentHR > 0) {
      AppLogger.info('HeartRateService: [HR_DEBUG] Processing existing heart rate immediately: $currentHR');
      final sample = HeartRateSample(
        timestamp: DateTime.now(),
        bpm: currentHR.toInt(),
      );
      _processHeartRateSample(sample, 'Watch-Initial');
    }
    
    AppLogger.info('HeartRateService: Watch heart rate subscription successfully set up');
  }
  
  /// Set up subscription to HealthKit heart rate updates
  void _setupHealthKitHeartRateSubscription() {
    AppLogger.info('HeartRateService: Setting up HealthKit heart rate subscription');
    
    _healthHeartRateSubscription = _healthService.heartRateStream.listen(
      (sample) {
        _processHeartRateSample(sample, 'HealthKit');
      },
      onError: (error) {
        AppLogger.error('HeartRateService: Error in HealthKit heart rate stream: $error');
      },
      cancelOnError: false, // Don't cancel on error
    );
  }
  
  /// Attempt to reconnect to watch service
  void _tryReconnectWatchService() {
    // Avoid multiple simultaneous reconnection attempts
    if (_isReconnecting) return;
    
    _isReconnecting = true;
    AppLogger.info('HeartRateService: Attempting to reconnect watch heart rate subscription');
    
    Future.delayed(const Duration(seconds: 2), () {
      if (_watchHeartRateSubscription != null) {
        _watchHeartRateSubscription!.cancel();
        _watchHeartRateSubscription = null;
      }
      
      _setupWatchHeartRateSubscription();
      _isReconnecting = false;
      AppLogger.info('HeartRateService: Watch heart rate subscription reconnected');
    });
  }
  
  /// Start a watchdog timer to detect and recover from lost connections
  void _startConnectionWatchdog() {
    // Clean up existing timer if any
    _watchdogTimer?.cancel();
    
    // Check every 10 seconds if we're still receiving heart rate updates
    _watchdogTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      final now = DateTime.now();
      
      // If no heart rate updates in 20 seconds and we should be receiving them,
      // attempt to reconnect
      if (_lastHeartRateTime != null && 
          now.difference(_lastHeartRateTime!).inSeconds > 20 &&
          !_isReconnecting) {
        AppLogger.warning('HeartRateService: No heart rate updates received in the last 20 seconds');
        _tryReconnectWatchService();
      }
    });
  }
  
  /// Get initial heart rate from HealthKit if available
  Future<void> _fetchInitialHeartRate() async {
    try {
      final initialHr = await _healthService.getHeartRate();
      if (initialHr != null && initialHr > 0) {
        AppLogger.info('HeartRateService: Initial heart rate fetched: $initialHr BPM');
        final sample = HeartRateSample(
          timestamp: DateTime.now(),
          bpm: initialHr.round(),
        );
        _processHeartRateSample(sample, 'HealthKit-Initial');
      } else {
        AppLogger.info('HeartRateService: Initial heart rate not available');
      }
    } catch (e) {
      // Monitor heart rate initialization failures (affects fitness tracking quality)
      await AppErrorHandler.handleError(
        'heart_rate_initial_fetch',
        e,
        context: {
          'health_service_available': _healthService != null,
        },
      );
      AppLogger.error('HeartRateService: Error fetching initial heart rate: $e');
    }
  }
  
  /// Process a heart rate sample from any source
  void _processHeartRateSample(HeartRateSample sample, String source) {
    // Only process valid heart rate values
    if (sample.bpm <= 0) {
      AppLogger.warning('HeartRateService: Ignoring invalid heart rate value: ${sample.bpm} from $source');
      return;
    }
    
    _latestHeartRate = sample.bpm;
    _lastHeartRateTime = DateTime.now(); // Track when we received this sample
    
    AppLogger.info('HeartRateService: [HR_DEBUG] Received heart rate update from $source: ${sample.bpm} BPM');
    
    // Downsampling: only add to buffer if enough time has passed since last saved sample
    final now = DateTime.now();
    final shouldSave = _lastSavedSampleTime == null || 
                      now.difference(_lastSavedSampleTime!) >= _samplingInterval;
    
    if (shouldSave) {
      _hrBuffer.add(sample);
      _lastSavedSampleTime = now;
      AppLogger.info('HeartRateService: Saved heart rate sample to buffer (downsampled): ${sample.bpm} BPM');
    } else {
      AppLogger.debug('HeartRateService: Skipped saving heart rate sample (downsampling): ${sample.bpm} BPM');
    }
    
    // Broadcast individual sample - this is critical for UI updates
    if (!_heartRateController.isClosed) {
      _heartRateController.add(sample);
      AppLogger.info('HeartRateService: [HR_DEBUG] Successfully broadcast heart rate: ${sample.bpm} BPM to ${_heartRateController.hasListener ? 'listeners' : 'NO LISTENERS'}');
    } else {
      AppLogger.error('HeartRateService: Cannot broadcast heart rate sample - controller is closed!');
      // Try to recover by recreating the controller
      _recreateControllers();
      // Try to send again after recreation
      if (!_heartRateController.isClosed) {
        _heartRateController.add(sample);
        AppLogger.info('HeartRateService: [HR_DEBUG] Broadcast heart rate after controller recreation: ${sample.bpm} BPM');
      }
    }
    
    // If buffer exceeds threshold, also broadcast buffer update
    if (_hrBuffer.length >= 10) {
      if (!_bufferController.isClosed) {
        _bufferController.add(List.unmodifiable(_hrBuffer));
      }
    }
  }
  
  /// Recreate the stream controllers if they are closed
  void _recreateControllers() {
    AppLogger.info('HeartRateService: Recreating stream controllers');
    
    // Only recreate if closed
    if (_heartRateController.isClosed) {
      // Save any listeners to reattach them
      _heartRateController = StreamController<HeartRateSample>.broadcast();
      AppLogger.info('HeartRateService: Heart rate controller recreated');
    }
    
    if (_bufferController.isClosed) {
      _bufferController = StreamController<List<HeartRateSample>>.broadcast();
      AppLogger.info('HeartRateService: Buffer controller recreated');
    }
  }
  
  /// Flush the heart rate buffer to listeners
  Future<void> flushHeartRateBuffer() async {
    if (_hrBuffer.isEmpty) return;
    
    try {
      _bufferController.add(List.unmodifiable(_hrBuffer));
      _lastHrFlush = DateTime.now();
    } catch (e) {
      AppLogger.error('HeartRateService: Failed to flush heart rate buffer: $e');
    }
  }
  
  /// Clear the heart rate buffer
  void clearHeartRateBuffer() {
    _hrBuffer.clear();
    _lastHrFlush = DateTime.now();
  }
  
  /// Check if the buffer should be flushed based on time
  bool shouldFlushBuffer() {
    if (_hrBuffer.isEmpty) return false;
    
    return _lastHrFlush == null || 
           DateTime.now().difference(_lastHrFlush!) > const Duration(seconds: 5);
  }
  
  /// Update heart rate from an external source (like direct input)
  void updateHeartRate(int heartRate) {
    final sample = HeartRateSample(
      timestamp: DateTime.now(),
      bpm: heartRate,
    );
    _processHeartRateSample(sample, 'External');
  }
  
  /// Dispose all resources
  void dispose() {
    stopHeartRateMonitoring();
    
    // Reset reconnection state
    _isReconnecting = false;
    
    // Close stream controllers
    if (!_heartRateController.isClosed) {
      _heartRateController.close();
    }
    
    if (!_bufferController.isClosed) {
      _bufferController.close();
    }
    
    // Clear any buffered data
    _hrBuffer.clear();
    _lastHeartRateTime = null;
    _lastSavedSampleTime = null;
    
    AppLogger.info('HeartRateService: Disposed all resources');
  }
}
