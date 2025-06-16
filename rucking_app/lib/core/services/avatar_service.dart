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

  /// Upload a club logo image to Supabase Storage
  /// 
  /// [imageFile] - The image file to upload
  /// Returns the public URL of the uploaded logo
  /// Note: This does NOT update user profile
  Future<String> uploadClubLogo(File imageFile) async {
    try {
      // Get authenticated user from AuthService
      final user = await _authService.getCurrentUser();
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final userId = user.userId;
      AppLogger.info('Uploading club logo by user $userId');

      // Read image file
      final bytes = await imageFile.readAsBytes();
      AppLogger.info('Image size: ${bytes.length} bytes');

      // Create unique filename for club logo with timestamp and user ID
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'club_logo_${userId}_${timestamp}.jpg';
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
      final logoUrl = supabase.storage
          .from('avatars')
          .getPublicUrl(storagePath);

      AppLogger.info('Club logo uploaded successfully: $logoUrl');
      
      // Return URL without updating user profile
      return logoUrl;
      
    } catch (e) {
      AppLogger.error('Club logo upload failed: $e');
      throw Exception('Failed to upload club logo: $e');
    }
  }

  /// Upload an event banner image to Supabase Storage
  /// 
  /// [imageFile] - The image file to upload
  /// Returns the public URL of the uploaded banner
  /// Note: This does NOT update event data - that's handled separately
  Future<String> uploadEventBanner(File imageFile) async {
    try {
      // Get authenticated user from AuthService
      final user = await _authService.getCurrentUser();
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final userId = user.userId;
      AppLogger.info('Uploading event banner by user $userId');

      // Read image file
      final bytes = await imageFile.readAsBytes();
      AppLogger.info('Image size: ${bytes.length} bytes');

      // Create unique filename for event banner with timestamp and user ID
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'event_banner_${userId}_${timestamp}.jpg';
      final storagePath = 'event_banners/$fileName';

      // Upload directly to Supabase Storage using efficient multipart
      final supabase = Supabase.instance.client;
      final storageResponse = await supabase.storage
          .from('event_banners')
          .uploadBinary(storagePath, bytes);

      if (storageResponse.isEmpty) {
        throw Exception('Failed to upload to storage');
      }

      // Get public URL
      final bannerUrl = supabase.storage
          .from('event_banners')
          .getPublicUrl(storagePath);

      AppLogger.info('Event banner uploaded successfully: $bannerUrl');
      
      // Return URL without updating event data - that's handled by the events service
      return bannerUrl;
      
    } catch (e) {
      AppLogger.error('Event banner upload failed: $e');
      throw Exception('Failed to upload event banner: $e');
    }
  }
}
