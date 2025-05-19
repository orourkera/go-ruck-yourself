import 'dart:io';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/auth_service.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/network/api_endpoints.dart';
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
    // Create a list to hold all successfully uploaded photos
    final List<RuckPhoto> allUploadedPhotos = [];
    
    try {
      AppLogger.info('[PHOTO_UPLOAD] Starting upload of ${photos.length} photos for session: $ruckId');
      
      if (photos.isEmpty) {
        AppLogger.info('[PHOTO_UPLOAD] No photos to upload, returning empty list');
        return [];
      }
      
      // Check if any photos don't exist or are empty
      for (int i = 0; i < photos.length; i++) {
        final file = photos[i];
        final exists = await file.exists();
        final size = exists ? await file.length() : 0;
        
        AppLogger.info('[PHOTO_UPLOAD] Photo ${i+1} check: exists=$exists, size=$size bytes');
        
        if (!exists || size == 0) {
          AppLogger.error('[PHOTO_UPLOAD] Photo ${i+1} is invalid: exists=$exists, size=$size bytes');
        }
      }
      
      // Get the auth token - we'll need this for each request
      final authService = GetIt.I<AuthService>();
      final authToken = await authService.getToken();
      
      // For photo upload, we need to use a direct URL approach - we'll use the API host from .env file
      final apiHost = dotenv.env['API_HOST'] ?? 'https://getrucky.com';
      final url = '$apiHost${ApiEndpoints.ruckPhotos}';
      AppLogger.info('Uploading photos to URL: $url');
      
      // Upload each photo individually to avoid timeout issues
      for (int i = 0; i < photos.length; i++) {
        AppLogger.info('Uploading photo ${i+1} of ${photos.length}');
        final photo = photos[i];
        
        // Create a new request for each photo to prevent connection timeouts
        bool photoUploaded = false;
        int retryCount = 0;
        Exception? lastError;
        
        // Try uploading this photo up to 3 times
        while (!photoUploaded && retryCount < 3) {
          try {
            final singlePhotoRequest = http.MultipartRequest(
              'POST',
              Uri.parse(url),
            );
            
            // Add timeout settings to the request
            singlePhotoRequest.persistentConnection = false;
            
            // Add the authorization header
            if (authToken != null && authToken.isNotEmpty) {
              singlePhotoRequest.headers.addAll({
                'Authorization': 'Bearer $authToken',
              });
            }
            
            // Add ruck_id as a form field
            singlePhotoRequest.fields['ruck_id'] = ruckId;
            AppLogger.info('Added ruck_id=$ruckId to photo upload request');
            
            // Add this single photo to the request
            final originalFilename = path.basename(photo.path);
            final contentType = _getContentType(photo.path);
            
            singlePhotoRequest.files.add(
              await http.MultipartFile.fromPath(
                'photos', // The field name expected by the backend
                photo.path,
                filename: originalFilename,
                contentType: MediaType.parse(contentType),
              ),
            );
            
            // Send the request with timeout protection
            AppLogger.info('Sending request for photo ${i+1} (attempt ${retryCount+1})');
            final client = http.Client();
            try {
              final streamedResponse = await client.send(singlePhotoRequest)
                  .timeout(const Duration(seconds: 30));
              final response = await http.Response.fromStream(streamedResponse);
              
              // Handle the response
              if (response.statusCode == 201) {
                photoUploaded = true;
                final responseData = json.decode(response.body);
                
                if (responseData is Map && 
                    responseData.containsKey('data') && 
                    responseData['data'] is Map && 
                    responseData['data'].containsKey('photos')) {
                  
                  final photosList = responseData['data']['photos'] as List;
                  final List<RuckPhoto> uploadedPhotos = photosList
                      .map((photo) => RuckPhoto.fromJson(photo))
                      .toList();
                  
                  if (uploadedPhotos.isNotEmpty) {
                    allUploadedPhotos.addAll(uploadedPhotos);
                    AppLogger.info('Successfully uploaded photo ${i+1}');
                  }
                }
              } else {
                throw Exception('Photo upload failed with status: ${response.statusCode}, Body: ${response.body}');
              }
            } finally {
              client.close();
            }
          } catch (e) {
            lastError = e is Exception ? e : Exception(e.toString());
            retryCount++;
            AppLogger.error('Error uploading photo ${i+1} (attempt $retryCount): $e');
            await Future.delayed(Duration(seconds: 2 * retryCount)); // Backoff strategy
          }
        }
        
        // If we still couldn't upload this photo after retries, log it but continue with others
        if (!photoUploaded) {
          AppLogger.error('Failed to upload photo ${i+1} after 3 attempts: $lastError');
        }
      }
      
      AppLogger.info('Successfully uploaded ${allUploadedPhotos.length} photos');
      return allUploadedPhotos;
      
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
        final responseData = json.decode(response.body);
        return responseData;
      } else {
        AppLogger.error('Error uploading to Supabase: ${response.statusCode}, ${response.body}');
        return null;
      }
    } catch (e) {
      AppLogger.error('Error uploading to Supabase: $e');
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
        'photo_id': photoId,
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
        AppLogger.info('Received ${response.length} photos for session $ruckId (List format)');  
        return response.map((photo) => RuckPhoto.fromJson(photo)).toList();
      } else if (response is Map && response.containsKey('data')) {
        final List<dynamic> data = response['data'];
        AppLogger.info('Received ${data.length} photos for session $ruckId (Map format)');
        return data.map((photo) => RuckPhoto.fromJson(photo)).toList();
      } else {
        AppLogger.warning('Unexpected response format when fetching photos: $response');
        return [];
      }
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
  /// Returns true if deletion was successful, false if it failed for a reason other than 404
  /// Throws an exception with 'not found' message if the photo was already deleted (404)
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
      // Check if this is a 404 error (photo already deleted)
      if (e.toString().contains('404') || 
          e.toString().contains('not found') || 
          (e.toString().contains('StatusCode') && e.toString().contains('404'))) {
        AppLogger.info('Photo already deleted (404): ${photo.id}');
        // Rethrow a specific error for the bloc to handle
        throw Exception('not found'); 
      }
      
      AppLogger.error('Error deleting photo: $e');
      return false;
    }
  }
}
