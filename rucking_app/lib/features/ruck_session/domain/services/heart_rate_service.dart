import 'dart:async';

import 'package:rucking_app/core/services/watch_service.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/health_integration/domain/health_service.dart';
import 'package:rucking_app/features/ruck_session/domain/models/heart_rate_sample.dart';

/// Service that centralizes heart rate data handling from multiple sources
/// (Apple Watch and HealthKit) and provides a unified stream of heart rate updates.
class HeartRateService {
  final WatchService _watchService;
  final HealthService _healthService;

  // Stream controllers to expose heart rate data
  final _heartRateController = StreamController<HeartRateSample>.broadcast();
  final _bufferController = StreamController<List<HeartRateSample>>.broadcast();

  // Subscriptions to source streams
  StreamSubscription? _watchHeartRateSubscription;
  StreamSubscription? _healthHeartRateSubscription;

  // Buffer for heart rate samples
  final List<HeartRateSample> _hrBuffer = [];
  
  // Last flush time for buffer
  DateTime? _lastHrFlush;
  
  // Current heart rate value
  int _latestHeartRate = 0;

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
    
    // Ensure HealthKit permissions are granted once per app session
    if (!_healthService.isAuthorized) {
      final granted = await _healthService.requestAuthorization();
      if (!granted) {
        AppLogger.warning('HeartRateService: Health authorization denied – heart-rate stream disabled');
        return; // Do not start subscription without permission
      }
    }
    
    // Cancel previous subscriptions if any
    _watchHeartRateSubscription?.cancel();
    _healthHeartRateSubscription?.cancel();
    
    // Subscribe to Watch heart rate updates
    _watchHeartRateSubscription = _watchService.onHeartRateUpdate.listen(
      (heartRate) {
        final sample = HeartRateSample(
          timestamp: DateTime.now(),
          bpm: heartRate.toInt(),
        );
        _processHeartRateSample(sample, 'Watch');
      },
      onError: (error) {
        AppLogger.error('HeartRateService: Error in watch heart rate stream: $error');
      },
    );
    
    // Subscribe to HealthKit heart rate updates
    _healthHeartRateSubscription = _healthService.heartRateStream.listen(
      (sample) {
        _processHeartRateSample(sample, 'HealthKit');
      },
      onError: (error) {
        AppLogger.error('HeartRateService: Error in HealthKit heart rate stream: $error');
      },
    );

    // Get initial heart rate from HealthKit if available
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
      AppLogger.error('HeartRateService: Error fetching initial heart rate: $e');
    }
  }

  /// Process a heart rate sample from any source
  void _processHeartRateSample(HeartRateSample sample, String source) {
    _latestHeartRate = sample.bpm;
    
    AppLogger.info('HeartRateService: Received heart rate update from $source: ${sample.bpm} BPM');
    _hrBuffer.add(sample);
    
    // Broadcast individual sample
    _heartRateController.add(sample);
    
    // If buffer exceeds threshold, also broadcast buffer update
    if (_hrBuffer.length >= 10) {
      _bufferController.add(List.unmodifiable(_hrBuffer));
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

  /// Stop heart rate monitoring
  void stopHeartRateMonitoring() {
    _watchHeartRateSubscription?.cancel();
    _healthHeartRateSubscription?.cancel();
    
    _watchHeartRateSubscription = null;
    _healthHeartRateSubscription = null;
    
    AppLogger.info('HeartRateService: Heart rate monitoring stopped');
  }

  /// Dispose all resources
  void dispose() {
    stopHeartRateMonitoring();
    _heartRateController.close();
    _bufferController.close();
  }
}
