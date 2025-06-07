import 'dart:io';
import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rucking_app/core/services/auth_service.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

/// Service for handling avatar upload operations using Supabase Storage
class AvatarService {
  final AuthService _authService;
  final ApiClient _apiClient;

  AvatarService({
    required AuthService authService,
    required ApiClient apiClient,
  })  : _authService = authService,
        _apiClient = apiClient;

  /// Upload a user avatar image directly to Supabase Storage
  /// 
  /// [imageFile] - The image file to upload
  /// Returns the public URL of the uploaded avatar
  Future<String> uploadAvatar(File imageFile) async {
    try {
      // Get authenticated user from AuthService
      final user = await _authService.getCurrentUser();
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final userId = user.userId;
      AppLogger.info('Uploading avatar for user $userId');

      // Read image file
      final bytes = await imageFile.readAsBytes();
      AppLogger.info('Image size: ${bytes.length} bytes');

      // Create unique filename
      final fileName = 'avatar_${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final storagePath = 'avatars/$fileName';

      // Upload directly to Supabase Storage using efficient multipart
      final supabase = Supabase.instance.client;
      final storageResponse = await supabase.storage
          .from('avatars')
          .uploadBinary(storagePath, bytes);

      if (storageResponse.isEmpty) {
        throw Exception('Failed to upload to storage');
      }

      // Get public URL
      final avatarUrl = supabase.storage
          .from('avatars')
          .getPublicUrl(storagePath);

      AppLogger.info('Avatar uploaded successfully: $avatarUrl');
      
      // Update user profile with avatar URL
      await _updateUserProfile(avatarUrl);
      
      return avatarUrl;
      
    } catch (e) {
      AppLogger.error('Avatar upload failed: $e');
      throw Exception('Failed to upload avatar: $e');
    }
  }

  /// Update user profile with avatar URL
  Future<void> _updateUserProfile(String avatarUrl) async {
    try {
      await _apiClient.put('/users/profile', {
        'avatar_url': avatarUrl,
      });
      AppLogger.info('User profile updated with avatar URL');
    } catch (e) {
      AppLogger.error('Failed to update user profile: $e');
      // Don't throw here - avatar upload succeeded, profile update is secondary
    }
  }
}
