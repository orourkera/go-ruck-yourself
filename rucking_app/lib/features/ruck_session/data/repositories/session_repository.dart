import 'dart:io';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:rucking_app/core/services/api_client.dart'; 
import 'package:rucking_app/core/services/auth_service.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/network/api_endpoints.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_photo.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_session.dart';
import 'package:rucking_app/features/ruck_session/domain/models/heart_rate_sample.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rucking_app/core/models/api_exception.dart'; // Corrected import for ApiException
import 'dart:async'; // For Timer

/// Repository class for session-related operations
class SessionRepository {
  final ApiClient _apiClient;
  final String _supabaseUrl;
  final String _supabaseAnonKey;
  final String _photoBucketName = 'ruck-photos';
  
  // Photo caching mechanism to prevent excessive API calls
  static final Map<String, List<RuckPhoto>> _photoCache = {};
  static final Map<String, DateTime> _lastFetchTime = {};
  static final Map<String, Completer<List<RuckPhoto>>> _pendingRequests = {};
  
  // Rate limiting configuration: max 5 requests per minute per API's restriction
  static const Duration _minRequestInterval = Duration(seconds: 12); // ~5 per minute

  SessionRepository({required ApiClient apiClient})
      : _apiClient = apiClient,
        _supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '',
        _supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  // Cache for heart rate samples to avoid hitting rate limits
  static final Map<String, List<HeartRateSample>> _heartRateCache = {};
  static final Map<String, DateTime> _heartRateCacheTime = {};
  static const Duration _heartRateCacheValidity = Duration(hours: 1); // Cache for an hour
  
  /// Fetch heart rate samples for a session by its ID.
  /// This method specifically requests heart rate data from the server.
  /// Uses caching to avoid hitting rate limits (50 per hour).
  Future<List<HeartRateSample>> fetchHeartRateSamples(String sessionId) async {
    try {
      // First check if we have cached data for this session
      if (_heartRateCache.containsKey(sessionId)) {
        final cacheTime = _heartRateCacheTime[sessionId];
        final now = DateTime.now();
        
        // Check if cache is still valid (less than 1 hour old)
        if (cacheTime != null && now.difference(cacheTime) < _heartRateCacheValidity) {
          AppLogger.debug('[HEARTRATE FETCH] Using cached data for session: $sessionId');
          return _heartRateCache[sessionId]!;
        } else {
          AppLogger.debug('[HEARTRATE FETCH] Cache expired for session: $sessionId');
        }
      } else {
        AppLogger.debug('[HEARTRATE FETCH] No cache found for session: $sessionId');
      }

      AppLogger.debug('[HEARTRATE FETCH] Attempting to fetch heart rate samples from API for session: $sessionId');
      
      // Try multiple endpoint variations - according to API conventions
      // Note: No /api prefix (base URL already has it)
      List<String> endpoints = [
        '/rucks/$sessionId/heart_rate',  // Primary format with underscore (per API standards)
        '/rucks/$sessionId/heartrate'    // Alternative format without underscore
      ];
      
      dynamic response;
      String? successEndpoint;
      
      // Try each endpoint until we get a successful response
      for (final endpoint in endpoints) {
        try {
          AppLogger.debug('[HEARTRATE FETCH] Trying endpoint: $endpoint');
          response = await _apiClient.get(endpoint);
          
          if (response != null) {
            successEndpoint = endpoint;
            AppLogger.debug('[HEARTRATE FETCH] Successfully retrieved data from: $endpoint');
            break;
          }
        } catch (e) {
          // Check if this is a rate limit error (429)
          if (e.toString().contains('429')) {
            AppLogger.warning('[HEARTRATE FETCH] Rate limit hit for endpoint: $endpoint');
          } else {
            AppLogger.debug('[HEARTRATE FETCH] Endpoint failed: $endpoint - $e');
          }
          // Continue to the next endpoint
        }
      }
      
      if (response == null) {
        AppLogger.debug('[HEARTRATE FETCH] Could not retrieve heart rate data from any endpoint');
        return [];
      }
      
      // Parse heart rate samples using a more robust approach
      List<HeartRateSample> samples = [];
      
      try {
        if (response is List) {
          // Response is a direct list of samples
          AppLogger.debug('[HEARTRATE FETCH] Response is a List with ${response.length} items');
          
          // Process each sample individually to handle errors
          for (var item in response) {
            try {
              if (item is Map) {
                // Convert to Map<String, dynamic> before parsing
                final Map<String, dynamic> sampleMap = {};
                item.forEach((key, value) {
                  if (key is String) {
                    sampleMap[key] = value;
                  }
                });
                samples.add(HeartRateSample.fromJson(sampleMap));
              } else {
                AppLogger.debug('[HEARTRATE FETCH] Skipping non-map item: ${item.runtimeType}');
              }
            } catch (e) {
              AppLogger.debug('[HEARTRATE FETCH] Error parsing one sample: $e');
              // Continue with next sample
            }
          }
        } else if (response is Map && response.containsKey('heart_rate_samples')) {
          // Response is an object with heart_rate_samples field
          var samplesData = response['heart_rate_samples'];
          if (samplesData is List) {
            AppLogger.debug('[HEARTRATE FETCH] Found heart_rate_samples list with ${samplesData.length} items');
            
            for (var item in samplesData) {
              try {
                if (item is Map) {
                  // Convert to Map<String, dynamic> before parsing
                  final Map<String, dynamic> sampleMap = {};
                  item.forEach((key, value) {
                    if (key is String) {
                      sampleMap[key] = value;
                    }
                  });
                  samples.add(HeartRateSample.fromJson(sampleMap));
                } else {
                  AppLogger.debug('[HEARTRATE FETCH] Skipping non-map item in samplesData: ${item.runtimeType}');
                }
              } catch (e) {
                AppLogger.debug('[HEARTRATE FETCH] Error parsing one sample from samplesData: $e');
                // Continue with next sample
              }
            }
          } else {
            AppLogger.debug('[HEARTRATE FETCH] heart_rate_samples field is not a List: ${samplesData?.runtimeType}');
          }
        } else {
          AppLogger.debug('[HEARTRATE FETCH] Response is not a List or Map with heart_rate_samples: ${response.runtimeType}');
        }
      } catch (e) {
        AppLogger.error('[HEARTRATE FETCH] Error during samples parsing: $e');
        // Return whatever samples we managed to parse
      }
      
      AppLogger.debug('[HEARTRATE FETCH] Successfully parsed ${samples.length} heart rate samples');
      // Return the collected samples and update cache
      if (samples.isNotEmpty) {
        // Update cache with the retrieved data
        _heartRateCache[sessionId] = samples;
        _heartRateCacheTime[sessionId] = DateTime.now();
        AppLogger.debug('[HEARTRATE FETCH] Cached ${samples.length} heart rate samples for session $sessionId');
      }
      return samples;
    } catch (e) {
      AppLogger.error('[HEARTRATE FETCH] Error fetching heart rate samples: $e');
      return [];
    }
  }

  /// Fetch a ruck session by its ID, including all heart rate samples.
  Future<RuckSession?> fetchSessionById(String sessionId) async {
    try {
      AppLogger.info('DEBUGGING: Fetching session with ID: $sessionId');
      if (sessionId.isEmpty) {
        AppLogger.error('Session ID is empty');
        return null;
      }
      final response = await _apiClient.get('/rucks/$sessionId');
      AppLogger.info('DEBUGGING: Raw session response keys: ${response?.keys.toList()}');
      
      if (response == null) {
        AppLogger.error('No response from backend for session $sessionId');
        return null;
      }
      // Parse RuckSession
      final session = RuckSession.fromJson(response);
      AppLogger.info('DEBUGGING: Parsed session ${session.id} with start time ${session.startTime}');
      
      // Check if there are heart rate samples and parse them
      List<HeartRateSample> heartRateSamples = [];
      if (response.containsKey('heart_rate_samples') && response['heart_rate_samples'] != null) {
        var hrSamples = response['heart_rate_samples'] as List;
        AppLogger.info('DEBUGGING: Found ${hrSamples.length} raw heart rate samples in response');
        
        heartRateSamples = hrSamples
            .map((e) => HeartRateSample.fromJson(e as Map<String, dynamic>))
            .toList();
        AppLogger.info('DEBUGGING: Successfully parsed ${heartRateSamples.length} heart rate samples');
        
        // Add sample timestamps debug
        if (heartRateSamples.isNotEmpty) {
          AppLogger.info('DEBUGGING: First sample: ${heartRateSamples.first.timestamp}, bpm: ${heartRateSamples.first.bpm}');
          AppLogger.info('DEBUGGING: Last sample: ${heartRateSamples.last.timestamp}, bpm: ${heartRateSamples.last.bpm}');
        }
      } else {
        AppLogger.info('DEBUGGING: No heart_rate_samples field in session response');
      }
      // Return a session with samples attached
      final resultSession = session.copyWith(heartRateSamples: heartRateSamples);
      AppLogger.info('DEBUGGING: Returning session with ${resultSession.heartRateSamples?.length ?? 0} heart rate samples');
      return resultSession;
    } catch (e) {
      AppLogger.error('Error fetching session: $e');
      return null;
    }
  }
  
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
    AppLogger.debug('[PHOTO_DEBUG] SessionRepository: Attempting to fetch photos for ruckId: $ruckId');
    AppLogger.info('===== BEGIN FETCH PHOTOS DETAIL (ruckId: $ruckId) =====');
    try {
      // Ensure we're working with a valid ruckId
      if (ruckId.isEmpty) {
        AppLogger.error('[PHOTO_DEBUG] SessionRepository: Empty ruckId provided');
        throw ApiException(message: 'Invalid ruckId: empty string');
      }
      
      // The backend expects an integer ruckId
      // Make sure we're passing a clean integer value (no whitespace, etc.)
      final parsedRuckId = int.tryParse(ruckId.trim());
      if (parsedRuckId == null) {
        AppLogger.error('[PHOTO_DEBUG] SessionRepository: Unable to parse ruckId: $ruckId as integer');
        throw ApiException(message: 'Invalid ruckId format. Expected integer value, got: $ruckId');
      }
      
      final endpointPath = '/ruck-photos'; 
      final queryParams = {'ruck_id': parsedRuckId.toString()};
      AppLogger.debug('[PHOTO_DEBUG] SessionRepository: Calling API with endpoint: $endpointPath and params: $queryParams');
      
      dynamic response;
      try {
        // Make API request with detailed logging
        print('[PHOTO_DEBUG] Sending API request to $endpointPath with params $queryParams');
        response = await _apiClient.get(endpointPath, queryParams: queryParams);
        print('[PHOTO_DEBUG] Full API response: $response');
        AppLogger.debug('[PHOTO_DEBUG] SessionRepository: Received response from API: $response');
      } catch (e, stackTrace) {
        AppLogger.error('[PHOTO_DEBUG] SessionRepository: Error calling API: $e');
        AppLogger.error('[PHOTO_DEBUG] StackTrace: $stackTrace');
        print('[PHOTO_DEBUG] API call error: $e');
        rethrow; 
      }

      // Handle potential response structure variations
      if (response == null) {
        AppLogger.warning('[PHOTO_DEBUG] SessionRepository: API response is null. Returning empty list.');
        print('[PHOTO_DEBUG] API response is null, returning empty list');
        return [];
      }

      // Print the raw response to understand its structure
      print('[PHOTO_DEBUG] Raw API response type: ${response.runtimeType}');
      if (response is Map) {
        print('[PHOTO_DEBUG] Response map keys: ${response.keys.join(', ')}');
      }

      // Initialize photoDataList as an empty list to avoid null issues
      List<dynamic> photoDataList = [];
      
      if (response is Map && response.containsKey('photos') && response['photos'] is List) {
        // Handle the case where the response is {"photos": [...]} which is the most likely structure
        print('[PHOTO_DEBUG] Found "photos" key in response map');
        photoDataList = response['photos'] as List<dynamic>;
      } else if (response is Map && response.containsKey('data') && response['data'] is List) {
        AppLogger.debug('[PHOTO_DEBUG] SessionRepository: Response is a Map with "data" key, extracting data list.');
        print('[PHOTO_DEBUG] Found "data" key in response map');
        photoDataList = response['data'] as List<dynamic>;
      } else if (response is List) {
        AppLogger.debug('[PHOTO_DEBUG] SessionRepository: Response is a direct List.');
        print('[PHOTO_DEBUG] Response is a direct List');
        photoDataList = response;
      } else if (response is Map) {
        // Try to extract any list from the response as a last resort
        AppLogger.warning('[PHOTO_DEBUG] SessionRepository: Unexpected response format: ${response.runtimeType}.');
        print('[PHOTO_DEBUG] Unexpected response format, looking for any list in response');
        
        // Look for any key with a list value
        bool foundList = false;
        for (final entry in response.entries) {
          if (entry.value is List && (entry.value as List).isNotEmpty) {
            print('[PHOTO_DEBUG] Found list in response under key: ${entry.key}');
            photoDataList = entry.value as List<dynamic>;
            foundList = true;
            break;
          }
        }
        
        if (!foundList) {
          print('[PHOTO_DEBUG] No suitable list found in response, returning empty list');
          return [];
        }
      } else {
        print('[PHOTO_DEBUG] Response is not a map or list, returning empty list');
        return [];
      }

      // Print some example data to help debug the parsing
      if (photoDataList.isNotEmpty) {
        print('[PHOTO_DEBUG] First photo data: ${photoDataList.first}');
      }

      AppLogger.debug('[PHOTO_DEBUG] SessionRepository: Parsing ${photoDataList.length} photo data items.');
      final photos = photoDataList.map((photoJson) { 
        try {
          if (photoJson is Map<String, dynamic>) {
            return RuckPhoto.fromJson(photoJson);
          } else {
            print('[PHOTO_DEBUG] Photo data is not a Map: ${photoJson.runtimeType}');
            return null;
          }
        } catch (e) {
          AppLogger.error('[PHOTO_DEBUG] SessionRepository: Error parsing photo JSON: $photoJson. Error: $e');
          print('[PHOTO_DEBUG] Error parsing photo: $e');
          return null; 
        }
      }).whereType<RuckPhoto>().toList(); 
      
      AppLogger.debug('[PHOTO_DEBUG] SessionRepository: Successfully parsed ${photos.length} photos.');
      print('[PHOTO_DEBUG] Successfully processed ${photos.length} photos');
      _logPhotoDetails(photos); 
      return photos;
    } on ApiException catch (e, stackTrace) {
      AppLogger.error('[PHOTO_DEBUG] SessionRepository: ApiException: ${e.message}');
      AppLogger.error('[PHOTO_DEBUG] StackTrace: $stackTrace');
      print('[PHOTO_DEBUG] API exception: ${e.message}');
      rethrow; // Rethrow to be handled by the BLoC
    } catch (e, stackTrace) {
      AppLogger.error('[PHOTO_DEBUG] SessionRepository: Exception: $e');
      AppLogger.error('[PHOTO_DEBUG] StackTrace: $stackTrace');
      print('[PHOTO_DEBUG] General exception: $e');
      rethrow;
    } finally {
      AppLogger.info('===== END FETCH PHOTOS DETAIL (ruckId: $ruckId) =====');
    }
  }
  
  // Helper method to log photo details
  void _logPhotoDetails(List<RuckPhoto> photos) {
    AppLogger.info('PHOTO DETAILS:');
    for (int i = 0; i < photos.length; i++) {
      final photo = photos[i];
      AppLogger.info('  [$i] ID: ${photo.id}, URL: ${photo.url}');
      AppLogger.info('      Created: ${photo.createdAt}, Size: ${photo.size}, Type: ${photo.contentType}');
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
