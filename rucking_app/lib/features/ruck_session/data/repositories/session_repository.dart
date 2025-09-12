import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:async';
import 'dart:collection';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/auth_service.dart';
import 'package:rucking_app/core/services/app_error_handler.dart';
import 'package:get_it/get_it.dart';

import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_photo.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_session.dart';
import 'package:rucking_app/features/ruck_session/domain/models/heart_rate_sample.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:image/image.dart' as img;
import 'package:rucking_app/core/api/api_exceptions.dart';
import 'package:rucking_app/core/config/app_config.dart';
import 'package:flutter/foundation.dart' show compute;
// import 'dart:async' show unawaited; // Covered by dart:async

/// Simple semaphore for limiting concurrent operations
class Semaphore {
  final int maxCount;
  int _currentCount;
  final Queue<Completer<void>> _waitQueue = Queue<Completer<void>>();

  Semaphore(this.maxCount) : _currentCount = maxCount;

  Future<void> acquire() async {
    if (_currentCount > 0) {
      _currentCount--;
      return;
    } else {
      final completer = Completer<void>();
      _waitQueue.add(completer);
      return completer.future;
    }
  }

  void release() {
    if (_waitQueue.isNotEmpty) {
      final completer = _waitQueue.removeFirst();
      completer.complete();
    } else {
      _currentCount++;
    }
  }
}

/// Repository class for session-related operations

// Top-level function for image compression to be run in a separate isolate.
Future<String> _compressPhotoIsolateWork(String originalPhotoPath) async {
  try {
    final File originalPhoto = File(originalPhotoPath);
    final bytes = await originalPhoto.readAsBytes();

    // Check file size and skip compression for very large files to prevent GPU issues
    if (bytes.length > 50 * 1024 * 1024) {
      // 50MB limit
      print(
          'Photo too large for compression (${(bytes.length / 1024 / 1024).toStringAsFixed(1)}MB), using original');
      return originalPhotoPath;
    }

    final image = img.decodeImage(bytes);
    if (image == null)
      return originalPhotoPath; // Return original path if decoding fails
    // Resize to max 1080px on longest side (was 1920px) for faster uploads
    img.Image resized = image;
    const int maxDimension = 1080; // Reduced from 1920 to prevent timeouts
    if (image.width > maxDimension || image.height > maxDimension) {
      if (image.width > image.height) {
        resized = img.copyResize(image, width: maxDimension);
      } else {
        resized = img.copyResize(image, height: maxDimension);
      }
    }

    // Lower quality for smaller file sizes (was 80)
    final compressedBytes = img.encodeJpg(resized, quality: 60);

    final tempDir = await getTemporaryDirectory();
    final String compressedFilePath =
        '${tempDir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}_${path.basename(originalPhotoPath)}';
    final File compressedFile = File(compressedFilePath);
    await compressedFile.writeAsBytes(compressedBytes);

    final originalSize = bytes.length;
    final compressedSize = compressedBytes.length;
    final compressionRatio =
        ((originalSize - compressedSize) / originalSize * 100)
            .toStringAsFixed(1);

    // Using print as AppLogger might not be available/configured in a separate isolate.
    print(
        'Compressed photo (isolate): ${originalSize} → ${compressedSize} bytes (${compressionRatio}% reduction)');

    return compressedFilePath;
  } catch (e) {
    print('Photo compression failed in isolate, using original path: $e');
    return originalPhotoPath; // Return original path on error
  }
}

class SessionRepository {
  final ApiClient _apiClient;
  // final String _supabaseUrl; // Unused Supabase field
  // final String _supabaseAnonKey; // Unused Supabase field
  // final String _photoBucketName = 'ruck-photos'; // Unused Supabase field

  // Photo caching mechanism to prevent excessive API calls
  static final Map<String, List<RuckPhoto>> _photoCache = {};
  static final Map<String, DateTime> _lastFetchTime = {};
  static final Map<String, Completer<List<RuckPhoto>>> _pendingRequests = {};

  // Rate limiting configuration: max 5 requests per minute per API's restriction
  // static const Duration _minRequestInterval = Duration(seconds: 12); // ~5 per minute // Unused

  // Cache for heart rate samples to avoid hitting rate limits
  static final Map<String, List<HeartRateSample>> _heartRateCache = {};
  static final Map<String, DateTime> _heartRateCacheTime = {};
  static const Duration _heartRateCacheValidity =
      Duration(hours: 1); // Cache for an hour

  // Cache for session history to improve loading performance
  static List<RuckSession>? _sessionHistoryCache;
  static DateTime? _sessionHistoryCacheTime;
  static const Duration _sessionHistoryCacheValidity =
      Duration(minutes: 5); // Cache for 5 minutes

  // Cache for individual session details to avoid repeated API calls
  static final Map<String, RuckSession> _sessionDetailCache = {};
  static final Map<String, DateTime> _sessionDetailCacheTime = {};
  static const Duration _sessionDetailCacheValidity =
      Duration(minutes: 10); // Cache for 10 minutes

  SessionRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  /// Upload heart rate samples for a session
  Future<bool> uploadHeartRateSamples(
      String sessionId, List<Map<String, dynamic>> samples) async {
    try {
      if (samples.isEmpty) {
        AppLogger.debug('[HEARTRATE UPLOAD] No samples to upload');
        return true;
      }

      AppLogger.info(
          '[HEARTRATE UPLOAD] Uploading ${samples.length} heart rate samples for session: $sessionId');

      final payload = {
        'heart_rate_samples': samples,
      };

      // Use the heart-rate-chunk endpoint for batch uploads
      final response =
          await _apiClient.post('/rucks/$sessionId/heart-rate-chunk', payload);

      if (response != null) {
        AppLogger.info(
            '[HEARTRATE UPLOAD] Successfully uploaded ${samples.length} heart rate samples');
        return true;
      } else {
        AppLogger.error(
            '[HEARTRATE UPLOAD] Failed to upload heart rate samples - null response');
        return false;
      }
    } catch (e) {
      AppLogger.error(
          '[HEARTRATE UPLOAD] Error uploading heart rate samples: $e');
      return false;
    }
  }

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
        if (cacheTime != null &&
            now.difference(cacheTime) < _heartRateCacheValidity) {
          AppLogger.debug(
              '[HEARTRATE FETCH] Using cached data for session: $sessionId');
          return _heartRateCache[sessionId]!;
        } else {
          AppLogger.debug(
              '[HEARTRATE FETCH] Cache expired for session: $sessionId');
        }
      } else {
        AppLogger.debug(
            '[HEARTRATE FETCH] No cache found for session: $sessionId');
      }

      AppLogger.debug(
          '[HEARTRATE FETCH] Attempting to fetch heart rate samples from API for session: $sessionId');

      // Try multiple endpoint variations - according to API conventions
      // Note: No /api prefix (base URL already has it)
      List<String> endpoints = [
        '/rucks/$sessionId/heartrate', // Primary format WITHOUT underscore (per API standards)
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
            AppLogger.debug(
                '[HEARTRATE FETCH] Successfully retrieved data from: $endpoint');
            break;
          }
        } catch (e) {
          // Check if this is a rate limit error (429)
          if (e.toString().contains('429')) {
            AppLogger.warning(
                '[HEARTRATE FETCH] Rate limit hit for endpoint: $endpoint');
          } else {
            AppLogger.debug(
                '[HEARTRATE FETCH] Endpoint failed: $endpoint - $e');
          }
          // Continue to the next endpoint
        }
      }

      if (response == null) {
        AppLogger.debug(
            '[HEARTRATE FETCH] Could not retrieve heart rate data from any endpoint');
        return [];
      }

      // Parse heart rate samples using a more robust approach
      List<HeartRateSample> samples = [];

      try {
        if (response is List) {
          // Response is a direct list of samples
          AppLogger.debug(
              '[HEARTRATE FETCH] Response is a List with ${response.length} items');

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
                AppLogger.debug(
                    '[HEARTRATE FETCH] Skipping non-map item: ${item.runtimeType}');
              }
            } catch (e) {
              AppLogger.debug('[HEARTRATE FETCH] Error parsing one sample: $e');
              // Continue with next sample
            }
          }
        } else if (response is Map &&
            response.containsKey('heart_rate_samples')) {
          // Response is an object with heart_rate_samples field
          var samplesData = response['heart_rate_samples'];
          if (samplesData is List) {
            AppLogger.debug(
                '[HEARTRATE FETCH] Found heart_rate_samples list with ${samplesData.length} items');

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
                  AppLogger.debug(
                      '[HEARTRATE FETCH] Skipping non-map item in samplesData: ${item.runtimeType}');
                }
              } catch (e) {
                AppLogger.debug(
                    '[HEARTRATE FETCH] Error parsing one sample from samplesData: $e');
                // Continue with next sample
              }
            }
          } else {
            AppLogger.debug(
                '[HEARTRATE FETCH] heart_rate_samples field is not a List: ${samplesData?.runtimeType}');
          }
        } else {
          AppLogger.debug(
              '[HEARTRATE FETCH] Response is not a List or Map with heart_rate_samples: ${response.runtimeType}');
        }
      } catch (e) {
        AppLogger.error('[HEARTRATE FETCH] Error during samples parsing: $e');
        // Return whatever samples we managed to parse
      }

      AppLogger.debug(
          '[HEARTRATE FETCH] Successfully parsed ${samples.length} heart rate samples');
      // Return the collected samples and update cache
      if (samples.isNotEmpty) {
        // Update cache with the retrieved data
        _heartRateCache[sessionId] = samples;
        _heartRateCacheTime[sessionId] = DateTime.now();
        AppLogger.debug(
            '[HEARTRATE FETCH] Cached ${samples.length} heart rate samples for session $sessionId');
      }
      return samples;
    } catch (e) {
      AppLogger.error(
          '[HEARTRATE FETCH] Error fetching heart rate samples: $e');
      return [];
    }
  }

  /// Fetch a ruck session by its ID, including all heart rate samples.
  /// Set [forceRefresh] to true to bypass cache and fetch fresh data.
  Future<RuckSession?> fetchSessionById(String sessionId,
      {bool forceRefresh = false}) async {
    try {
      // Check if we have cached data for this session (unless force refresh is requested)
      if (!forceRefresh && _sessionDetailCache.containsKey(sessionId)) {
        final cacheTime = _sessionDetailCacheTime[sessionId];
        final now = DateTime.now();

        // Check if cache is still valid (less than 10 minutes old)
        if (cacheTime != null &&
            now.difference(cacheTime) < _sessionDetailCacheValidity) {
          AppLogger.debug(
              '[SESSION FETCH] Using cached data for session: $sessionId');
          return _sessionDetailCache[sessionId];
        } else {
          AppLogger.debug(
              '[SESSION FETCH] Cache expired for session: $sessionId');
        }
      } else {
        AppLogger.debug(
            '[SESSION FETCH] No cache found for session: $sessionId');
      }

      AppLogger.info('DEBUGGING: Fetching session with ID: $sessionId');
      if (sessionId.isEmpty) {
        AppLogger.error('Session ID is empty');
        return null;
      }
      final response = await _apiClient.get('/rucks/$sessionId');
      AppLogger.info(
          'DEBUGGING: Raw session response keys: ${response?.keys.toList()}');

      if (response == null) {
        AppLogger.error('No response from backend for session $sessionId');
        return null;
      }
      // Parse RuckSession (now includes photos from backend)
      final session = RuckSession.fromJson(response);
      AppLogger.info(
          'DEBUGGING: Parsed session ${session.id} with start time ${session.startTime}');
      AppLogger.info(
          'DEBUGGING: Session includes ${session.photos?.length ?? 0} photos from backend');

      // Check if there are heart rate samples and parse them
      List<HeartRateSample> heartRateSamples = [];
      if (response.containsKey('heart_rate_samples') &&
          response['heart_rate_samples'] != null) {
        var hrSamples = response['heart_rate_samples'] as List;
        AppLogger.info(
            'DEBUGGING: Found ${hrSamples.length} raw heart rate samples in response');

        heartRateSamples = hrSamples
            .map((e) => HeartRateSample.fromJson(e as Map<String, dynamic>))
            .toList();
        AppLogger.info(
            'DEBUGGING: Successfully parsed ${heartRateSamples.length} heart rate samples');

        // Add sample timestamps debug
        if (heartRateSamples.isNotEmpty) {
          AppLogger.info(
              'DEBUGGING: First sample: ${heartRateSamples.first.timestamp}, bpm: ${heartRateSamples.first.bpm}');
          AppLogger.info(
              'DEBUGGING: Last sample: ${heartRateSamples.last.timestamp}, bpm: ${heartRateSamples.last.bpm}');
        }
      } else {
        AppLogger.info(
            'DEBUGGING: No heart_rate_samples field in session response');

        // Try to fetch heart rate samples separately if we have aggregate data but no samples
        if (session.avgHeartRate != null && session.avgHeartRate! > 0) {
          AppLogger.info(
              'DEBUGGING: Attempting to fetch heart rate samples separately for session $sessionId');
          heartRateSamples = await fetchHeartRateSamples(sessionId);
        }
      }
      // Compute HR statistics if missing and samples are available
      RuckSession resultSession =
          session.copyWith(heartRateSamples: heartRateSamples);
      if (heartRateSamples.isNotEmpty &&
          (resultSession.avgHeartRate == null ||
              resultSession.maxHeartRate == null ||
              resultSession.minHeartRate == null)) {
        try {
          // Ensure samples are sorted (not strictly required for stats, but keeps consistency)
          final sorted = [...heartRateSamples]
            ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
          final bpmValues = sorted.map((s) => s.bpm).toList();
          final int minBpm = bpmValues.reduce((a, b) => a < b ? a : b);
          final int maxBpm = bpmValues.reduce((a, b) => a > b ? a : b);
          final int avgBpm =
              (bpmValues.fold<int>(0, (sum, v) => sum + v) / bpmValues.length)
                  .round();

          resultSession = resultSession.copyWith(
            avgHeartRate: resultSession.avgHeartRate ?? avgBpm,
            maxHeartRate: resultSession.maxHeartRate ?? maxBpm,
            minHeartRate: resultSession.minHeartRate ?? minBpm,
          );
          AppLogger.debug(
              '[HEARTRATE DEBUG] Computed HR stats - avg: ${resultSession.avgHeartRate}, max: ${resultSession.maxHeartRate}, min: ${resultSession.minHeartRate}');
        } catch (e) {
          AppLogger.warning(
              '[HEARTRATE DEBUG] Failed computing HR stats from samples: $e');
        }
      }

      AppLogger.info(
          'DEBUGGING: Returning session with ${resultSession.heartRateSamples?.length ?? 0} heart rate samples');

      // Cache the session details
      _sessionDetailCache[sessionId] = resultSession;
      _sessionDetailCacheTime[sessionId] = DateTime.now();
      AppLogger.debug('[SESSION FETCH] Cached session details for $sessionId');

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
      AppLogger.info(
          'Successfully deleted session: $sessionId. Response: $response');
      return true;
    } catch (e) {
      // Enhanced error handling with Sentry - wrapped to prevent secondary errors
      try {
        String? userId;
        try {
          userId = await getCurrentUserId();
        } catch (userIdError) {
          // If getting user ID fails, proceed with error reporting without it
          print(
              'Could not get current user ID for error reporting: $userIdError');
        }

        await AppErrorHandler.handleError(
          'session_delete',
          e,
          context: {
            'session_id': sessionId,
          },
          userId: userId,
          sendToBackend: true,
        );
      } catch (errorHandlerException) {
        // If error reporting fails, log it but don't crash the app
        print(
            'Error reporting failed during session deletion: $errorHandlerException');
      }
      return false;
    }
  }

  /// Update a ruck session with edited data (e.g., session trimming/editing)
  ///
  /// Takes a RuckSession object and updates it in the backend database
  /// This includes updating session metrics and removing extraneous data points
  /// Returns the updated session if successful, throws exception on failure
  Future<RuckSession> updateSession(RuckSession updatedSession) async {
    try {
      AppLogger.info('[SESSION_EDIT] Updating session ${updatedSession.id}');

      // Verify sessionId is not empty
      if (updatedSession.id?.isEmpty ?? true) {
        throw ApiException('Session ID is empty or null');
      }

      // Prepare the update payload
      final updatePayload = {
        'end_time': updatedSession.endTime.toIso8601String(),
        'duration_seconds': updatedSession.duration.inSeconds,
        'distance_km': updatedSession.distance,
        'elevation_gain_m': updatedSession.elevationGain,
        'elevation_loss_m': updatedSession.elevationLoss,
        'calories_burned': updatedSession.caloriesBurned,
        'average_pace_min_per_km': updatedSession.averagePace,
        'avg_heart_rate': updatedSession.avgHeartRate,
        'max_heart_rate': updatedSession.maxHeartRate,
        'min_heart_rate': updatedSession.minHeartRate,
        'location_points': updatedSession.locationPoints,
        'heart_rate_samples': updatedSession.heartRateSamples
            ?.map((sample) => {
                  'timestamp': sample.timestamp.toIso8601String(),
                  'heart_rate': sample.bpm,
                })
            .toList(),
        'splits': updatedSession.splits
            ?.map((split) => {
                  'split_number': split.splitNumber,
                  'split_distance_km': split.splitDistance,
                  'split_duration_seconds': split.splitDurationSeconds,
                  'total_distance_km': split.totalDistance,
                  'total_duration_seconds': split.totalDurationSeconds,
                  'timestamp': split.timestamp.toIso8601String(),
                })
            .toList(),
      };

      // Make the API call to update the session
      final response = await _apiClient.put(
          '/rucks/${updatedSession.id}/edit', updatePayload);

      if (response != null) {
        AppLogger.info('[SESSION_EDIT] Session updated successfully');

        // Update the local cache with the new session data
        updateSessionCache(updatedSession.id!, updatedSession);

        // Also clear session history cache to ensure it gets refreshed
        clearSessionHistoryCache();

        return updatedSession;
      } else {
        throw ApiException('Failed to update session: empty response');
      }
    } catch (e) {
      AppLogger.error(
          '[SESSION_EDIT] Error updating session ${updatedSession.id}',
          exception: e);

      // Handle specific error cases
      if (e.toString().contains('404')) {
        throw ApiException('Session not found or already deleted');
      } else if (e.toString().contains('403')) {
        throw ApiException('Not authorized to edit this session');
      } else if (e.toString().contains('400')) {
        throw ApiException('Invalid session data provided');
      }

      // Re-throw the original error for other cases
      rethrow;
    }
  }

  /// Upload photos for a ruck session
  ///
  /// Takes a list of photo files and uploads them to the backend API,
  /// which handles both storage and metadata creation
  Future<List<RuckPhoto>> uploadSessionPhotos(
      String ruckId, List<File> photos) async {
    // Create a list to hold all successfully uploaded photos
    final List<RuckPhoto> allUploadedPhotos = [];

    try {
      AppLogger.info(
          '===== START PHOTO UPLOAD (${photos.length} photos for ruckId: $ruckId) =====');

      // We can only upload 1 photo at a time over multipart form data
      // This will also help us avoid rate limits
      if (photos.isEmpty) {
        AppLogger.info('[PHOTO_DEBUG] No photos to upload');
        return [];
      }

      // Use the multi-part upload endpoint which is more efficient for photos
      AppLogger.info(
          '[PHOTO_DEBUG] Getting ready to upload photos with multipart request');

      // Process one photo at a time to avoid server timeouts and respect rate limits
      for (int i = 0; i < photos.length; i++) {
        // Declare tempCompressedPath OUTSIDE the try block so it's accessible in finally
        String? tempCompressedPath;

        try {
          final photo = photos[i];
          final exists = await photo.exists();
          final size = exists ? await photo.length() : 0;

          if (!exists || size == 0) {
            AppLogger.error('[PHOTO_DEBUG] Skipping invalid photo ${i + 1}');
            continue;
          }

          AppLogger.info(
              '[PHOTO_DEBUG] Processing photo ${i + 1}: ${photo.path}');

          // For photo upload, we need to use a direct URL approach since ApiClient's built-in
          // methods don't handle multipart form data well
          final apiHost = dotenv.env['API_HOST'] ?? 'https://getrucky.com';
          final endpoint = '/ruck-photos'; // Endpoint without /api prefix
          final url = '$apiHost/api$endpoint';

          // Get the auth token
          final authService = GetIt.I<AuthService>();
          final authToken = await authService.getToken();

          if (authToken == null || authToken.isEmpty) {
            AppLogger.error(
                '[PHOTO_DEBUG] Authentication token is null or empty!');
            throw ApiException('Authentication token is missing');
          }

          // Create a multipart request
          final request = http.MultipartRequest('POST', Uri.parse(url));

          // Add headers
          request.headers.addAll({
            'Authorization': 'Bearer $authToken',
            'Accept': 'application/json',
          });

          // Add fields
          request.fields['ruck_id'] = ruckId;

          // Upload the original file directly - we'll add proper image compression in a future update if needed
          File fileToUpload = photo;
          AppLogger.info(
              '[PHOTO_DEBUG] Original file size: ${await photo.length()} bytes for ${photo.path}');

          try {
            final tempDir = await getTemporaryDirectory();
            final targetFileName =
                '${path.basenameWithoutExtension(photo.path)}_${DateTime.now().millisecondsSinceEpoch}.jpg';
            tempCompressedPath = path.join(tempDir.path, targetFileName);

            final XFile? result = await FlutterImageCompress.compressAndGetFile(
              photo.absolute.path,
              tempCompressedPath,
              minWidth: 1920, // Max width 1920px
              minHeight: 1920, // Max height 1920px
              quality: 80, // JPEG quality 80%
              format: CompressFormat.jpeg,
            );

            if (result != null) {
              fileToUpload = File(result.path);
              AppLogger.info(
                  '[PHOTO_DEBUG] Compressed photo to: ${fileToUpload.path}, new size: ${await fileToUpload.length()} bytes');
            } else {
              AppLogger.warning(
                  '[PHOTO_DEBUG] Compression returned null, using original file: ${photo.path}');
              fileToUpload =
                  photo; // Fallback to original if compression fails or returns null
              tempCompressedPath =
                  null; // Ensure we don't try to delete a non-existent temp file
            }
          } catch (e) {
            AppLogger.error(
                '[PHOTO_DEBUG] Error during image compression for ${photo.path}: $e. Using original file.');
            fileToUpload = photo; // Fallback to original on error
            tempCompressedPath =
                null; // Ensure we don't try to delete a non-existent temp file
          }

          // Add the file
          final fileName = path.basename(fileToUpload.path);
          final contentType = _getContentType(fileToUpload.path);
          request.files.add(
            await http.MultipartFile.fromPath(
              'photos', // The field name expected by the backend
              fileToUpload.path,
              filename: fileName,
              contentType: MediaType.parse(contentType),
            ),
          );

          AppLogger.info(
              '[PHOTO_DEBUG] Sending multipart request for photo ${i + 1}');

          // Send the request
          final streamedResponse =
              await request.send().timeout(const Duration(seconds: 30));
          final response = await http.Response.fromStream(streamedResponse);

          // Handle rate limiting
          if (response.statusCode == 429) {
            AppLogger.warning(
                '[PHOTO_DEBUG] Rate limit hit (${response.body}). Waiting...');
            await Future.delayed(const Duration(
                seconds: 15)); // Wait longer to respect rate limit
            throw ApiException('Rate limit hit');
          }

          // Handle successful response
          if (response.statusCode == 200 || response.statusCode == 201) {
            AppLogger.info(
                '[PHOTO_DEBUG] Upload successful for photo ${i + 1} with status ${response.statusCode}');

            // Parse the response
            final responseData = json.decode(response.body);
            AppLogger.info(
                '[PHOTO_DEBUG] Response: ${json.encode(responseData).substring(0, math.min(100, json.encode(responseData).length))}...');

            // Try to parse response formats
            List<dynamic>? photosList;

            // Format 1: Direct response is the photo object
            if (responseData is Map &&
                responseData.containsKey('id') &&
                responseData.containsKey('url')) {
              photosList = [responseData];
              AppLogger.debug(
                  '[PHOTO_DEBUG] Found direct photo object in response');
            }
            // Format 2: {"success": true, "data": {"count": X, "photos": [...]}}
            else if (responseData is Map &&
                responseData.containsKey('success') &&
                responseData.containsKey('data')) {
              AppLogger.debug(
                  '[PHOTO_DEBUG] Found success/data format in response');
              final data = responseData['data'];
              if (data is Map && data.containsKey('photos')) {
                // Backend returns {"success": true, "data": {"count": X, "photos": [...]}}
                photosList = data['photos'] is List ? data['photos'] : null;
                AppLogger.debug(
                    '[PHOTO_DEBUG] Found photos array in data.photos');
              } else if (data is Map && data.containsKey('id')) {
                // Single photo object in data
                photosList = [data];
              } else if (data is List) {
                // Direct list in data
                photosList = data;
              }
            }
            // Format 3: Just a list of photos
            else if (responseData is List) {
              photosList = responseData;
              AppLogger.debug('[PHOTO_DEBUG] Found list format in response');
            }

            if (photosList != null) {
              // Parse each photo from the list
              List<RuckPhoto> uploadedPhotos = [];

              for (var photoData in photosList) {
                try {
                  if (photoData is Map) {
                    // Convert to Map<String, dynamic>
                    final Map<String, dynamic> photoMap = {};
                    photoData.forEach((key, value) {
                      if (key is String) {
                        photoMap[key] = value;
                      }
                    });
                    uploadedPhotos.add(RuckPhoto.fromJson(photoMap));
                  }
                } catch (e) {
                  AppLogger.error('[PHOTO_DEBUG] Error parsing photo data: $e');
                }
              }

              if (uploadedPhotos.isNotEmpty) {
                allUploadedPhotos.addAll(uploadedPhotos);
                AppLogger.info(
                    '[PHOTO_DEBUG] Successfully uploaded photo ${i + 1}');
              } else {
                AppLogger.info(
                    '[PHOTO_DEBUG] Photo ${i + 1} uploaded but no photo data in response');
              }
            } else {
              AppLogger.warning(
                  '[PHOTO_DEBUG] Photo ${i + 1} uploaded but could not find photo data in response: $response');
            }
          }
        } catch (e) {
          AppLogger.error('[PHOTO_DEBUG] Error uploading photo ${i + 1}: $e');
        } finally {
          // Clean up the temporary compressed file if it was created
          if (tempCompressedPath != null) {
            final tempFile = File(tempCompressedPath);
            if (await tempFile.exists()) {
              try {
                await tempFile.delete();
                AppLogger.info(
                    '[PHOTO_DEBUG] Deleted temporary compressed file: $tempCompressedPath');
              } catch (e) {
                AppLogger.error(
                    '[PHOTO_DEBUG] Failed to delete temporary compressed file $tempCompressedPath: $e');
              }
            }
          }
        }
      }

      AppLogger.info(
          '===== END PHOTO UPLOAD (${allUploadedPhotos.length} photos uploaded successfully) =====');
      return allUploadedPhotos;
    } catch (e) {
      // Enhanced error handling with Sentry (critical for user content)
      await AppErrorHandler.handleCriticalError(
        'session_photo_upload',
        e,
        context: {
          'ruck_id': ruckId,
          'photo_count': photos.length,
          'uploaded_count': allUploadedPhotos.length,
          'operation': 'bulk_photo_upload',
        },
        userId: await getCurrentUserId(),
      );
      rethrow;
    }
  }

  /// Upload photos for a ruck session with optimization
  ///
  /// This optimized version includes:
  /// - Image compression to reduce upload time
  /// - Parallel uploads for better performance
  /// - Better error handling and retry logic
  Future<List<RuckPhoto>> uploadSessionPhotosOptimized(
      String ruckId, List<File> photos) async {
    final List<RuckPhoto> allUploadedPhotos = [];

    try {
      AppLogger.info(
          '===== START OPTIMIZED PHOTO UPLOAD (${photos.length} photos for ruckId: $ruckId) =====');

      if (photos.isEmpty) {
        AppLogger.info('No photos to upload');
        return allUploadedPhotos;
      }

      // Compress photos in parallel first
      final compressedPhotos = await _compressPhotosInParallel(photos);
      AppLogger.info('Compressed ${compressedPhotos.length} photos for upload');

      // Upload photos in parallel (limit to 3 concurrent uploads to avoid overwhelming server)
      final uploadFutures = <Future<RuckPhoto?>>[];
      final semaphore = Semaphore(3); // Limit to 3 concurrent uploads

      for (int i = 0; i < compressedPhotos.length; i++) {
        final uploadFuture = semaphore.acquire().then((_) async {
          try {
            return await _uploadSinglePhotoOptimized(
                ruckId, compressedPhotos[i], i + 1);
          } finally {
            semaphore.release();
          }
        });
        uploadFutures.add(uploadFuture);
      }

      // Wait for all uploads to complete
      final results = await Future.wait(uploadFutures);

      // Collect successful uploads
      for (final photo in results) {
        if (photo != null) {
          allUploadedPhotos.add(photo);
        }
      }

      AppLogger.info(
          '===== OPTIMIZED PHOTO UPLOAD COMPLETED: ${allUploadedPhotos.length}/${photos.length} successful =====');
      return allUploadedPhotos;
    } catch (e) {
      AppLogger.error('Optimized photo upload failed: $e');
      return allUploadedPhotos; // Return any photos that were successfully uploaded
    }
  }

  /// Compress photos sequentially to prevent GPU memory exhaustion
  Future<List<File>> _compressPhotosInParallel(List<File> photos) async {
    final List<File> compressedPhotos = [];

    // Process photos one at a time to prevent GPU memory issues
    for (final photo in photos) {
      try {
        final compressedPhoto = await _compressPhoto(photo);
        compressedPhotos.add(compressedPhoto);

        // Small delay to allow GPU memory cleanup
        await Future.delayed(const Duration(milliseconds: 100));
      } catch (e) {
        AppLogger.error('Failed to compress photo: $e');
        compressedPhotos.add(photo); // Use original if compression fails
      }
    }

    return compressedPhotos;
  }

  /// Compress a single photo for faster upload using a separate isolate.
  Future<File> _compressPhoto(File originalPhoto) async {
    try {
      AppLogger.info('Starting compression for ${originalPhoto.path}');
      // Run the compression logic in a separate isolate.
      // Pass the file path as a String, as File objects may not be ideal for isolates.
      final String compressedPath =
          await compute(_compressPhotoIsolateWork, originalPhoto.path);

      // If compression failed in the isolate, it returns the original path.
      if (compressedPath == originalPhoto.path) {
        AppLogger.warning(
            'Photo compression returned original path for ${originalPhoto.path}, possibly due to an error in isolate.');
        return originalPhoto;
      }

      AppLogger.info(
          'Finished compression for ${originalPhoto.path}, compressed file at $compressedPath');
      return File(compressedPath);
    } catch (e) {
      AppLogger.error(
          'Error calling compute for photo compression, using original for ${originalPhoto.path}: $e');
      return originalPhoto;
    }
  }

  /// Upload a single photo with retry logic
  Future<RuckPhoto?> _uploadSinglePhotoOptimized(
      String ruckId, File photo, int photoIndex) async {
    const maxRetries = 3;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        // 🔧 PREVENT H18: Check file size before upload
        final fileSize = await photo.length();
        const maxFileSizeMB = 5; // 5MB limit to prevent timeouts
        const maxFileSizeBytes = maxFileSizeMB * 1024 * 1024;

        if (fileSize > maxFileSizeBytes) {
          await AppErrorHandler.handleWarning(
            'photo_upload_file_too_large',
            Exception(
                'File size ${(fileSize / 1024 / 1024).toStringAsFixed(1)}MB exceeds ${maxFileSizeMB}MB limit'),
            context: {
              'ruck_id': ruckId,
              'photo_index': photoIndex,
              'file_size_bytes': fileSize,
              'file_size_mb': (fileSize / 1024 / 1024).toStringAsFixed(1),
              'max_size_mb': maxFileSizeMB,
            },
            userId: await getCurrentUserId(),
          );
          throw Exception(
              'Photo file too large: ${(fileSize / 1024 / 1024).toStringAsFixed(1)}MB (max: ${maxFileSizeMB}MB)');
        }

        AppLogger.info(
            '[PHOTO_DEBUG] Uploading photo $photoIndex (attempt $attempt/$maxRetries) - Size: ${(fileSize / 1024 / 1024).toStringAsFixed(1)}MB');

        final fileName =
            'ruck_${ruckId}_photo_${photoIndex}_${DateTime.now().millisecondsSinceEpoch}.jpg';

        final request = http.MultipartRequest(
            'POST', Uri.parse('${AppConfig.apiBaseUrl}/ruck-photos'));

        // Add auth headers
        final token = await _apiClient.getToken();
        if (token != null && token.isNotEmpty) {
          request.headers['Authorization'] = 'Bearer $token';
        }

        // Add the ruck_id field - this is required by the backend
        request.fields['ruck_id'] = ruckId;

        request.files.add(
          await http.MultipartFile.fromPath(
            'photos',
            photo.path,
            filename: fileName,
            contentType: MediaType.parse(_getContentType(photo.path)),
          ),
        );

        // 🔧 REDUCED timeout to prevent H18 errors (was 90s, now 25s)
        // Heroku times out at 30s, so we fail faster and retry
        final streamedResponse =
            await request.send().timeout(const Duration(seconds: 25));
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200 || response.statusCode == 201) {
          final responseData = jsonDecode(response.body);
          AppLogger.info(
              '[PHOTO_DEBUG] Photo $photoIndex uploaded successfully');

          if (responseData is Map<String, dynamic> &&
              responseData.containsKey('photos')) {
            final photosData = responseData['photos'] as List;
            if (photosData.isNotEmpty) {
              return RuckPhoto.fromJson(photosData.first);
            }
          }
          return null;
        } else {
          AppLogger.error(
              '[PHOTO_DEBUG] Photo $photoIndex upload failed with status: ${response.statusCode}, body: ${response.body}');

          // Handle specific server errors
          if (response.statusCode >= 500) {
            AppLogger.warning(
                '[PHOTO_DEBUG] Server error detected, increasing retry delay');
          }

          if (attempt < maxRetries) {
            // Exponential backoff
            final delaySeconds = attempt * 3;
            await Future.delayed(Duration(seconds: delaySeconds));
            continue;
          }
        }
      } catch (e) {
        // 🔧 ENHANCED: Monitor H18-like errors with Sentry
        await AppErrorHandler.handleCriticalError(
          'photo_upload_timeout',
          e,
          context: {
            'ruck_id': ruckId,
            'photo_index': photoIndex,
            'attempt': attempt,
            'max_retries': maxRetries,
            'error_type': e.runtimeType.toString(),
            'is_timeout': e.toString().contains('timeout') ||
                e.toString().contains('TimeoutException'),
            'file_size_bytes': await photo.length(),
            'file_path': photo.path,
          },
          userId: await getCurrentUserId(),
        );

        AppLogger.error(
            '[PHOTO_DEBUG] Photo $photoIndex upload error (attempt $attempt): $e');

        if (attempt < maxRetries) {
          // Exponential backoff
          final delaySeconds = attempt * 3;
          AppLogger.info(
              '[PHOTO_DEBUG] Retrying photo $photoIndex in ${delaySeconds}s');
          await Future.delayed(Duration(seconds: delaySeconds));
          continue;
        }
      }
    }

    AppLogger.error(
        '[PHOTO_DEBUG] Photo $photoIndex upload failed after all retries');
    return null;
  }

  /// Upload photos in the background without blocking the UI or being tied to widget lifecycle
  void uploadSessionPhotosInBackground(String ruckId, List<File> photoFiles) {
    // Fire and forget - this runs independently of any widget
    unawaited(_performBackgroundUpload(ruckId, photoFiles));
  }

  /// Internal method to perform the actual background upload
  Future<void> _performBackgroundUpload(
      String ruckId, List<File> photoFiles) async {
    try {
      AppLogger.info(
          '[PHOTO_DEBUG] Starting independent background upload for ${photoFiles.length} photos');

      final uploadedPhotos =
          await uploadSessionPhotosOptimized(ruckId, photoFiles);

      if (uploadedPhotos.isNotEmpty) {
        // No explicit update needed: backend sets has_photos in RuckPhotosResource
        AppLogger.info(
            '[PHOTO_DEBUG] Background upload completed successfully for ${uploadedPhotos.length} photos');
      } else {
        AppLogger.warning(
            '[PHOTO_DEBUG] Background upload completed but no photos were successfully uploaded');
      }
    } catch (e) {
      AppLogger.error('[PHOTO_DEBUG] Background photo upload failed: $e');
      // Could implement retry logic or local storage for failed uploads here
      // For now, we log the error but don't disrupt the user experience
    }
  }

  /// Get photos for a ruck session
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
        return 'image/heic'; // Common on iOS
      default:
        return 'application/octet-stream'; // Fallback
    }
  }

  Future<List<RuckPhoto>> getSessionPhotos(String ruckId) async {
    AppLogger.debug(
        '[PHOTO_DEBUG] SessionRepository: Attempting to fetch photos for ruckId: $ruckId');
    AppLogger.info('===== BEGIN FETCH PHOTOS DETAIL (ruckId: $ruckId) =====');
    try {
      // Ensure we're working with a valid ruckId
      if (ruckId.isEmpty) {
        AppLogger.error(
            '[PHOTO_DEBUG] SessionRepository: Empty ruckId provided');
        throw ApiException('Invalid ruckId: empty string');
      }

      // The backend expects an integer ruckId
      // Make sure we're passing a clean integer value (no whitespace, etc.)
      final parsedRuckId = int.tryParse(ruckId.trim());
      if (parsedRuckId == null) {
        AppLogger.error(
            '[PHOTO_DEBUG] SessionRepository: Unable to parse ruckId: $ruckId as integer');
        throw ApiException(
            'Invalid ruckId format. Expected integer value, got: $ruckId');
      }

      final endpointPath = '/ruck-photos';
      final queryParams = {'ruck_id': parsedRuckId.toString()};
      AppLogger.debug(
          '[PHOTO_DEBUG] SessionRepository: Calling API with endpoint: $endpointPath and params: $queryParams');

      dynamic response;
      try {
        // Make API request with detailed logging
        print(
            '[PHOTO_DEBUG] Sending API request to $endpointPath with params $queryParams');
        response = await _apiClient.get(endpointPath, queryParams: queryParams);
        print('[PHOTO_DEBUG] Full API response: $response');
        AppLogger.debug(
            '[PHOTO_DEBUG] SessionRepository: Received response from API: $response');
      } catch (e, stackTrace) {
        AppLogger.error(
            '[PHOTO_DEBUG] SessionRepository: Error calling API: $e');
        AppLogger.error('[PHOTO_DEBUG] StackTrace: $stackTrace');
        print('[PHOTO_DEBUG] API call error: $e');
        rethrow;
      }

      // Handle potential response structure variations
      if (response == null) {
        AppLogger.warning(
            '[PHOTO_DEBUG] SessionRepository: API response is null. Returning empty list.');
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

      // From the logs, we've seen the response is: {"success": true, "data": []}
      if (response is Map &&
          response.containsKey('success') &&
          response.containsKey('data')) {
        AppLogger.debug(
            '[PHOTO_DEBUG] SessionRepository: Found standard API response with success and data keys');
        print(
            '[PHOTO_DEBUG] Found standard API response with success and data keys');

        if (response['data'] is List) {
          photoDataList = response['data'] as List<dynamic>;
          AppLogger.debug(
              '[PHOTO_DEBUG] SessionRepository: Extracted ${photoDataList.length} items from data list');
        } else {
          AppLogger.warning(
              '[PHOTO_DEBUG] SessionRepository: data key exists but is not a list: ${response['data'].runtimeType}');
        }
      } else if (response is Map &&
          response.containsKey('photos') &&
          response['photos'] is List) {
        // Handle the case where the response is {"photos": [...]} which is an alternative structure
        print('[PHOTO_DEBUG] Found "photos" key in response map');
        photoDataList = response['photos'] as List<dynamic>;
      } else if (response is Map &&
          response.containsKey('data') &&
          response['data'] is List) {
        AppLogger.debug(
            '[PHOTO_DEBUG] SessionRepository: Response is a Map with "data" key, extracting data list.');
        print('[PHOTO_DEBUG] Found "data" key in response map');
        photoDataList = response['data'] as List<dynamic>;
      } else if (response is List) {
        AppLogger.debug(
            '[PHOTO_DEBUG] SessionRepository: Response is a direct List.');
        print('[PHOTO_DEBUG] Response is a direct List');
        photoDataList = response;
      } else if (response is Map) {
        // Try to extract any list from the response as a last resort
        AppLogger.warning(
            '[PHOTO_DEBUG] SessionRepository: Unexpected response format: ${response.runtimeType}.');
        print(
            '[PHOTO_DEBUG] Unexpected response format, looking for any list in response');

        // Look for any key with a list value
        bool foundList = false;
        for (final entry in response.entries) {
          if (entry.value is List) {
            print(
                '[PHOTO_DEBUG] Found list in response under key: ${entry.key} with ${(entry.value as List).length} items');
            photoDataList = entry.value as List<dynamic>;
            foundList = true;
            break;
          }
        }

        if (!foundList) {
          print(
              '[PHOTO_DEBUG] No suitable list found in response, returning empty list');
          return [];
        }
      } else {
        print(
            '[PHOTO_DEBUG] Response is not a map or list, returning empty list');
        return [];
      }

      // Print some example data to help debug the parsing
      if (photoDataList.isNotEmpty) {
        print('[PHOTO_DEBUG] First photo data: ${photoDataList.first}');
      }

      AppLogger.debug(
          '[PHOTO_DEBUG] SessionRepository: Parsing ${photoDataList.length} photo data items.');
      final photos = photoDataList
          .map((photoJson) {
            try {
              if (photoJson is Map<String, dynamic>) {
                return RuckPhoto.fromJson(photoJson);
              } else {
                print(
                    '[PHOTO_DEBUG] Photo data is not a Map: ${photoJson.runtimeType}');
                return null;
              }
            } catch (e) {
              AppLogger.error(
                  '[PHOTO_DEBUG] SessionRepository: Error parsing photo JSON: $photoJson. Error: $e');
              print('[PHOTO_DEBUG] Error parsing photo: $e');
              return null;
            }
          })
          .whereType<RuckPhoto>()
          .toList();

      AppLogger.debug(
          '[PHOTO_DEBUG] SessionRepository: Successfully parsed ${photos.length} photos.');
      print('[PHOTO_DEBUG] Successfully processed ${photos.length} photos');
      _logPhotoDetails(photos);
      return photos;
    } on ApiException catch (e, stackTrace) {
      AppLogger.error(
          '[PHOTO_DEBUG] SessionRepository: ApiException: ${e.message}');
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
      AppLogger.info(
          '      Created: ${photo.createdAt}, Size: ${photo.size}, Type: ${photo.contentType}');
    }
  }

  // Cache the user ID to avoid repeated API calls
  String? _cachedUserId;
  DateTime? _userIdCacheTime;
  static const Duration _userIdCacheDuration = Duration(minutes: 30);

  /// Get the current authenticated user's ID with caching
  ///
  /// This checks for cached ID first, then API, then SharedPreferences
  Future<String?> getCurrentUserId() async {
    try {
      // Check if we have a valid cached user ID
      if (_cachedUserId != null &&
          _userIdCacheTime != null &&
          DateTime.now().difference(_userIdCacheTime!).abs() <
              _userIdCacheDuration) {
        return _cachedUserId;
      }

      // Try to get from SharedPreferences first (faster than API call)
      final prefs = await SharedPreferences.getInstance();
      String? userId = prefs.getString('user_id');

      // If SharedPreferences doesn't have it, try AuthService (respects caching/dedup)
      if (userId == null) {
        try {
          final authService = GetIt.instance<AuthService>();
          final user = await authService.getCurrentUser();
          if (user != null && (user.userId).isNotEmpty) {
            userId = user.userId;
            // Store in SharedPreferences for next time
            await prefs.setString('user_id', userId);
          }
        } catch (e) {
          AppLogger.debug(
              'getCurrentUserId: AuthService.getCurrentUser() failed: $e');
        }
      }

      // Cache the result if we found one
      if (userId != null) {
        _cachedUserId = userId;
        _userIdCacheTime = DateTime.now();
      }

      return userId;
    } catch (e) {
      AppLogger.error('Error getting current user ID: $e');
      // Try to return cached value even if API fails
      return _cachedUserId;
    }
  }

  /// Clear the cached user ID (call on logout)
  void clearUserIdCache() {
    _cachedUserId = null;
    _userIdCacheTime = null;
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
      final response =
          await _apiClient.delete('/ruck-photos?photo_id=${photo.id}');

      // Check if deletion was successful
      if (response is Map &&
          response.containsKey('success') &&
          response['success'] == true) {
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
          (e.toString().contains('StatusCode') &&
              e.toString().contains('404'))) {
        AppLogger.info('Photo already deleted (404): ${photo.id}');
        // Rethrow a specific error for the bloc to handle
        throw Exception('not found');
      }

      AppLogger.error('Error deleting photo: $e');
      return false;
    }
  }

  /// Fetch session history with caching for improved performance
  ///
  /// Returns a list of completed ruck sessions, cached for 5 minutes to reduce API calls
  /// Supports filtering by date ranges and pagination
  Future<List<RuckSession>> fetchSessionHistory({
    DateTime? startDate,
    DateTime? endDate,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      // Check if we have cached data that's still valid and can satisfy this request
      final now = DateTime.now();
      if (_sessionHistoryCache != null &&
          _sessionHistoryCacheTime != null &&
          now.difference(_sessionHistoryCacheTime!) <
              _sessionHistoryCacheValidity &&
          startDate == null &&
          endDate == null) {
        // Use cache for all pagination of unfiltered sessions

        AppLogger.debug(
            '[SESSION_HISTORY] Using cached session history (${_sessionHistoryCache!.length} total sessions, requesting offset=$offset, limit=$limit)');

        // Return the appropriate slice from cache
        final endIndex = offset + limit;
        if (offset < _sessionHistoryCache!.length) {
          final cacheSlice =
              _sessionHistoryCache!.skip(offset).take(limit).toList();
          AppLogger.debug(
              '[SESSION_HISTORY] Returning ${cacheSlice.length} sessions from cache (offset=$offset)');
          return cacheSlice;
        } else {
          AppLogger.debug(
              '[SESSION_HISTORY] Offset ($offset) beyond cache size (${_sessionHistoryCache!.length}), returning empty list');
          return [];
        }
      }

      // Build endpoint based on filter
      String endpoint = '/rucks';
      List<String> params = [];

      // Add pagination parameters
      params.add('limit=$limit');
      params.add('offset=$offset');

      if (startDate != null || endDate != null) {
        if (startDate != null) {
          params.add('start_date=${startDate.toIso8601String()}');
        }
        if (endDate != null) {
          params.add('end_date=${endDate.toIso8601String()}');
        }
      }

      endpoint = '/rucks?${params.join('&')}';

      AppLogger.info(
          '[SESSION_HISTORY] Fetching sessions with endpoint: $endpoint');
      final response = await _apiClient.get(endpoint);

      AppLogger.info(
          '[SESSION_HISTORY] Raw API response type: ${response?.runtimeType}');
      AppLogger.info(
          '[SESSION_HISTORY] Raw API response length/keys: ${response is List ? response.length : (response is Map ? response.keys.length : 'N/A')}');

      List<dynamic> sessionsList = [];

      // Handle different response formats from the API
      if (response == null) {
        AppLogger.warning('[SESSION_HISTORY] API response is null');
        sessionsList = [];
      } else if (response is List) {
        AppLogger.info(
            '[SESSION_HISTORY] API response is List with ${response.length} items');
        sessionsList = response;
      } else if (response is Map) {
        AppLogger.info(
            '[SESSION_HISTORY] API response is Map with keys: ${response.keys.join(', ')}');
        // Look for common API response patterns
        if (response.containsKey('data')) {
          sessionsList = response['data'] as List;
        } else if (response.containsKey('sessions')) {
          sessionsList = response['sessions'] as List;
        } else if (response.containsKey('items')) {
          sessionsList = response['items'] as List;
        } else if (response.containsKey('results')) {
          sessionsList = response['results'] as List;
        } else {
          // Try to find any List in the response
          for (final key in response.keys) {
            if (response[key] is List) {
              sessionsList = response[key] as List;
              break;
            }
          }

          if (sessionsList.isEmpty) {
            AppLogger.warning(
                '[SESSION_HISTORY] Unexpected response format from API');
          }
        }
      } else {
        AppLogger.warning('[SESSION_HISTORY] Unknown response type from API');
      }

      // Convert to RuckSession objects with debug logging
      AppLogger.info(
          '[SESSION_HISTORY] Converting ${sessionsList.length} raw sessions to RuckSession objects');
      final sessions = <RuckSession>[];

      for (int i = 0; i < sessionsList.length; i++) {
        try {
          final rawSession = sessionsList[i];
          AppLogger.debug(
              '[SESSION_HISTORY] Converting session $i: id=${rawSession['id']}, status=${rawSession['status']}');
          final session = RuckSession.fromJson(rawSession);
          sessions.add(session);
          AppLogger.debug(
              '[SESSION_HISTORY] Successfully converted session ${session.id} with status ${session.status}');
        } catch (e) {
          AppLogger.error('[SESSION_HISTORY] Failed to parse session $i: $e');
          AppLogger.error(
              '[SESSION_HISTORY] Raw session data: ${sessionsList[i]}');
        }
      }

      // Filter for completed sessions ONLY
      AppLogger.info(
          '[SESSION_HISTORY] Filtering ${sessions.length} sessions for completed status');
      final completedSessions = sessions.where((s) {
        final isCompleted = s.status == RuckStatus.completed;
        AppLogger.debug(
            '[SESSION_HISTORY] Session ${s.id}: status=${s.status}, isCompleted=$isCompleted');
        return isCompleted;
      }).toList();

      AppLogger.info(
          '[SESSION_HISTORY] Found ${completedSessions.length} completed sessions out of ${sessions.length} total');

      // Sort by date (newest first)
      completedSessions.sort((a, b) => b.startTime.compareTo(a.startTime));

      // Cache the results only for "all sessions" requests (no date filters)
      // For offset=0, replace cache completely. For offset>0, extend cache if we got new data.
      if (startDate == null && endDate == null) {
        if (offset == 0) {
          // First page - replace entire cache
          _sessionHistoryCache = completedSessions;
          _sessionHistoryCacheTime = now;
          AppLogger.debug(
              '[SESSION_HISTORY] Cached ${completedSessions.length} sessions (first page)');
        } else if (_sessionHistoryCache != null &&
            completedSessions.isNotEmpty) {
          // Subsequent page - extend cache if we have new sessions
          final existingIds = _sessionHistoryCache!.map((s) => s.id).toSet();
          final newSessions = completedSessions
              .where((s) => !existingIds.contains(s.id))
              .toList();
          if (newSessions.isNotEmpty) {
            _sessionHistoryCache!.addAll(newSessions);
            AppLogger.debug(
                '[SESSION_HISTORY] Extended cache with ${newSessions.length} new sessions (total: ${_sessionHistoryCache!.length})');
          }
        }
      }

      AppLogger.info(
          '[SESSION_HISTORY] Fetched ${completedSessions.length} completed sessions');
      return completedSessions;
    } catch (e) {
      AppLogger.error('[SESSION_HISTORY] Error fetching sessions: $e');
      rethrow;
    }
  }

  /// Clear session history cache (useful when new sessions are completed)
  static void clearSessionHistoryCache() {
    _sessionHistoryCache = null;
    _sessionHistoryCacheTime = null;
    AppLogger.debug('[SESSION_HISTORY] Cache cleared');
  }

  /// Clear cached data for specific operations
  static void clearSessionDetailCache(String sessionId) {
    _sessionDetailCache.remove(sessionId);
    _sessionDetailCacheTime.remove(sessionId);
    AppLogger.debug('[SESSION CACHE] Cleared cache for session: $sessionId');
  }

  static void clearAllSessionCaches() {
    _sessionDetailCache.clear();
    _sessionDetailCacheTime.clear();
    _sessionHistoryCache = null;
    _sessionHistoryCacheTime = null;
    AppLogger.debug('[SESSION CACHE] Cleared all session caches');
  }

  static void clearPhotoCache(String sessionId) {
    _photoCache.remove(sessionId);
    _lastFetchTime.remove(sessionId);
    _pendingRequests.remove(sessionId);
    AppLogger.debug(
        '[PHOTO CACHE] Cleared photo cache for session: $sessionId');
  }

  /// Update cached session after modification (e.g., editing notes, rating)
  static void updateSessionCache(String sessionId, RuckSession updatedSession) {
    _sessionDetailCache[sessionId] = updatedSession;
    _sessionDetailCacheTime[sessionId] = DateTime.now();

    // Also update session history cache if it exists
    if (_sessionHistoryCache != null) {
      final index = _sessionHistoryCache!.indexWhere((s) => s.id == sessionId);
      if (index != -1) {
        _sessionHistoryCache![index] = updatedSession;
      }
    }

    AppLogger.debug(
        '[SESSION CACHE] Updated cache for modified session: $sessionId');
  }

  Future<String> createManualSession(Map<String, dynamic> data) async {
    data['is_manual'] = true;
    try {
      final response = await _apiClient.post('/rucks', data);
      return response['id'].toString();
    } catch (e) {
      AppLogger.error('Failed to create manual session: $e');
      rethrow;
    }
  }
}
