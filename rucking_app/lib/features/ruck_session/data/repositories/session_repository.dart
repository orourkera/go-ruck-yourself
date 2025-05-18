import 'dart:io';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_photo.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
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
  /// Takes a list of photo files and uploads them to the backend API,
  /// which handles both storage and metadata creation
  Future<List<RuckPhoto>> uploadSessionPhotos(String ruckId, List<File> photos) async {
    try {
      AppLogger.info('Uploading ${photos.length} photos for session: $ruckId');
      
      if (photos.isEmpty) {
        return [];
      }
      
      // Prepare multipart request to our new API endpoint
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${_apiClient.baseUrl}/ruck-photos'),
      );
      
      // Add the authorization header
      final authToken = await _apiClient.getAuthToken();
      request.headers.addAll({
        'Authorization': 'Bearer $authToken',
      });
      
      // Add ruck_id as a form field
      request.fields['ruck_id'] = ruckId;
      
      // Add each photo as a file
      for (final photoFile in photos) {
        final originalFilename = path.basename(photoFile.path);
        final contentType = _getContentType(photoFile.path);
        
        // Add the file to the request
        request.files.add(
          await http.MultipartFile.fromPath(
            'photos', // The field name expected by the backend
            photoFile.path,
            filename: originalFilename,
            contentType: MediaType.parse(contentType),
          ),
        );
      }
      
      // Send the request and get the response
      AppLogger.info('Sending multipart request to upload photos');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      // Parse the response
      if (response.statusCode == 201) {
        final responseData = json.decode(response.body);
        
        if (responseData is Map && 
            responseData.containsKey('data') && 
            responseData['data'] is Map && 
            responseData['data'].containsKey('photos')) {
          
          final photosList = responseData['data']['photos'] as List;
          final List<RuckPhoto> uploadedPhotos = photosList
              .map((photo) => RuckPhoto.fromJson(photo))
              .toList();
          
          AppLogger.info('Successfully uploaded ${uploadedPhotos.length} photos');
          return uploadedPhotos;
        } else {
          AppLogger.warning('Unexpected response format from photo upload: $responseData');
          return [];
        }
      } else {
        AppLogger.error('Error uploading photos. Status: ${response.statusCode}, Body: ${response.body}');
        throw Exception('Failed to upload photos: ${response.statusCode}');
      }
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
  /// 
  /// Takes a RuckPhoto object and deletes it using the backend API
  /// The backend will handle both the database record deletion and storage cleanup
  Future<bool> deletePhoto(RuckPhoto photo) async {
    try {
      AppLogger.info('Deleting photo: ${photo.id}');
      
      // Use the correct query parameter format for our new endpoint
      final response = await _apiClient.delete('/ruck-photos?photo_id=${photo.id}');
      
      // Check if deletion was successful
      if (response is Map && response.containsKey('success') && response['success'] == true) {
        AppLogger.info('Successfully deleted photo with ID: ${photo.id}');
        return true;
      } else {
        AppLogger.warning('Unexpected response when deleting photo: $response');
        return false;
      }
    } catch (e) {
      AppLogger.error('Error deleting photo: $e');
      return false;
    }
  }
}
