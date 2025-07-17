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
  
  static const int _maxRetries = 3;
  
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
    } else if (event is MemoryPressureDetected) {
      await _onMemoryPressureDetected(event);
    }
  }

  Future<void> _onSessionStarted(SessionStartRequested event) async {
    _activeSessionId = event.sessionId;
    
    // Start upload timer
    _startUploadTimer();
    
    _updateState(_currentState.copyWith(
      pendingLocationPoints: 0,
      pendingHeartRateSamples: 0,
      isUploading: false,
      errorMessage: null,
    ));
    
    // Check for any pending offline uploads
    await _loadOfflineData();
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
  
  /// Handle memory pressure detection by triggering aggressive upload
  Future<void> _onMemoryPressureDetected(MemoryPressureDetected event) async {
    AppLogger.error('[UPLOAD_MANAGER] MEMORY_PRESSURE: ${event.memoryUsageMb}MB detected, triggering aggressive upload');
    
    // Trigger immediate upload of all pending data
    await _processUploadQueue();
    
    // Trigger aggressive offline data processing
    await _loadOfflineData();
    
    AppLogger.info('[UPLOAD_MANAGER] MEMORY_PRESSURE: Aggressive upload completed');
  }

  void _startUploadTimer() {
    _uploadTimer?.cancel();
    _uploadTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _processUploadQueue();
    });
  }

  Future<void> _processUploadQueue() async {
    if (_uploadQueue.isEmpty || _isProcessing) return;
    
    _isProcessing = true;
    _updateState(_currentState.copyWith(isUploading: true));
    
    while (_uploadQueue.isNotEmpty && _activeSessionId != null) {
      final upload = _uploadQueue.removeFirst();
      
      try {
        // Note: The API currently doesn't support live batch uploads
        // This is a placeholder for future implementation
        // For now, data will be uploaded on session completion
        
        AppLogger.debug('[UPLOAD_MANAGER] Queued upload processed: ${upload['type']}');
        
        _updateState(_currentState.copyWith(
          lastUploadTime: DateTime.now(),
        ));
        
      } catch (e) {
        AppLogger.error('[UPLOAD_MANAGER] Upload failed: $e');
        
        // Retry logic
        upload['retries'] = (upload['retries'] ?? 0) + 1;
        
        if (upload['retries'] < _maxRetries) {
          _uploadQueue.add(upload); // Re-add to queue
        } else {
          // Save failed upload for manual retry later
          await _saveFailedUpload(upload);
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

  void _updateState(UploadState newState) {
    _currentState = newState;
    _stateController.add(newState);
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
