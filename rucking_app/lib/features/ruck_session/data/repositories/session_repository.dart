import 'dart:io';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_photo.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Repository class for session-related operations
class SessionRepository {
  final ApiClient _apiClient;
  final String _supabaseUrl;
  final String _supabaseAnonKey;
  final String _photoBucketName = 'ruck-photos';
  
  SessionRepository({required ApiClient apiClient})
      : _apiClient = apiClient,
        _supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '',
        _supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';
  
  /// Delete a ruck session by its ID
  /// 
  /// Returns true if the deletion was successful, false otherwise
  Future<bool> deleteSession(String sessionId) async {
    try {
      AppLogger.info('Deleting session with ID: $sessionId');
      
      // Verify sessionId is not empty
      if (sessionId.isEmpty) {
        AppLogger.error('Session ID is empty');
        return false;
      }
      
      // Use direct DELETE operation with the correct endpoint pattern
      final response = await _apiClient.delete('/rucks/$sessionId');
      
      // The API returns the response data directly, not a Response object
      // If we get here without an exception, the deletion was successful
      AppLogger.info('Successfully deleted session: $sessionId. Response: $response');
      return true;
    } catch (e) {
      AppLogger.error('Error deleting session: $e');
      return false;
    }
  }
  
  /// Upload photos for a ruck session
  /// 
  /// Takes a list of photo files and uploads them to storage
  Future<List<RuckPhoto>> uploadSessionPhotos(String ruckId, List<File> photos) async {
    try {
      AppLogger.info('Uploading ${photos.length} photos for session: $ruckId');
      
      if (photos.isEmpty) {
        return [];
      }
      
      if (_supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty) {
        AppLogger.error('Supabase URL or Anon Key not configured');
        throw Exception('Supabase storage not properly configured');
      }
      
      final List<RuckPhoto> uploadedPhotos = [];
      
      // Get the current user ID
      final userId = await getCurrentUserId();
      if (userId == null || userId.isEmpty) {
        AppLogger.error('Unable to get current user ID for photo upload');
        throw Exception('User not authenticated');
      }
      
      // Create the necessary directories if they don't exist
      final userFolder = userId;
      final ruckFolder = ruckId;
      final uuid = const Uuid();
      
      for (final photoFile in photos) {
        final photoId = uuid.v4();
        final originalFilename = path.basename(photoFile.path);
        final ext = path.extension(originalFilename).isNotEmpty 
            ? path.extension(originalFilename) 
            : '.jpg';
        
        final filename = '$photoId$ext';
        final storagePath = '$userFolder/$ruckFolder/$filename';
        
        // Upload the file to Supabase Storage
        final uploadResult = await _uploadToSupabase(
          photoFile, 
          storagePath,
        );
        
        if (uploadResult != null) {
          // Construct URLs from storage path
          final url = '$_supabaseUrl/storage/v1/object/public/$_photoBucketName/$storagePath';
          final thumbnailUrl = '$url?width=200&height=200&resize=contain';
          
          // Create metadata entry in database
          final photoMetadata = await _createPhotoMetadata(
            photoId: photoId,
            ruckId: ruckId,
            userId: userId,
            filename: filename,
            originalFilename: originalFilename,
            contentType: uploadResult['contentType'],
            size: uploadResult['size'],
            url: url,
            thumbnailUrl: thumbnailUrl,
          );
          
          if (photoMetadata != null) {
            uploadedPhotos.add(photoMetadata);
          }
        }
      }
      
      AppLogger.info('Successfully uploaded ${uploadedPhotos.length} photos');
      return uploadedPhotos;
    } catch (e) {
      AppLogger.error('Error uploading photos: $e');
      rethrow;
    }
  }
  
  /// Upload a file to Supabase storage
  Future<Map<String, dynamic>?> _uploadToSupabase(File file, String storagePath) async {
    try {
      final fileBytes = await file.readAsBytes();
      final contentType = _getContentType(file.path);
      
      // Prepare the storage upload URL
      final url = '$_supabaseUrl/storage/v1/object/$_photoBucketName/$storagePath';
      
      // Upload file to Supabase storage
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': contentType,
          'apikey': _supabaseAnonKey,
          'Authorization': 'Bearer $_supabaseAnonKey',
        },
        body: fileBytes,
      );
      
      if (response.statusCode == 200) {
        return {
          'path': storagePath,
          'contentType': contentType,
          'size': fileBytes.length,
        };
      } else {
        AppLogger.error('Error uploading file to Supabase: ${response.body}');
        return null;
      }
    } catch (e) {
      AppLogger.error('Exception uploading to Supabase: $e');
      return null;
    }
  }
  
  /// Create metadata entry for a photo in the database
  Future<RuckPhoto?> _createPhotoMetadata({
    required String photoId,
    required String ruckId,
    required String userId,
    required String filename,
    required String originalFilename,
    required String contentType,
    required int size,
    required String url,
    required String thumbnailUrl,
  }) async {
    try {
      final data = {
        'id': photoId,
        'ruck_id': ruckId,
        'user_id': userId,
        'filename': filename,
        'original_filename': originalFilename,
        'content_type': contentType,
        'size': size,
        'url': url,
        'thumbnail_url': thumbnailUrl,
      };
      
      final response = await _apiClient.post('/ruck-photos', data);
      
      return RuckPhoto.fromJson(response);
    } catch (e) {
      AppLogger.error('Error creating photo metadata: $e');
      return null;
    }
  }
  
  /// Get the content type based on file extension
  String _getContentType(String filePath) {
    final ext = path.extension(filePath).toLowerCase();
    switch (ext) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.heic':
        return 'image/heic';
      default:
        return 'application/octet-stream';
    }
  }
  
  /// Get photos for a ruck session
  Future<List<RuckPhoto>> getSessionPhotos(String ruckId) async {
    try {
      AppLogger.info('Fetching photos for session: $ruckId');
      
      final response = await _apiClient.get('/ruck-photos?ruck_id=$ruckId');
      
      if (response is List) {
        return response.map((photo) => RuckPhoto.fromJson(photo)).toList();
      } else if (response is Map && response.containsKey('data')) {
        final List<dynamic> data = response['data'];
        return data.map((photo) => RuckPhoto.fromJson(photo)).toList();
      }
      
      return [];
    } catch (e) {
      AppLogger.error('Error fetching photos: $e');
      return [];
    }
  }
  
  /// Get the current authenticated user's ID
  /// 
  /// This checks for the user ID from API or session data
  Future<String?> getCurrentUserId() async {
    try {
      // Try to get the user profile from API
      final response = await _apiClient.get('/api/me');
      if (response != null && response['id'] != null) {
        return response['id'].toString();
      }
      
      // Fallback: try to get from shared preferences (if stored during login)
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('user_id');
    } catch (e) {
      AppLogger.error('Error getting current user ID: $e');
      return null;
    }
  }
  
  /// Delete a photo
  Future<bool> deletePhoto(RuckPhoto photo) async {
    try {
      AppLogger.info('Deleting photo: ${photo.id}');
      
      // Delete from database first
      await _apiClient.delete('/ruck-photos/${photo.id}');
      
      // Then delete from storage if database deletion was successful
      // Extract the storage path from the URL
      final Uri uri = Uri.parse(photo.url ?? '');
      final pathSegments = uri.pathSegments;
      if (pathSegments.length >= 4) {
        // Storage path should be after /storage/v1/object/public/ruck-photos/
        final storagePath = pathSegments.sublist(4).join('/');
        
        // Delete from Supabase storage
        final storageUrl = '$_supabaseUrl/storage/v1/object/$_photoBucketName/$storagePath';
        final response = await http.delete(
          Uri.parse(storageUrl),
          headers: {
            'apikey': _supabaseAnonKey,
            'Authorization': 'Bearer $_supabaseAnonKey',
          },
        );
        
        if (response.statusCode != 200) {
          AppLogger.warning('Error deleting file from storage: ${response.body}');
          // We continue even if storage deletion fails, as the metadata is already deleted
        }
      }
      
      return true;
    } catch (e) {
      AppLogger.error('Error deleting photo: $e');
      return false;
    }
  }
}
