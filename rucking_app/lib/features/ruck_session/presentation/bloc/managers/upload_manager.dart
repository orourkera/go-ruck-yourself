import 'dart:async';
import 'dart:collection';

import '../../../../../core/services/api_client.dart';
import '../../../../../core/services/storage_service.dart';
import '../../../../../core/utils/app_logger.dart';
import '../../../../../core/models/location_point.dart';
import '../../../data/repositories/session_repository.dart';
import '../events/session_events.dart';
import '../models/manager_states.dart';
import 'session_manager.dart';

/// Manages batch uploads and offline data synchronization
class UploadManager implements SessionManager {
  final SessionRepository _sessionRepository;
  final ApiClient _apiClient;
  final StorageService _storageService;
  
  final StreamController<UploadState> _stateController;
  UploadState _currentState;
  
  // Upload state
  String? _activeSessionId;
  final Queue<Map<String, dynamic>> _uploadQueue = Queue();
  bool _isProcessing = false;
  Timer? _uploadTimer;
  
  // Sophisticated upload tracking
  bool _isBatchUploadInProgress = false;
  DateTime? _lastUploadTime;
  Duration _batchUploadInterval = const Duration(minutes: 2);
  int _uploadSuccessCount = 0;
  int _uploadFailureCount = 0;
  final Map<String, int> _uploadStats = {};
  
  static const int _maxRetries = 3;
  static const int _maxQueueSize = 100;
  static const Duration _uploadTimeout = Duration(seconds: 30);
  
  UploadManager({
    required SessionRepository sessionRepository,
    required ApiClient apiClient,
    required StorageService storageService,
  })  : _sessionRepository = sessionRepository,
        _apiClient = apiClient,
        _storageService = storageService,
        _stateController = StreamController<UploadState>.broadcast(),
        _currentState = const UploadState();

  @override
  Stream<UploadState> get stateStream => _stateController.stream;

  @override
  UploadState get currentState => _currentState;

  @override
  Future<void> handleEvent(ActiveSessionEvent event) async {
    if (event is SessionStartRequested) {
      await _onSessionStarted(event);
    } else if (event is SessionStopRequested) {
      await _onSessionStopped(event);
    } else if (event is BatchLocationUpdated) {
      await _onBatchLocationUpdated(event);
    } else if (event is HeartRateBatchUploadRequested) {
      await _onHeartRateBatchUploadRequested(event);
    } else if (event is MemoryPressureDetected) {
      await _onMemoryPressureDetected(event);
    }
  }

  Future<void> _onSessionStarted(SessionStartRequested event) async {
    _activeSessionId = event.sessionId;
    
    // Start sophisticated batch upload timer
    _startSophisticatedUploadTimer();
    
    // Reset upload statistics
    _uploadSuccessCount = 0;
    _uploadFailureCount = 0;
    _uploadStats.clear();
    _isBatchUploadInProgress = false;
    
    _updateState(_currentState.copyWith(
      pendingLocationPoints: 0,
      pendingHeartRateSamples: 0,
      isUploading: false,
      errorMessage: null,
    ));
    
    // Check for any pending offline uploads
    await _loadOfflineData();
    
    AppLogger.info('[UPLOAD_MANAGER] Sophisticated batch upload system started for session: $_activeSessionId');
  }

  Future<void> _onSessionStopped(SessionStopRequested event) async {
    // Process any remaining uploads
    await _processUploadQueue();
    
    // Stop upload timer
    _uploadTimer?.cancel();
    _uploadTimer = null;
    
    _activeSessionId = null;
    _uploadQueue.clear();
    
    _updateState(const UploadState());
  }

  Future<void> _onBatchLocationUpdated(BatchLocationUpdated event) async {
    if (_activeSessionId == null || _activeSessionId!.startsWith('offline_')) {
      // Save offline for later sync
      await _saveOfflineLocationBatch(event.locationPoints);
      return;
    }
    
    // Add to upload queue
    _uploadQueue.add({
      'type': 'location_batch',
      'data': event.locationPoints,
      'retries': 0,
    });
    
    _updateState(_currentState.copyWith(
      pendingLocationPoints: _uploadQueue.length,
    ));
    
    AppLogger.debug('[UPLOAD_MANAGER] Added location batch to queue. Pending: ${_uploadQueue.length}');
  }
  
  Future<void> _onHeartRateBatchUploadRequested(HeartRateBatchUploadRequested event) async {
    if (_activeSessionId == null || _activeSessionId!.startsWith('offline_')) {
      // Save offline for later sync
      AppLogger.debug('[UPLOAD_MANAGER] Offline session, skipping heart rate upload');
      return;
    }
    
    // Convert heart rate samples to uploadable format
    final heartRateData = event.samples.map((sample) => {
      'bpm': sample.bpm,
      'timestamp': sample.timestamp.toIso8601String(),
      'session_id': _activeSessionId,
    }).toList();
    
    // Add to upload queue
    _uploadQueue.add({
      'type': 'heart_rate_batch',
      'data': heartRateData,
      'retries': 0,
    });
    
    _updateState(_currentState.copyWith(
      pendingHeartRateSamples: _uploadQueue.where((item) => item['type'] == 'heart_rate_batch').length,
    ));
    
    AppLogger.debug('[UPLOAD_MANAGER] Added heart rate batch to queue. Pending HR batches: ${_uploadQueue.where((item) => item['type'] == 'heart_rate_batch').length}');
  }

  Future<void> _onMemoryPressureDetected(MemoryPressureDetected event) async {
    AppLogger.error('[UPLOAD_MANAGER] MEMORY_PRESSURE: ${event.memoryUsageMb}MB detected, triggering aggressive upload');
    
    // Trigger immediate upload of all pending data
    await _processUploadQueue();
    
    // Trigger aggressive offline data processing
    await _loadOfflineData();
    
    AppLogger.info('[UPLOAD_MANAGER] MEMORY_PRESSURE: Aggressive upload completed');
  }

  void _startSophisticatedUploadTimer() {
    _uploadTimer?.cancel();
    _uploadTimer = Timer.periodic(_batchUploadInterval, (timer) async {
      if (_isBatchUploadInProgress) {
        AppLogger.debug('[UPLOAD_MANAGER] Batch upload already in progress, skipping...');
        return;
      }
      
      if (_uploadQueue.isEmpty) {
        AppLogger.debug('[UPLOAD_MANAGER] No uploads pending, skipping batch upload');
        return;
      }
      
      await _processBatchUploadWithProgress();
    });
    
    AppLogger.info('[UPLOAD_MANAGER] Sophisticated batch upload timer started - '
        'uploading every ${_batchUploadInterval.inMinutes} minutes');
  }
  
  /// Process batch upload with sophisticated progress tracking
  Future<void> _processBatchUploadWithProgress() async {
    if (_isBatchUploadInProgress) return;
    
    _isBatchUploadInProgress = true;
    final batchStartTime = DateTime.now();
    final initialQueueSize = _uploadQueue.length;
    
    AppLogger.info('[UPLOAD_MANAGER] Starting batch upload - ${initialQueueSize} items in queue');
    
    _updateState(_currentState.copyWith(
      isUploading: true,
      errorMessage: null,
    ));
    
    try {
      int successCount = 0;
      int failureCount = 0;
      
      // Process uploads in batches of 10 for better performance
      while (_uploadQueue.isNotEmpty && successCount + failureCount < initialQueueSize) {
        final batchToProcess = <Map<String, dynamic>>[];
        
        // Take up to 10 items from queue
        for (int i = 0; i < 10 && _uploadQueue.isNotEmpty; i++) {
          batchToProcess.add(_uploadQueue.removeFirst());
        }
        
        // Process this batch
        for (final upload in batchToProcess) {
          try {
            await _processUploadItem(upload);
            successCount++;
            _uploadSuccessCount++;
            
            // Update statistics
            final uploadType = upload['type'] as String;
            _uploadStats[uploadType] = (_uploadStats[uploadType] ?? 0) + 1;
            
          } catch (e) {
            failureCount++;
            _uploadFailureCount++;
            
            // Handle upload failure
            await _handleUploadFailure(upload, e);
            
            AppLogger.warning('[UPLOAD_MANAGER] Upload failed: $e');
          }
        }
        
        // Update progress
        _updateState(_currentState.copyWith(
          pendingLocationPoints: _uploadQueue.length,
          isUploading: _uploadQueue.isNotEmpty,
        ));
        
        // Small delay between batches to prevent overwhelming the server
        if (_uploadQueue.isNotEmpty) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
      
      final batchDuration = DateTime.now().difference(batchStartTime);
      _lastUploadTime = DateTime.now();
      
      AppLogger.info('[UPLOAD_MANAGER] Batch upload completed - '
          'Success: $successCount, Failures: $failureCount, '
          'Duration: ${batchDuration.inSeconds}s, '
          'Total Success: $_uploadSuccessCount, Total Failures: $_uploadFailureCount');
      
      _updateState(_currentState.copyWith(
        isUploading: false,
        pendingLocationPoints: _uploadQueue.length,
        errorMessage: failureCount > 0 ? '$failureCount uploads failed' : null,
      ));
      
    } catch (e) {
      AppLogger.error('[UPLOAD_MANAGER] Batch upload process failed: $e');
      
      _updateState(_currentState.copyWith(
        isUploading: false,
        errorMessage: 'Batch upload failed: $e',
      ));
    } finally {
      _isBatchUploadInProgress = false;
    }
  }

  Future<void> _processUploadQueue() async {
    if (_uploadQueue.isEmpty || _isProcessing) return;
    
    _isProcessing = true;
    _updateState(_currentState.copyWith(isUploading: true));
    
    while (_uploadQueue.isNotEmpty && _activeSessionId != null) {
      final upload = _uploadQueue.removeFirst();
      
      try {
        // Process different upload types with actual server calls
        final uploadType = upload['type'] as String;
        final uploadData = upload['data'];
        
        AppLogger.info('[UPLOAD_MANAGER] Processing ${uploadType} upload for session $_activeSessionId');
        
        switch (uploadType) {
          case 'location_batch':
            await _uploadLocationBatch(uploadData as List<LocationPoint>);
            break;
          case 'heart_rate_batch':
            await _uploadHeartRateBatch(uploadData as List<Map<String, dynamic>>);
            break;
          case 'terrain_segments':
            await _uploadTerrainSegments(uploadData as List<Map<String, dynamic>>);
            break;
          default:
            AppLogger.warning('[UPLOAD_MANAGER] Unknown upload type: $uploadType');
        }
        
        AppLogger.info('[UPLOAD_MANAGER] Successfully uploaded ${uploadType} batch');
        
        _updateState(_currentState.copyWith(
          lastUploadTime: DateTime.now(),
          errorMessage: null,
        ));
        
      } catch (e) {
        AppLogger.error('[UPLOAD_MANAGER] Upload failed for ${upload['type']}: $e');
        
        // Retry logic
        upload['retries'] = (upload['retries'] ?? 0) + 1;
        
        if (upload['retries'] < _maxRetries) {
          _uploadQueue.add(upload); // Re-add to queue
          AppLogger.info('[UPLOAD_MANAGER] Retrying upload (${upload['retries']}/$_maxRetries)');
        } else {
          // Save failed upload for manual retry later
          await _saveFailedUpload(upload);
          AppLogger.warning('[UPLOAD_MANAGER] Max retries exceeded, saving for later: ${upload['type']}');
        }
        
        _updateState(_currentState.copyWith(
          errorMessage: 'Upload failed: $e',
        ));
      }
    }
    
    _isProcessing = false;
    _updateState(_currentState.copyWith(isUploading: false));
  }

  Future<void> _saveOfflineLocationBatch(List<LocationPoint> locations) async {
    if (_activeSessionId == null) return;
    
    try {
      final key = 'offline_locations_$_activeSessionId';
      
      // Get existing offline locations
      final existingData = await _storageService.getObject(key);
      final existing = existingData?['locations'] as List<dynamic>? ?? [];
      
      // Add new locations
      existing.addAll(locations.map((l) => l.toJson()).toList());
      
      // Save back
      await _storageService.setObject(key, {'locations': existing});
      
      AppLogger.debug('[UPLOAD_MANAGER] Saved ${locations.length} locations offline');
      
    } catch (e) {
      AppLogger.error('[UPLOAD_MANAGER] Failed to save offline locations: $e');
    }
  }

  Future<void> _loadOfflineData() async {
    if (_activeSessionId == null) return;
    
    try {
      // Load offline location batch for current session
      final key = 'offline_locations_$_activeSessionId';
      final data = await _storageService.getObject(key);
      
      if (data != null && data['locations'] != null) {
        final locationsList = data['locations'] as List<dynamic>;
        if (locationsList.isNotEmpty) {
          final locations = locationsList.map((json) => LocationPoint.fromJson(json)).toList();
          
          _uploadQueue.add({
            'type': 'location_batch',
            'data': locations,
            'retries': 0,
          });
          
          // Remove from offline storage after adding to queue
          await _storageService.remove(key);
        }
      }
      
      AppLogger.info('[UPLOAD_MANAGER] Loaded ${_uploadQueue.length} offline items');
      
    } catch (e) {
      AppLogger.error('[UPLOAD_MANAGER] Failed to load offline data: $e');
    }
  }

  Future<void> _saveFailedUpload(Map<String, dynamic> upload) async {
    try {
      final key = 'failed_uploads';
      
      // Get existing failed uploads
      final existingData = await _storageService.getObject(key);
      final existing = existingData?['uploads'] as List<dynamic>? ?? [];
      
      // Add the failed upload
      existing.add({
        'sessionId': _activeSessionId,
        'type': upload['type'],
        'timestamp': DateTime.now().toIso8601String(),
        'data': upload['data'],
      });
      
      // Save back
      await _storageService.setObject(key, {'uploads': existing});
      
      AppLogger.debug('[UPLOAD_MANAGER] Saved failed upload for retry');
      
    } catch (e) {
      AppLogger.error('[UPLOAD_MANAGER] Failed to save failed upload: $e');
    }
  }

  /// Manually retry failed uploads
  Future<void> retryFailedUploads() async {
    try {
      final key = 'failed_uploads';
      
      // Get failed uploads
      final data = await _storageService.getObject(key);
      final failedUploads = data?['uploads'] as List<dynamic>?;
      
      if (failedUploads == null || failedUploads.isEmpty) return;
      
      AppLogger.info('[UPLOAD_MANAGER] Retrying ${failedUploads.length} failed uploads');
      
      // Add each failed upload back to the queue
      for (final upload in failedUploads) {
        _uploadQueue.add({
          'type': upload['type'],
          'data': upload['data'],
          'retries': 0,
        });
      }
      
      // Clear the failed uploads
      await _storageService.remove(key);
      
      _updateState(_currentState.copyWith(
        isUploading: true,
        pendingLocationPoints: _uploadQueue.length,
        pendingHeartRateSamples: 0,
        errorMessage: null,
      ));
      
      // Trigger processing
      _processUploadQueue();
      
    } catch (e) {
      AppLogger.error('[UPLOAD_MANAGER] Failed to retry uploads: $e');
    }
  }

  /// Upload location batch to server
  Future<void> _uploadLocationBatch(List<LocationPoint> locations) async {
    if (_activeSessionId == null || locations.isEmpty) return;
    
    // Deduplicate using uniqueId
    final seenIds = <String>{};
    final uniqueLocations = locations.where((point) {
      if (seenIds.contains(point.uniqueId)) return false;
      seenIds.add(point.uniqueId);
      return true;
    }).toList();
    
    if (uniqueLocations.isEmpty) {
      AppLogger.info('[UPLOAD_MANAGER] All points were duplicates - skipping upload');
      return;
    }
    
    AppLogger.info('[UPLOAD_MANAGER] Uploading ${uniqueLocations.length} unique location points (deduped from ${locations.length})');
    
    final locationData = uniqueLocations.map((point) => point.toJson()).toList();
    
    await _apiClient.post('/rucks/$_activeSessionId/location-batch', {
      'location_points': locationData,
      'batch_timestamp': DateTime.now().toIso8601String(),
    });
    
    AppLogger.info('[UPLOAD_MANAGER] Location batch uploaded successfully');
  }
  
  /// Upload heart rate batch to server
  Future<void> _uploadHeartRateBatch(List<Map<String, dynamic>> heartRateData) async {
    if (_activeSessionId == null || heartRateData.isEmpty) return;
    
    AppLogger.info('[UPLOAD_MANAGER] Uploading ${heartRateData.length} heart rate samples');
    
    await _apiClient.post('/rucks/$_activeSessionId/heart-rate-batch', {
      'heart_rate_samples': heartRateData,
      'batch_timestamp': DateTime.now().toIso8601String(),
    });
    
    AppLogger.info('[UPLOAD_MANAGER] Heart rate batch uploaded successfully');
  }
  
  /// Upload terrain segments to server
  Future<void> _uploadTerrainSegments(List<Map<String, dynamic>> terrainData) async {
    if (_activeSessionId == null || terrainData.isEmpty) return;
    
    AppLogger.info('[UPLOAD_MANAGER] Uploading ${terrainData.length} terrain segments');
    
    await _apiClient.post('/rucks/$_activeSessionId/terrain-batch', {
      'terrain_segments': terrainData,
      'batch_timestamp': DateTime.now().toIso8601String(),
    });
    
    AppLogger.info('[UPLOAD_MANAGER] Terrain batch uploaded successfully');
  }

  void _updateState(UploadState newState) {
    _currentState = newState;
    _stateController.add(newState);
  }

  /// Process individual upload item with timeout
  Future<void> _processUploadItem(Map<String, dynamic> uploadItem) async {
    final uploadType = uploadItem['type'] as String;
    final data = uploadItem['data'];
    
    switch (uploadType) {
      case 'location_batch':
        await _uploadLocationBatch(data as List<LocationPoint>)
            .timeout(_uploadTimeout);
        break;
      case 'heart_rate_batch':
        await _uploadHeartRateBatch(data as List<Map<String, dynamic>>)
            .timeout(_uploadTimeout);
        break;
      case 'terrain_batch':
        await _uploadTerrainSegments(data as List<Map<String, dynamic>>)
            .timeout(_uploadTimeout);
        break;
      default:
        throw Exception('Unknown upload type: $uploadType');
    }
  }
  
  /// Handle upload failure with retry logic
  Future<void> _handleUploadFailure(Map<String, dynamic> uploadItem, dynamic error) async {
    final retries = (uploadItem['retries'] as int? ?? 0) + 1;
    
    if (retries < _maxRetries) {
      // Retry the upload
      uploadItem['retries'] = retries;
      _uploadQueue.add(uploadItem);
      
      AppLogger.warning('[UPLOAD_MANAGER] Upload failed, retrying (attempt $retries/$_maxRetries): $error');
    } else {
      // Save for later retry
      await _saveFailedUpload(uploadItem);
      
      AppLogger.error('[UPLOAD_MANAGER] Upload failed after $_maxRetries attempts, saving for later: $error');
    }
  }
  
  /// Get upload statistics
  Map<String, dynamic> getUploadStats() {
    return {
      'successCount': _uploadSuccessCount,
      'failureCount': _uploadFailureCount,
      'pendingUploads': _uploadQueue.length,
      'isUploading': _isBatchUploadInProgress,
      'lastUploadTime': _lastUploadTime?.toIso8601String(),
      'uploadsByType': Map.from(_uploadStats),
      'batchUploadInterval': _batchUploadInterval.inMinutes,
    };
  }
  
  /// Update batch upload interval for performance optimization
  void updateBatchUploadInterval(Duration newInterval) {
    if (newInterval != _batchUploadInterval) {
      _batchUploadInterval = newInterval;
      
      // Restart timer with new interval
      if (_uploadTimer != null) {
        _startSophisticatedUploadTimer();
      }
      
      AppLogger.info('[UPLOAD_MANAGER] Batch upload interval updated to ${newInterval.inMinutes} minutes');
    }
  }
  
  /// Force immediate batch upload
  Future<void> forceUpload() async {
    if (_uploadQueue.isEmpty) {
      AppLogger.debug('[UPLOAD_MANAGER] No uploads to force');
      return;
    }
    
    AppLogger.info('[UPLOAD_MANAGER] Forcing immediate batch upload');
    await _processBatchUploadWithProgress();
  }
  
  /// Check if upload queue is getting too large
  bool _isQueueOverloaded() {
    return _uploadQueue.length > _maxQueueSize;
  }
  
  /// Handle queue overload by processing oldest uploads
  Future<void> _handleQueueOverload() async {
    if (!_isQueueOverloaded()) return;
    
    AppLogger.warning('[UPLOAD_MANAGER] Upload queue overloaded (${_uploadQueue.length} items), '
        'forcing immediate upload');
    
    await _processBatchUploadWithProgress();
  }

  @override
  Future<void> dispose() async {
    await _processUploadQueue();
    _uploadTimer?.cancel();
    await _stateController.close();
  }

  // Getters for coordinator
  int get pendingUploads => _uploadQueue.length;
  bool get isUploading => _currentState.isUploading;
  bool get isBatchUploadInProgress => _isBatchUploadInProgress;
  Map<String, dynamic> get uploadStats => getUploadStats();

  @override
  Future<void> checkForCrashedSession() async {
    // No-op: This manager doesn't handle session recovery
  }
  
  @override
  Future<void> clearCrashRecoveryData() async {
    // No-op: This manager doesn't handle crash recovery data
  }

}

/// Represents a task in the upload queue
class UploadTask {
  final UploadTaskType type;
  final String sessionId;
  final dynamic data;
  int retryCount;
  
  UploadTask({
    required this.type,
    required this.sessionId,
    required this.data,
    required this.retryCount,
  });
}

/// Types of upload tasks
enum UploadTaskType {
  locationBatch,
  heartRateBatch,
  sessionData,
}
