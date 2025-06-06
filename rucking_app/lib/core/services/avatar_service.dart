import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:rucking_app/core/config/app_config.dart';
import 'package:rucking_app/core/services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

/// Service for handling avatar upload operations using Supabase Storage
class AvatarService {
  final Dio _dio;
  final AuthService _authService;
  final SupabaseClient _supabase;

  AvatarService({
    required Dio dio,
    required AuthService authService,
  })  : _dio = dio,
        _authService = authService,
        _supabase = Supabase.instance.client;

  /// Upload a user avatar image directly to Supabase Storage
  /// 
  /// [imageFile] - The image file to upload
  /// Returns the public avatar URL from Supabase Storage
  Future<String> uploadAvatar(File imageFile) async {
    try {
      AppLogger.info('Starting avatar upload to Supabase Storage');
      
      // Get current user
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final userId = user.id;
      final String mimeType = _getMimeType(imageFile.path);
      final String fileName = 'avatar.${_getFileExtension(mimeType)}';
      final String filePath = '$userId/$fileName';

      AppLogger.info('Uploading avatar for user $userId to path: $filePath');

      // Read image file as bytes
      final imageBytes = await imageFile.readAsBytes();

      // Upload to Supabase Storage
      await _supabase.storage
          .from('avatars')
          .uploadBinary(
            filePath,
            imageBytes,
            fileOptions: FileOptions(
              contentType: mimeType,
              upsert: true, // Allow overwriting existing avatar
            ),
          );

      AppLogger.info('Avatar uploaded successfully to Supabase Storage');

      // Get public URL
      final publicUrl = _supabase.storage
          .from('avatars')
          .getPublicUrl(filePath);

      AppLogger.info('Generated public URL: $publicUrl');

      // Update user table with avatar URL
      await _supabase
          .from('user')
          .update({'avatar_url': publicUrl})
          .eq('id', userId);

      AppLogger.info('User avatar_url updated in database');

      return publicUrl;
    } catch (e) {
      AppLogger.error('Failed to upload avatar: $e');
      
      if (e is StorageException) {
        throw Exception('Storage error: ${e.message}');
      } else if (e is PostgrestException) {
        throw Exception('Database error: ${e.message}');
      } else {
        throw Exception('Failed to upload avatar: $e');
      }
    }
  }

  /// Get MIME type from file extension
  String _getMimeType(String filePath) {
    final extension = filePath.toLowerCase().split('.').last;
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg'; // Default fallback
    }
  }

  /// Get file extension from MIME type
  String _getFileExtension(String mimeType) {
    switch (mimeType) {
      case 'image/jpeg':
        return 'jpg';
      case 'image/png':
        return 'png';
      case 'image/gif':
        return 'gif';
      case 'image/webp':
        return 'webp';
      default:
        return 'jpg'; // Default fallback
    }
  }
}
