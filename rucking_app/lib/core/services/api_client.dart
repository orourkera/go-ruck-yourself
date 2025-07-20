import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:rucking_app/core/services/storage_service.dart';
import 'package:rucking_app/core/api/api_exceptions.dart';
import 'package:rucking_app/core/config/app_config.dart';
import 'package:flutter/foundation.dart';
import 'package:rucking_app/features/ruck_buddies/domain/entities/user_info.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:jwt_decode/jwt_decode.dart';

/// Client for handling API requests to the backend
class ApiClient {
  // Note: Dio is already configured with the base URL in service_locator.dart
  final Dio _dio;
  late final StorageService _storageService;
  
  // Callback to refresh token via auth service (with circuit breaker)
  Function()? _tokenRefreshCallback;
  
  // Prevent simultaneous refresh attempts
  bool _isRefreshing = false;
  final List<Completer<void>> _refreshCompleters = [];

  ApiClient(this._dio) {
    // Add logging interceptor only in debug mode
    if (kDebugMode) {
      _dio.interceptors.add(LogInterceptor(
        requestHeader: true,
        requestBody: true,
        // Don't log request headers in debug to avoid exposing auth tokens
        responseHeader: false,
        responseBody: true,
        error: true,
        // Custom log function to avoid printing sensitive data
        logPrint: (log) {
          // Redact Authorization header and tokens from logs
          String logStr = log.toString();
          if (logStr.contains('Authorization')) {
            logStr = logStr.replaceAll(RegExp(r'Bearer [a-zA-Z0-9\._-]+'), 'Bearer [REDACTED]');
          }
          debugPrint('[API] $logStr');
        }
      ));
    }
    
    // Add simplified token refresh interceptor
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (error, handler) async {
          // Handle unauthorized errors (401) that indicate token expiration
          if (error.response?.statusCode == 401) {
            // Skip token refresh for requests that are already token refresh attempts
            if (error.requestOptions.path.contains('/auth/refresh')) {
              debugPrint('[API] Skipping refresh for refresh token request');
              return handler.next(error);
            }
            
            debugPrint('[API] Authentication error (401). Attempting coordinated refresh...');
            
            // Use auth service's refresh method (with circuit breaker and coordination)
            if (_tokenRefreshCallback != null) {
              try {
                await _coordinatedRefresh();
                // If refresh succeeded, retry the original request
                debugPrint('[API] Coordinated refresh completed. Retrying original request...');
                final response = await _dio.fetch(error.requestOptions);
                return handler.resolve(response);
              } catch (refreshError) {
                debugPrint('[API] Coordinated refresh failed: $refreshError');
                return handler.next(error);
              }
            } else {
              debugPrint('[API] No token refresh callback available');
              return handler.next(error);
            }
          }
          
          return handler.next(error);
        },
      ),
    );
  }
  
  /// Coordinates token refresh to prevent multiple simultaneous attempts
  Future<void> _coordinatedRefresh() async {
    if (_isRefreshing) {
      // If refresh is already in progress, wait for it to complete
      debugPrint('[API] Refresh already in progress, waiting...');
      final completer = Completer<void>();
      _refreshCompleters.add(completer);
      return completer.future;
    }
    
    _isRefreshing = true;
    try {
      debugPrint('[API] Starting coordinated token refresh...');
      await _tokenRefreshCallback!();
      debugPrint('[API] Coordinated token refresh successful');
      
      // Notify all waiting requests
      for (final completer in _refreshCompleters) {
        completer.complete();
      }
      _refreshCompleters.clear();
    } catch (error) {
      debugPrint('[API] Coordinated token refresh failed: $error');
      
      // Notify all waiting requests of failure
      for (final completer in _refreshCompleters) {
        completer.completeError(error);
      }
      _refreshCompleters.clear();
      rethrow;
    } finally {
      _isRefreshing = false;
    }
  }
  
  /// Set the storage service after it has been initialized
  void setStorageService(StorageService storageService) {
    _storageService = storageService;
  }
  
  /// Gets the auth token, attempting to refresh if necessary
  Future<String?> getToken() async {
    // Get the token from storage, if not found or empty, try to refresh it
    final token = await _storageService.getSecureString(AppConfig.tokenKey);
    if (token == null || token.isEmpty) {
      // Attempt token refresh as a recovery mechanism
      debugPrint('[API] Token not found in storage, attempting refresh');
      try {
        return await refreshToken();
      } catch (e) {
        debugPrint('[API] Refresh attempt failed during getToken: $e');
        return null;
      }
    }
    return token;
  }
  
  /// Refreshes the authentication token
  Future<String?> refreshToken() async {
    // Retry logic for long sessions - attempt refresh up to 3 times with exponential backoff
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        final refreshToken = await _storageService.getSecureString(AppConfig.refreshTokenKey);
        if (refreshToken == null || refreshToken.isEmpty) {
          debugPrint('[API] No refresh token available for refresh (attempt $attempt)');
          return null;
        }
        
        // Create a new Dio instance to avoid interceptor loops
        final refreshDio = Dio(_dio.options);
        // Add timeouts to avoid hanging on slow networks
        refreshDio.options.connectTimeout = const Duration(seconds: 60);
        refreshDio.options.receiveTimeout = const Duration(seconds: 60);
        
        debugPrint('[API] Attempting token refresh via dedicated method (attempt $attempt/3)');
        final response = await refreshDio.post(
          '/auth/refresh',
          data: {'refresh_token': refreshToken},
        );
        
        if (response.statusCode == 200 && response.data != null) {
          final newToken = response.data['token'] as String;
          final newRefreshToken = response.data['refresh_token'] as String;
          
          if (newToken.isNotEmpty && newRefreshToken.isNotEmpty) {
            // Save the new tokens
            await _storageService.setSecureString(AppConfig.tokenKey, newToken);
            await _storageService.setSecureString(AppConfig.refreshTokenKey, newRefreshToken);
            
            // Update the token in Dio
            setAuthToken(newToken);
            
            debugPrint('[API] Token refreshed successfully via refreshToken method (attempt $attempt)');
            return newToken;
          } else {
            debugPrint('[API] Received empty tokens from refresh response (attempt $attempt)');
          }
        } else {
          debugPrint('[API] Token refresh failed with status: ${response.statusCode} (attempt $attempt)');
        }
        
      } catch (e) {
        debugPrint('[API] Error refreshing token (attempt $attempt/3): $e');
        
        // For network errors, wait before retrying (exponential backoff)
        if (attempt < 3 && (e is DioException && 
            (e.type == DioExceptionType.connectionError || 
             e.type == DioExceptionType.connectionTimeout))) {
          final waitTime = Duration(seconds: attempt * 2); // 2s, 4s for attempts 1,2
          debugPrint('[API] Network error, waiting ${waitTime.inSeconds}s before retry...');
          await Future.delayed(waitTime);
          continue; // Retry
        }
      }
      
      // If we reach here on the last attempt, all retries failed
      if (attempt == 3) {
        debugPrint('[API] All token refresh attempts failed, but maintaining user session');
      }
    }
    
    // Return null instead of throwing - maintains user session
    return null;
  }
  
  /// Sets the authentication token for subsequent requests
  void setAuthToken(String token) {
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }
  
  /// Clears the authentication token
  void clearAuthToken() {
    _dio.options.headers.remove('Authorization');
  }

  /// Ensures the auth token is present for authenticated requests
  /// Returns true if token was set successfully
  Future<bool> _ensureAuthToken() async {
    // Check if the token is already set in the Dio instance
    if (_dio.options.headers.containsKey('Authorization')) {
      // Verify the token format and expiration
      String authHeader = _dio.options.headers['Authorization'] as String;
      if (authHeader.startsWith('Bearer ') && authHeader.length > 10) {
        final tokenPart = authHeader.substring(7); // Remove 'Bearer ' prefix
        
        // Check if token is expired
        try {
          if (Jwt.isExpired(tokenPart)) {
            debugPrint('[API] Current token is expired, clearing and refreshing');
            _dio.options.headers.remove('Authorization');
          } else {
            // Token is valid and not expired
            return true;
          }
        } catch (e) {
          // Invalid token format, clear it
          debugPrint('[API] Invalid JWT token format detected, clearing: $e');
          _dio.options.headers.remove('Authorization');
        }
      } else {
        // Invalid header format, clear it and try again
        debugPrint('[API] Invalid auth header format detected, clearing');
        _dio.options.headers.remove('Authorization');
      }
    }
    
    // If not set or invalid/expired, try to get it from storage
    final token = await _storageService.getSecureString(AppConfig.tokenKey);
    if (token != null && token.isNotEmpty) {
      // Validate the token from storage before using it
      try {
        if (!Jwt.isExpired(token)) {
          // Token is valid and not expired, set it
          setAuthToken(token);
          return true;
        } else {
          debugPrint('[API] Stored token is expired, attempting refresh');
        }
      } catch (e) {
        debugPrint('[API] Invalid stored JWT token: $e');
      }
    }
    
    // No valid token in storage, try to refresh it
    final newToken = await refreshToken();
    if (newToken != null && newToken.isNotEmpty) {
      return true; // refreshToken already sets the auth header
    }
    
    debugPrint('[API] No valid auth token available');
    return false;
  }
  
  /// Makes a GET request to the API
  Future<dynamic> get(String endpoint, {Map<String, dynamic>? queryParams}) async {
    try {
      // Determine if this request should include an auth token.
      // By default, ALL API routes require authentication unless they are
      // explicitly public (e.g. /auth/*, /public/*, /users/register).
      final bool isPublicEndpoint =
          endpoint.startsWith('/auth/') || endpoint == '/users/register';

      if (!isPublicEndpoint) {
        final hasToken = await _ensureAuthToken();
        if (!hasToken) {
          throw UnauthorizedException('Not authenticated - please log in first');
        }
      }
      
      // Set timeout to prevent hanging requests
      final options = Options(
        headers: await _getHeaders(),
        sendTimeout: const Duration(seconds: 45),
        receiveTimeout: const Duration(seconds: 45),
      );
      
      // Make API call
      final response = await _dio.get(
        endpoint,
        queryParameters: queryParams,
        options: options,
      );
      
      return response.data;
    } catch (e) {
      throw _handleError(e);
    }
  }
  
  /// Makes a POST request to the specified endpoint with the given body
  Future<dynamic> post(String endpoint, dynamic body) async {
    try {
      // Require token for /rucks/*, /users/*, /achievements/*, and /duels/* endpoints, EXCEPT for /users/register
      bool requiresAuth = ((endpoint.startsWith('/rucks') || endpoint.startsWith('/users/') || endpoint.startsWith('/achievements/') || endpoint.startsWith('/duels/')) && 
                        endpoint != '/users/register') ||
                        endpoint.startsWith('/duel-') ||
                        endpoint == '/device-token'; // Ensure device token registration is authenticated
      // Explicitly do not set auth token for /auth/refresh endpoint
      bool excludeAuth = endpoint == '/auth/refresh';
                          
      if (requiresAuth && !excludeAuth) {
        final hasToken = await _ensureAuthToken();
        if (!hasToken) {
          throw UnauthorizedException('Not authenticated - please log in first');
        }
      }
      
      // Debug logging for /auth/refresh request
      if (endpoint == '/auth/refresh') {
        AppLogger.sessionCompletion('Sending refresh token request to $endpoint', context: {
          'request_body': body,
        });
        AppLogger.sessionCompletion('Request body: $body', context: {});
      }
      
      // Set timeout to prevent hanging requests
      final options = Options(
        headers: await _getHeaders(),
        // For /auth/refresh, explicitly remove the Authorization header if it exists
        validateStatus: (status) {
          return status != null && status < 500;
        },
        sendTimeout: const Duration(seconds: 45),
        receiveTimeout: const Duration(seconds: 45),
      );
      if (excludeAuth) {
        options.headers?.remove('Authorization');
      }
      
      final response = await _dio.post(
        endpoint,
        data: body,
        options: options,
      );
      
      // Debug logging for /auth/refresh response
      if (endpoint == '/auth/refresh') {
        AppLogger.sessionCompletion('Refresh token response status: ${response.statusCode}', context: {});
        AppLogger.sessionCompletion('Refresh token response body: ${response.data}', context: {});
      }
      
      return response.data;
    } catch (e) {
      throw _handleError(e);
    }
  }
  
  /// Makes a PUT request to the specified endpoint with the given body
  Future<dynamic> put(String endpoint, Map<String, dynamic> body) async {
    try {
      // Determine if this request should include an auth token.
      // By default, ALL API routes require authentication unless they are
      // explicitly public (e.g. /auth/*, /public/*, /users/register).
      final bool isPublicEndpoint =
          endpoint.startsWith('/auth/') || endpoint == '/users/register';

      if (!isPublicEndpoint) {
        final hasToken = await _ensureAuthToken();
        if (!hasToken) {
          throw UnauthorizedException('Not authenticated - please log in first');
        }
      }

      final response = await _dio.put(
        endpoint,
        data: body,
        options: Options(
          headers: await _getHeaders(),
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      
      return response.data;
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Makes a PATCH request to the specified endpoint with the given body
  Future<dynamic> patch(String endpoint, Map<String, dynamic> body) async {
    try {
      // Determine if this request should include an auth token.
      // By default, ALL API routes require authentication unless they are
      // explicitly public (e.g. /auth/*, /public/*, /users/register).
      final bool isPublicEndpoint =
          endpoint.startsWith('/auth/') || endpoint == '/users/register';

      if (!isPublicEndpoint) {
        final hasToken = await _ensureAuthToken();
        if (!hasToken) {
          throw UnauthorizedException('Not authenticated - please log in first');
        }
      }

      final response = await _dio.patch(
        endpoint,
        data: body,
        options: Options(
          headers: await _getHeaders(),
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      return response.data;
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Makes a DELETE request to the specified endpoint
  Future<dynamic> delete(String endpoint) async {
    try {
      // Determine if this request should include an auth token.
      // By default, ALL API routes require authentication unless they are
      // explicitly public (e.g. /auth/*, /public/*, /users/register).
      final bool isPublicEndpoint =
          endpoint.startsWith('/auth/') || endpoint == '/users/register';

      if (!isPublicEndpoint) {
        final hasToken = await _ensureAuthToken();
        if (!hasToken) {
          throw UnauthorizedException('Not authenticated - please log in first');
        }
      }

      final response = await _dio.delete(
        endpoint,
        options: Options(
          headers: await _getHeaders(),
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      return response.data;
    } catch (e) {
      throw _handleError(e);
    }
  }

  
  /// Makes a POST request to add a location point to a ruck session
  Future<dynamic> addLocationPoint(String ruckId, Map<String, dynamic> locationData) async {
    return await post('/rucks/$ruckId/location', locationData);
  }
  
  /// Makes a POST request to add multiple location points to a ruck session (batch)
  Future<dynamic> addLocationPoints(String ruckId, List<Map<String, dynamic>> locationPoints) async {
    return await post('/rucks/$ruckId/location', {'points': locationPoints});
  }

  /// Makes a POST request to add heart rate samples to a ruck session
  Future<dynamic> addHeartRateSamples(String ruckId, List<Map<String, dynamic>> heartRateSamples) async {
    // Match the pattern of addLocationPoint, which is working
    // The base URL already handles the /api prefix correctly
    return await post('/rucks/$ruckId/heartrate', {'samples': heartRateSamples});
  }
  
  /// Fetches the current authenticated user's profile
  Future<UserInfo> getCurrentUserProfile() async {
    try {
      // Ensure the token is available before making the request
      // The generic 'get' method will handle adding the auth token to headers if configured
      final response = await get('/users/profile'); 
      // Assuming response is a Map<String, dynamic> representing the user
      return UserInfo.fromJson(response as Map<String, dynamic>);
    } catch (e) {
      // Log or handle the error appropriately
      AppLogger.sessionCompletion('Error fetching current user profile', context: {
        'error': e.toString(),
      });
      // Re-throw or return a default/error UserInfo object if needed
      throw _handleError(e); 
    }
  }
  
  /// Fetches a specific user's public profile by ID
  Future<UserInfo> getUserProfile(String userId) async {
    try {
      // Fix the endpoint path to avoid duplicate /api/api/ issue
      final response = await get('/users/$userId');
      return UserInfo.fromJson(response as Map<String, dynamic>);
    } catch (e) {
      AppLogger.sessionCompletion('Error fetching user profile ($userId)', context: {
        'error': e.toString(),
      });
      throw _handleError(e);
    }
  }
  
  /// Returns headers for API requests
  Future<Map<String, String>> _getHeaders() async {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    
    // Use the token already set in Dio options if available
    if (_dio.options.headers.containsKey('Authorization')) {
      headers['Authorization'] = _dio.options.headers['Authorization'] as String;
    }
    
    return headers;
  }
  
  /// Returns options for API requests (including headers)
  Future<Options> _getOptions() async {
    return Options(
      headers: await _getHeaders(),
    );
  }
  
  /// Converts API exceptions to app-specific exceptions
  Exception _handleError(dynamic error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return TimeoutException('Connection timed out');
          
        case DioExceptionType.connectionError:
          return NetworkException('No internet connection');
          
        case DioExceptionType.badResponse:
          final statusCode = error.response?.statusCode;
          final data = error.response?.data;
          
          // Check if the response is HTML (typically means wrong API URL)
          if (data is String && data.contains('<!doctype html>')) {
            final url = error.requestOptions.uri.toString();
            if (statusCode == 404) {
              return NotFoundException('API endpoint not found. Check that your server is running and the URL is correct.');
            }
          }
          
          switch (statusCode) {
            case 400:
              return BadRequestException(data is Map ? data['message'] ?? 'Bad request' : 'Bad request');
            case 401:
              return UnauthorizedException(data is Map ? data['message'] ?? 'Unauthorized' : 'Unauthorized');
            case 403:
              return ForbiddenException(data is Map ? data['message'] ?? 'Forbidden' : 'Forbidden');
            case 404:
              return NotFoundException(data is Map ? data['message'] ?? 'Resource not found' : 'Resource not found');
            case 409:
              return ConflictException(data is Map ? data['message'] ?? 'Conflict' : 'Conflict');
            case 500:
            case 501:
            case 502:
            case 503:
              return ServerException(data is Map ? data['message'] ?? 'Server error' : 'Server error');
            default:
              return ApiException(data is Map ? data['message'] ?? 'API error: $statusCode' : 'API error: $statusCode');
          }
        
        default:
          return ApiException(error.message ?? 'Unknown API error');
      }
    }
    
    return ApiException('Unexpected error: $error');
  }
  
  /// Sets the token refresh callback
  void setTokenRefreshCallback(Function() callback) {
    _tokenRefreshCallback = callback;
  }
  
  /// Special POST method for session completion with chunked upload support
  /// Handles large payloads by optionally splitting them into smaller chunks
  Future<dynamic> postSessionCompletion(String path, Map<String, dynamic> data) async {
    try {
      await _ensureAuthToken();
      
      // Check payload size and chunk if necessary
      final payloadSize = data.toString().length;
      AppLogger.sessionCompletion('Session completion payload size check', context: {
        'payload_size_bytes': payloadSize,
        'path': path,
      });
      
      // If payload is large (>1MB), use chunked upload approach
      if (payloadSize > 1048576) { // 1MB threshold
        return await _chunkedSessionCompletion(path, data);
      }
      
      // For smaller payloads, use enhanced single request with longer timeouts
      return await _singleRequestSessionCompletion(path, data);
      
    } catch (e) {
      throw _handleError(e);
    }
  }
  
  /// Single request completion with enhanced timeouts for session completion
  Future<dynamic> _singleRequestSessionCompletion(String path, Map<String, dynamic> data) async {
    AppLogger.sessionCompletion('Using single request completion', context: {
      'path': path,
      'payload_size_bytes': data.toString().length,
    });
    
    final options = Options(
      headers: await _getHeaders(),
      // Extended timeouts for session completion
      sendTimeout: const Duration(minutes: 3), // 3 minutes for large uploads
      receiveTimeout: const Duration(minutes: 2), // 2 minutes for response
    );
    
    final response = await _dio.post(path, data: data, options: options);
    AppLogger.sessionCompletion('Single request completion response', context: {
      'response_status': response.statusCode,
      'response_data': response.data,
    });
    return response.data;
  }
  
  /// Chunked upload for very large session completion payloads
  Future<dynamic> _chunkedSessionCompletion(String path, Map<String, dynamic> data) async {
    AppLogger.sessionCompletion('Using chunked upload completion', context: {
      'path': path,
      'original_payload_size_bytes': data.toString().length,
    });
    
    // Split large arrays into chunks
    final Map<String, dynamic> baseData = Map.from(data);
    final List<dynamic> route = baseData.remove('route') ?? [];
    final List<dynamic> heartRateSamples = baseData.remove('heart_rate_samples') ?? [];
    
    // First, send base session data
    AppLogger.sessionCompletion('Sending base session data', context: {
      'base_data_size_bytes': baseData.toString().length,
    });
    
    final response = await _dio.post(
      path, 
      data: baseData,
      options: Options(
        headers: await _getHeaders(),
        sendTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
    AppLogger.sessionCompletion('Base session data response', context: {
      'response_status': response.statusCode,
      'response_data': response.data,
    });
    final sessionId = _extractSessionIdFromPath(path);
    
    // Then upload route data in chunks if it exists
    if (route.isNotEmpty) {
      await _uploadRouteDataInChunks(sessionId, route);
    }
    
    // Upload heart rate data in chunks if it exists  
    if (heartRateSamples.isNotEmpty) {
      await _uploadHeartRateDataInChunks(sessionId, heartRateSamples);
    }
    
    AppLogger.sessionCompletion('Chunked upload completed successfully', context: {
      'session_id': sessionId,
      'route_points': route.length,
      'heart_rate_samples': heartRateSamples.length,
    });
    
    return response.data;
  }
  
  /// Upload route data in manageable chunks
  Future<void> _uploadRouteDataInChunks(String sessionId, List<dynamic> route) async {
    const chunkSize = 100; // 100 location points per chunk
    
    for (int i = 0; i < route.length; i += chunkSize) {
      final chunk = route.skip(i).take(chunkSize).toList();
      
      AppLogger.sessionCompletion('Uploading route chunk', context: {
        'session_id': sessionId,
        'chunk_start': i,
        'chunk_size': chunk.length,
      });
      
      await _dio.post(
        '/rucks/$sessionId/route-chunk',
        data: {'route_points': chunk, 'chunk_index': i ~/ chunkSize},
        options: Options(
          headers: await _getHeaders(),
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      AppLogger.sessionCompletion('Route chunk uploaded', context: {
        'session_id': sessionId,
        'chunk_start': i,
        'chunk_size': chunk.length,
      });
    }
  }
  
  /// Upload heart rate data in manageable chunks
  Future<void> _uploadHeartRateDataInChunks(String sessionId, List<dynamic> heartRateSamples) async {
    const chunkSize = 50; // 50 heart rate samples per chunk
    
    for (int i = 0; i < heartRateSamples.length; i += chunkSize) {
      final chunk = heartRateSamples.skip(i).take(chunkSize).toList();
      
      AppLogger.sessionCompletion('Uploading heart rate chunk', context: {
        'session_id': sessionId,
        'chunk_start': i,
        'chunk_size': chunk.length,
      });
      
      await _dio.post(
        '/rucks/$sessionId/heart-rate-chunk',
        data: {'heart_rate_samples': chunk, 'chunk_index': i ~/ chunkSize},
        options: Options(
          headers: await _getHeaders(),
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      AppLogger.sessionCompletion('Heart rate chunk uploaded', context: {
        'session_id': sessionId,
        'chunk_start': i,
        'chunk_size': chunk.length,
      });
    }
  }
  
  /// Extract session ID from completion path
  String _extractSessionIdFromPath(String path) {
    final match = RegExp(r'/rucks/([^/]+)/complete').firstMatch(path);
    return match?.group(1) ?? 'unknown';
  }

  /// Sends a test notification via the backend API
  Future<Map<String, dynamic>> sendTestNotification() async {
    try {
      final response = await post('/test-notification', {});
      return response;
    } catch (e) {
      AppLogger.debug('[API] Test notification failed: $e');
      rethrow;
    }
  }
}