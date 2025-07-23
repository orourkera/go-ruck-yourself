import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:get_it/get_it.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../../../core/services/auth_service.dart';
import '../../../../../core/services/storage_service.dart';
import '../../../../../core/utils/app_logger.dart';
import '../../../data/repositories/session_repository.dart';
import '../../../domain/models/ruck_photo.dart';
import '../events/session_events.dart';
import '../models/manager_states.dart';
import 'session_manager.dart';

/// Manages photo capture and storage for ruck sessions
class PhotoManager implements SessionManager {
  final SessionRepository _sessionRepository;
  final StorageService _storageService;
  final ImagePicker _imagePicker;
  
  final StreamController<PhotoState> _stateController;
  PhotoState _currentState;
  
  // Photo state
  final List<RuckPhoto> _photos = [];
  String? _activeSessionId;
  bool _isUploading = false;
  
  PhotoManager({
    required SessionRepository sessionRepository,
    required StorageService storageService,
    ImagePicker? imagePicker,
  })  : _sessionRepository = sessionRepository,
        _storageService = storageService,
        _imagePicker = imagePicker ?? ImagePicker(),
        _stateController = StreamController<PhotoState>.broadcast(),
        _currentState = const PhotoState();

  @override
  Stream<PhotoState> get stateStream => _stateController.stream;

  @override
  PhotoState get currentState => _currentState;

  @override
  Future<void> handleEvent(ActiveSessionEvent event) async {
    if (event is SessionStartRequested) {
      await _onSessionStarted(event);
    } else if (event is SessionStopRequested) {
      await _onSessionStopped(event);
    } else if (event is PhotoAdded) {
      await _onPhotoAdded(event);
    } else if (event is PhotoDeleted) {
      await _onPhotoDeleted(event);
    }
  }

  Future<void> _onSessionStarted(SessionStartRequested event) async {
    _activeSessionId = event.sessionId;
    _photos.clear();
    
    _updateState(_currentState.copyWith(
      photos: [],
      isLoading: false,
      errorMessage: null,
    ));
    
    // Load existing photos if session ID provided
    if (_activeSessionId != null && !_activeSessionId!.startsWith('offline_')) {
      await _loadPhotos();
    }
  }

  Future<void> _onSessionStopped(SessionStopRequested event) async {
    _activeSessionId = null;
    _photos.clear();
    
    _updateState(const PhotoState());
  }

  Future<void> _onPhotoAdded(PhotoAdded event) async {
    if (_activeSessionId == null) {
      AppLogger.warning('[PHOTO_MANAGER] Cannot add photo without active session');
      return;
    }
    
    _updateState(_currentState.copyWith(isLoading: true));
    
    try {
      final photoFile = File(event.photoPath);
      if (!await photoFile.exists()) {
        throw Exception('Photo file does not exist');
      }
      
      // Create photo object
      final photoId = const Uuid().v4();
      
      // Get current user ID from auth service
      final authService = GetIt.instance<AuthService>();
      final currentUser = await authService.getCurrentUser();
      final userId = currentUser?.userId ?? '';
      
      final photo = RuckPhoto(
        id: photoId,
        ruckId: _activeSessionId!,
        userId: userId,
        filename: photoId,
        createdAt: DateTime.now(),
        url: event.photoPath, // Using local path temporarily
      );
      
      _photos.add(photo);
      
      // Save photo locally
      await _savePhotoLocally(photo);
      
      // Upload photo if online session
      if (!_activeSessionId!.startsWith('offline_')) {
        await _uploadPhoto(photo);
      }
      
      _updateState(_currentState.copyWith(
        photos: List.from(_photos),
        isLoading: false,
      ));
      
      AppLogger.info('[PHOTO_MANAGER] Photo added successfully: ${photo.id}');
      
    } catch (e) {
      AppLogger.error('[PHOTO_MANAGER] Failed to add photo: $e');
      _updateState(_currentState.copyWith(
        isLoading: false,
        errorMessage: 'Failed to add photo: $e',
      ));
    }
  }

  Future<void> _onPhotoDeleted(PhotoDeleted event) async {
    if (_activeSessionId == null) return;
    
    try {
      // Remove from local list
      _photos.removeWhere((p) => p.id == event.photoId);
      
      // Delete from server if online session
      if (!_activeSessionId!.startsWith('offline_')) {
        AppLogger.info('[PHOTO_MANAGER] Photo deletion not yet implemented on backend');
      }
      
      // Delete local file
      RuckPhoto? photo;
      try {
        photo = _photos.firstWhere((p) => p.id == event.photoId);
      } catch (e) {
        // Photo not found in local list, create fallback photo
        final authService = GetIt.instance<AuthService>();
        final currentUser = await authService.getCurrentUser();
        final userId = currentUser?.userId ?? '';
        
        photo = RuckPhoto(
          id: event.photoId,
          ruckId: _activeSessionId!,
          userId: userId,
          filename: 'photo_${event.photoId}.jpg',
          createdAt: DateTime.now(),
        );
      }
      if (photo.url != null && photo.url!.startsWith('/')) {
        // Local file path
        final file = File(photo.url!);
        if (await file.exists()) {
          await file.delete();
        }
      }
      
      _updateState(_currentState.copyWith(
        photos: List.from(_photos),
      ));
      
      AppLogger.info('[PHOTO_MANAGER] Photo deleted: ${event.photoId}');
      
    } catch (e) {
      AppLogger.error('[PHOTO_MANAGER] Failed to delete photo: $e');
      _updateState(_currentState.copyWith(
        errorMessage: 'Failed to delete photo',
      ));
    }
  }

  Future<void> _loadPhotos() async {
    if (_activeSessionId == null) return;
    
    _updateState(_currentState.copyWith(isLoading: true));
    
    try {
      final photos = await _sessionRepository.getSessionPhotos(_activeSessionId!);
      _photos.clear();
      _photos.addAll(photos);
      
      _updateState(_currentState.copyWith(
        photos: List.from(_photos),
        isLoading: false,
      ));
      
      AppLogger.info('[PHOTO_MANAGER] Loaded ${photos.length} photos');
      
    } catch (e) {
      AppLogger.error('[PHOTO_MANAGER] Failed to load photos: $e');
      _updateState(_currentState.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load photos',
      ));
    }
  }

  Future<void> _savePhotoLocally(RuckPhoto photo) async {
    try {
      // Save photo metadata to local storage
        final photosKey = 'session_${photo.ruckId}_photos';
        final existingPhotosJson = await _storageService.getString(photosKey);
        final existingPhotos = existingPhotosJson != null ? List<Map<String, dynamic>>.from(jsonDecode(existingPhotosJson)) : [];
        existingPhotos.add(photo.toJson());
        await _storageService.setString(photosKey, jsonEncode(existingPhotos));
      
    } catch (e) {
      AppLogger.error('[PHOTO_MANAGER] Failed to save photo locally: $e');
    }
  }

  Future<void> _uploadPhoto(RuckPhoto photo) async {
    try {
      if (_isUploading || photo.url == null || !photo.url!.startsWith('/')) return;
      
      _isUploading = true;
      
      // Upload photo to server
      try {
        AppLogger.info('[PHOTO_MANAGER] Uploading photo to backend: ${photo.filename}');
        
        // Read the image file
        final imageFile = File(photo.url!);
        if (!await imageFile.exists()) {
          throw Exception('Photo file not found: ${photo.url}');
        }
        
        // Upload to backend using session repository with compression
        final uploadedPhotos = await _sessionRepository.uploadSessionPhotosOptimized(
          photo.ruckId,
          [imageFile],  // Pass as single-item list
        );
        
        if (uploadedPhotos.isNotEmpty) {
          // Update photo with server URL
          final uploadedPhoto = uploadedPhotos.first;
          final index = _photos.indexWhere((p) => p.id == photo.id);
          if (index != -1) {
            _photos[index] = uploadedPhoto;
          }
          final uploadedPhotoUrl = uploadedPhoto.url;
          AppLogger.info('[PHOTO_MANAGER] Photo uploaded successfully: $uploadedPhotoUrl');
        } else {
          throw Exception('Photo upload failed - no photos returned');
        }
        
        _updateState(_currentState.copyWith(
          photos: List.from(_photos),
        ));
        
      } catch (e) {
        AppLogger.error('[PHOTO_MANAGER] Failed to upload photo: $e');
        _updateState(_currentState.copyWith(
          errorMessage: 'Failed to upload photo',
        ));
      } finally {
        _isUploading = false;
      }
      
    } catch (e) {
      AppLogger.error('[PHOTO_MANAGER] Error in photo upload: $e');
    }
  }

  /// Take a photo using the device camera
  Future<void> takePhoto() async {
    if (_activeSessionId == null) {
      AppLogger.warning('[PHOTO_MANAGER] Cannot take photo without active session');
      return;
    }
    
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 85,
      );
      
      if (image != null) {
        handleEvent(PhotoAdded(photoPath: image.path));
      }
      
    } catch (e) {
      AppLogger.error('[PHOTO_MANAGER] Failed to take photo: $e');
      _updateState(_currentState.copyWith(
        errorMessage: 'Failed to take photo',
      ));
    }
  }

  /// Select a photo from gallery
  Future<void> selectPhoto() async {
    if (_activeSessionId == null) {
      AppLogger.warning('[PHOTO_MANAGER] Cannot select photo without active session');
      return;
    }
    
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      
      if (image != null) {
        handleEvent(PhotoAdded(photoPath: image.path));
      }
      
    } catch (e) {
      AppLogger.error('[PHOTO_MANAGER] Failed to select photo: $e');
      _updateState(_currentState.copyWith(
        errorMessage: 'Failed to select photo',
      ));
    }
  }

  void _updateState(PhotoState newState) {
    _currentState = newState;
    _stateController.add(newState);
  }

  @override
  Future<void> dispose() async {
    await _stateController.close();
  }
  
  @override
  Future<void> checkForCrashedSession() async {
    // No-op: PhotoManager doesn't handle session recovery
  }
  
  @override
  Future<void> clearCrashRecoveryData() async {
    // No-op: PhotoManager doesn't handle crash recovery data  
  }

  // Getters for coordinator
  List<RuckPhoto> get photos => List.unmodifiable(_photos);
  bool get isPhotosLoading => _currentState.isLoading;
}
