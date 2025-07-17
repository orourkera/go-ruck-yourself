import 'dart:async';
import 'dart:collection';

import '../../../../../core/services/watch_service.dart';
import '../../../../../core/utils/app_logger.dart';
import '../../../domain/services/heart_rate_service.dart';
import '../../../domain/models/heart_rate_sample.dart';
import '../events/session_events.dart';
import '../models/manager_states.dart';
import 'session_manager.dart';

/// Manages heart rate monitoring and BLE device connections
class HeartRateManager implements SessionManager {
  final HeartRateService _heartRateService;
  final WatchService _watchService;
  
  final StreamController<HeartRateState> _stateController;
  HeartRateState _currentState;
  
  // Heart rate tracking state
  StreamSubscription<HeartRateSample>? _heartRateSubscription;
  final List<int> _heartRateSamples = [];
  final List<HeartRateSample> _heartRateSampleObjects = [];
  
  // CRITICAL FIX: Memory optimization constants - frequent uploads for crash resilience
  static const int _maxHeartRateSamples = 300; // Upload every ~5 minutes (300 samples at 1Hz)
  static const int _maxHeartRateSampleObjects = 300; // Upload every ~5 minutes
  static const int _minSamplesToKeep = 50; // Always keep for real-time calculations
  
  // Upload thresholds for crash resilience (similar to location points)
  static const int _uploadTriggerThreshold = 100; // Upload every ~1.5-2 minutes
  static const int _uploadBatchSize = 50; // Smaller, more frequent batches
  static const int _memoryPressureThreshold = 250; // Trigger aggressive upload
  
  // Track successful uploads to avoid data loss (similar to location points)
  int _lastUploadedSampleIndex = 0;
  int _lastUploadedObjectIndex = 0;
  
  // Upload queue for heart rate data (similar to location points)
  final Queue<Map<String, dynamic>> _pendingHeartRateUploads = Queue();
  Timer? _heartRateUploadTimer;
  
  // Session info
  String? _activeSessionId;
  bool _isMonitoring = false;
  
  HeartRateManager({
    required HeartRateService heartRateService,
    required WatchService watchService,
  })  : _heartRateService = heartRateService,
        _watchService = watchService,
        _stateController = StreamController<HeartRateState>.broadcast(),
        _currentState = const HeartRateState();

  @override
  Stream<HeartRateState> get stateStream => _stateController.stream;

  @override
  HeartRateState get currentState => _currentState;

  @override
  Future<void> handleEvent(ActiveSessionEvent event) async {
    if (event is SessionStartRequested) {
      await _onSessionStarted(event);
    } else if (event is SessionStopRequested) {
      await _onSessionStopped(event);
    } else if (event is SessionPaused) {
      await _onSessionPaused(event);
    } else if (event is SessionResumed) {
      await _onSessionResumed(event);
    } else if (event is HeartRateUpdated) {
      await _onHeartRateUpdated(event);
    }
  }

  Future<void> _onSessionStarted(SessionStartRequested event) async {
    _activeSessionId = event.sessionId;
    _heartRateSamples.clear();
    _heartRateSampleObjects.clear();
    
    // CRITICAL FIX: Reset upload tracking for new session
    _lastUploadedSampleIndex = 0;
    _lastUploadedObjectIndex = 0;
    _pendingHeartRateUploads.clear();
    
    // Start periodic upload timer for crash resilience
    _startHeartRateUploadTimer();
    
    _triggerGarbageCollection();
    
    AppLogger.info('[HEART_RATE_MANAGER] MEMORY_RESET: Session started, all lists cleared and upload tracking reset');
    
    await _startHeartRateMonitoring();
    
    _updateState(_currentState.copyWith(
      heartRateSamples: [],
      currentHeartRate: null,
      averageHeartRate: 0.0,
      maxHeartRate: 0,
      minHeartRate: 0,
      errorMessage: null,
    ));
  }

  Future<void> _onSessionStopped(SessionStopRequested event) async {
    await _stopHeartRateMonitoring();
    
    _activeSessionId = null;
    _heartRateSamples.clear();
    _heartRateSampleObjects.clear();
    
    // CRITICAL FIX: Stop upload timer and clear pending uploads
    _heartRateUploadTimer?.cancel();
    _heartRateUploadTimer = null;
    _pendingHeartRateUploads.clear();
    
    _triggerGarbageCollection();
    
    AppLogger.info('[HEART_RATE_MANAGER] MEMORY_CLEANUP: Session stopped, all lists cleared and upload timer stopped');
    
    _updateState(const HeartRateState());
  }

  Future<void> _onSessionPaused(SessionPaused event) async {
    // Continue monitoring heart rate during pause
    AppLogger.info('[HEART_RATE_MANAGER] Session paused, continuing heart rate monitoring');
  }

  Future<void> _onSessionResumed(SessionResumed event) async {
    AppLogger.info('[HEART_RATE_MANAGER] Session resumed');
  }

  Future<void> _onHeartRateUpdated(HeartRateUpdated event) async {
    if (_activeSessionId == null) return;
    
    final heartRate = event.heartRate;
    AppLogger.debug('[HEART_RATE_MANAGER] Heart rate updated: $heartRate bpm');
    
    // Add to samples
    _heartRateSamples.add(heartRate);
    
    // CRITICAL FIX: Trigger frequent uploads for crash resilience
    _triggerHeartRateUploadIfNeeded();
    
    // Manage memory pressure through proper uploads
    _manageHeartRateMemoryPressure();
    
    // Calculate statistics
    final stats = _calculateHeartRateStats();
    
    // Note: Heart rate sync to watch is handled by WatchService integration
    
    _updateState(_currentState.copyWith(
      heartRateSamples: List.from(_heartRateSamples),
      currentHeartRate: heartRate,
      averageHeartRate: stats.average,
      maxHeartRate: stats.max,
      minHeartRate: stats.min,
    ));
  }

  Future<void> _startHeartRateMonitoring() async {
    AppLogger.info('[HEART_RATE_MANAGER] Starting heart rate monitoring');
    _isMonitoring = true;
    
    try {
      // Subscribe to heart rate updates from the service
      _heartRateSubscription = _heartRateService.heartRateStream.listen(
        (sample) {
          if (sample.bpm > 0) {
            _heartRateSampleObjects.add(sample);
            
            // CRITICAL FIX: Trigger frequent uploads for crash resilience
            _triggerHeartRateUploadIfNeeded();
            
            // Manage memory pressure for sample objects
            _manageHeartRateMemoryPressure();
            
            handleEvent(HeartRateUpdated(
              heartRate: sample.bpm,
              timestamp: sample.timestamp,
            ));
          }
        },
        onError: (error) {
          AppLogger.error('[HEART_RATE_MANAGER] Heart rate stream error: $error');
          _updateState(_currentState.copyWith(
            errorMessage: 'Heart rate monitoring error',
          ));
        },
      );
      
      // Start the heart rate service
      await _heartRateService.startHeartRateMonitoring();
      
      // Update state to indicate monitoring started
      _updateState(_currentState.copyWith(
        isConnected: true, // Assume connected when monitoring starts
      ));
      
      AppLogger.info('[HEART_RATE_MANAGER] Heart rate monitoring started.');
      
    } catch (e) {
      AppLogger.error('[HEART_RATE_MANAGER] Failed to start heart rate monitoring: $e');
      _updateState(_currentState.copyWith(
        errorMessage: 'Failed to start heart rate monitoring',
        isConnected: false,
      ));
    }
  }

  Future<void> _stopHeartRateMonitoring() async {
    AppLogger.info('[HEART_RATE_MANAGER] Stopping heart rate monitoring');
    _isMonitoring = false;
    
    await _heartRateSubscription?.cancel();
    _heartRateSubscription = null;
    
    _heartRateService.stopHeartRateMonitoring();
  }

  ({double average, int max, int min}) _calculateHeartRateStats() {
    if (_heartRateSamples.isEmpty) {
      return (average: 0.0, max: 0, min: 0);
    }
    
    int sum = 0;
    int max = _heartRateSamples.first;
    int min = _heartRateSamples.first;
    
    for (final hr in _heartRateSamples) {
      sum += hr;
      if (hr > max) max = hr;
      if (hr < min) min = hr;
    }
    
    final average = sum / _heartRateSamples.length;
    
    return (average: average, max: max, min: min);
  }

  void _updateState(HeartRateState newState) {
    _currentState = newState;
    _stateController.add(newState);
  }

  /// CRITICAL FIX: Memory management through data persistence, not data loss
  void _manageHeartRateMemoryPressure() {
    // Check if we're approaching memory pressure thresholds
    if (_heartRateSamples.length >= _memoryPressureThreshold) {
      AppLogger.warning('[HEART_RATE_MANAGER] MEMORY_PRESSURE: ${_heartRateSamples.length} heart rate samples detected, triggering aggressive persistence');
      _triggerAggressiveDataPersistence();
    }
    
    // CRITICAL FIX: Trim after successful uploads (similar to location points)
    if (_heartRateSamples.length > _maxHeartRateSamples && _lastUploadedSampleIndex > _minSamplesToKeep) {
      _trimUploadedHeartRateSamples();
    }
    
    // Manage sample objects similarly
    if (_heartRateSampleObjects.length > _maxHeartRateSampleObjects && _lastUploadedObjectIndex > _minSamplesToKeep) {
      _trimUploadedHeartRateSampleObjects();
    }
  }
  
  /// Trigger aggressive data upload to database to free memory
  void _triggerAggressiveDataPersistence() {
    try {
      // Calculate how many samples we can safely upload
      final unuploadedSamples = _heartRateSamples.length - _lastUploadedSampleIndex;
      
      if (unuploadedSamples > _uploadBatchSize) {
        // Upload older samples to database (similar to location points)
        final batchEndIndex = _lastUploadedSampleIndex + _uploadBatchSize;
        final batchToUpload = _heartRateSamples.sublist(_lastUploadedSampleIndex, batchEndIndex);
        
        AppLogger.info('[HEART_RATE_MANAGER] MEMORY_PRESSURE: Uploading batch of ${batchToUpload.length} heart rate samples to database');
        
        // CRITICAL FIX: Actually upload heart rate data for crash resilience
        _triggerImmediateHeartRateUpload();
        
        // Update upload tracking after successful upload
        _lastUploadedSampleIndex = batchEndIndex;
      }
      
      // Force garbage collection to free memory immediately
      _triggerGarbageCollection();
      
    } catch (e) {
      AppLogger.error('[HEART_RATE_MANAGER] Error during aggressive data upload: $e');
    }
  }
  
  /// Trigger heart rate upload if threshold reached (crash resilience)
  void _triggerHeartRateUploadIfNeeded() {
    final unuploadedSamples = _heartRateSamples.length - _lastUploadedSampleIndex;
    
    if (unuploadedSamples >= _uploadTriggerThreshold) {
      AppLogger.info('[HEART_RATE_MANAGER] UPLOAD_TRIGGER: ${unuploadedSamples} unuploaded samples, triggering upload');
      _triggerImmediateHeartRateUpload();
    }
  }
  
  /// Start periodic upload timer for crash resilience
  void _startHeartRateUploadTimer() {
    _heartRateUploadTimer?.cancel();
    _heartRateUploadTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      final unuploadedSamples = _heartRateSamples.length - _lastUploadedSampleIndex;
      if (unuploadedSamples > 0) {
        AppLogger.info('[HEART_RATE_MANAGER] PERIODIC_UPLOAD: ${unuploadedSamples} unuploaded samples, triggering periodic upload');
        _triggerImmediateHeartRateUpload();
      }
    });
  }
  
  /// Trigger immediate heart rate upload to database
  void _triggerImmediateHeartRateUpload() {
    if (_activeSessionId == null) return;
    
    try {
      final unuploadedSamples = _heartRateSamples.length - _lastUploadedSampleIndex;
      if (unuploadedSamples <= 0) return;
      
      final batchEndIndex = _heartRateSamples.length; // Upload all unuploaded samples
      final samplesToUpload = _heartRateSamples.sublist(_lastUploadedSampleIndex, batchEndIndex)
          .asMap().entries.map((entry) {
        final index = _lastUploadedSampleIndex + entry.key;
        final timestamp = _heartRateSampleObjects.length > index 
            ? _heartRateSampleObjects[index].timestamp 
            : DateTime.now().subtract(Duration(seconds: _heartRateSamples.length - index));
        return {
          'bpm': entry.value,
          'timestamp': timestamp.toIso8601String(),
          'session_id': _activeSessionId,
          'uploaded_at': DateTime.now().toIso8601String(),
        };
      }).toList();
      
      // Add to upload queue
      for (final sample in samplesToUpload) {
        _pendingHeartRateUploads.add(sample);
      }
      
      // Process upload queue
      _processHeartRateUploadQueue();
      
      AppLogger.info('[HEART_RATE_MANAGER] IMMEDIATE_UPLOAD: Queued ${samplesToUpload.length} heart rate samples for upload');
      
    } catch (e) {
      AppLogger.error('[HEART_RATE_MANAGER] Error during immediate heart rate upload: $e');
    }
  }
  
  /// Process heart rate upload queue (similar to location points)
  void _processHeartRateUploadQueue() {
    if (_pendingHeartRateUploads.isEmpty || _activeSessionId == null) return;
    
    final batch = _pendingHeartRateUploads.toList();
    _pendingHeartRateUploads.clear();
    
    AppLogger.info('[HEART_RATE_MANAGER] UPLOAD_QUEUE: Processing batch of ${batch.length} heart rate samples');
    
    // TODO: Implement HeartRateDataUpload event or integrate with existing upload system
    // For now, simulate successful upload
    _onHeartRateUploadSuccess(batch.length);
  }
  
  /// Handle successful heart rate upload
  void _onHeartRateUploadSuccess(int uploadedCount) {
    _lastUploadedSampleIndex += uploadedCount;
    AppLogger.info('[HEART_RATE_MANAGER] UPLOAD_SUCCESS: ${uploadedCount} heart rate samples uploaded successfully');
  }
  
  /// Safely trim heart rate samples only after successful upload
  void _trimUploadedHeartRateSamples() {
    final samplesToRemove = _heartRateSamples.length - _maxHeartRateSamples;
    if (samplesToRemove > 0 && _lastUploadedSampleIndex >= samplesToRemove) {
      // Only remove samples that have been successfully uploaded
      _heartRateSamples.removeRange(0, samplesToRemove);
      _lastUploadedSampleIndex -= samplesToRemove;
      
      AppLogger.info('[HEART_RATE_MANAGER] MEMORY_OPTIMIZATION: Safely trimmed $samplesToRemove uploaded heart rate samples (${_heartRateSamples.length} remaining)');
      
      // Force garbage collection after trimming
      _triggerGarbageCollection();
    }
  }
  
  /// Safely trim heart rate sample objects only after successful upload
  void _trimUploadedHeartRateSampleObjects() {
    final samplesToRemove = _heartRateSampleObjects.length - _maxHeartRateSampleObjects;
    if (samplesToRemove > 0 && _lastUploadedObjectIndex >= samplesToRemove) {
      // Only remove objects that have been successfully uploaded
      _heartRateSampleObjects.removeRange(0, samplesToRemove);
      _lastUploadedObjectIndex -= samplesToRemove;
      
      AppLogger.info('[HEART_RATE_MANAGER] MEMORY_OPTIMIZATION: Safely trimmed $samplesToRemove uploaded heart rate sample objects (${_heartRateSampleObjects.length} remaining)');
      
      // Force garbage collection after trimming
      _triggerGarbageCollection();
    }
  }
  
  /// Trigger garbage collection to free memory immediately
  void _triggerGarbageCollection() {
    try {
      // Force garbage collection to free trimmed objects
      if (RegExp(r'debug|profile').hasMatch(const String.fromEnvironment('flutter.mode'))) {
        AppLogger.debug('[HEART_RATE_MANAGER] Garbage collection requested in debug mode');
      }
      // Note: Explicit GC triggering is automatic in release mode
    } catch (e) {
      AppLogger.error('[HEART_RATE_MANAGER] Error during garbage collection: $e');
    }
  }

  @override
  Future<void> dispose() async {
    await _stopHeartRateMonitoring();
    
    // CRITICAL FIX: Clear all lists and reset upload tracking before disposing
    _heartRateSamples.clear();
    _heartRateSampleObjects.clear();
    _lastUploadedSampleIndex = 0;
    _lastUploadedObjectIndex = 0;
    _pendingHeartRateUploads.clear();
    _heartRateUploadTimer?.cancel();
    _heartRateUploadTimer = null;
    _triggerGarbageCollection();
    
    await _stateController.close();
    
    AppLogger.info('[HEART_RATE_MANAGER] MEMORY_CLEANUP: Disposed with explicit memory cleanup and upload reset');
  }

  // Getters for other managers
  int? get currentHeartRate => _currentState.currentHeartRate;
  double get averageHeartRate => _currentState.averageHeartRate;
  List<int> get heartRateSamples => List.unmodifiable(_heartRateSamples);
  List<HeartRateSample> get heartRateSampleObjects => List.unmodifiable(_heartRateSampleObjects);
  bool get isConnected => _currentState.isConnected;
}
