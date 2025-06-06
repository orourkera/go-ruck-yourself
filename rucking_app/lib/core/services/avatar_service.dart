import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:rucking_app/core/config/app_config.dart';
import 'package:rucking_app/core/services/auth_service.dart';

/// Service for handling avatar upload operations
class AvatarService {
  final Dio _dio;
  final AuthService _authService;

  AvatarService({
    required Dio dio,
    required AuthService authService,
  })  : _dio = dio,
        _authService = authService;

  /// Upload a user avatar image
  /// 
  /// [imageFile] - The image file to upload
  /// Returns the avatar URL from the server
  Future<String> uploadAvatar(File imageFile) async {
    try {
      // Get access token
      final token = await _authService.getToken();
      if (token == null) {
        throw Exception('No access token available');
      }

      // Read image file as bytes
      final imageBytes = await imageFile.readAsBytes();
      
      // Convert to base64
      final base64Image = base64Encode(imageBytes);
      
      // Create data URL with MIME type
      final String mimeType = _getMimeType(imageFile.path);
      final String dataUrl = 'data:$mimeType;base64,$base64Image';

      // Prepare request
      final response = await _dio.post(
        '${AppConfig.apiBaseUrl}/auth/avatar',
        data: {
          'image': dataUrl,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        return data['avatar_url'] as String;
      } else {
        throw Exception('Failed to upload avatar: ${response.statusMessage}');
      }
    } catch (e) {
      if (e is DioException) {
        if (e.response != null) {
          final errorData = e.response!.data;
          if (errorData is Map<String, dynamic> && errorData.containsKey('message')) {
            throw Exception('Avatar upload failed: ${errorData['message']}');
          }
        }
        throw Exception('Network error during avatar upload: ${e.message}');
      }
      throw Exception('Failed to upload avatar: $e');
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
}
