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
import 'package:jwt_decoder/jwt_decoder.dart';

/// Client for handling API requests to the backend
class ApiClient {
  // Note: Dio is already configured with the base URL in service_locator.dart
  late final Dio _dio;
  final StorageService _storageService;

  // Prevent concurrent refresh attempts
  static Future<String?>? _refreshFuture;
  static DateTime? _lastRefreshAttempt;
  static const Duration _refreshCooldown = Duration(seconds: 30);

  // Token refresh coordination
  Function()? _tokenRefreshCallback;
  bool _isRefreshing = false;
  final List<Completer<void>> _refreshCompleters = [];

  ApiClient(this._storageService, this._dio) {
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
              logStr = logStr.replaceAll(
                  RegExp(r'Bearer [a-zA-Z0-9\._-]+'), 'Bearer [REDACTED]');
            }
            debugPrint('[API] $logStr');
          }));
    }

    // Add simplified token refresh interceptor
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (error, handler) async {
          // Handle unauthorized errors (401) that indicate token expiration
          if (error.response?.statusCode == 401) {
            // Skip token refresh for requests that are already token refresh attempts
            if (error.requestOptions.path.contains('/auth/refresh')) {
              debugPrint(
                  '[API] Skipping refresh for refresh token request - auth token is invalid');
              return handler.next(error);
            }

            debugPrint(
                '[API] Authentication error (401). Attempting coordinated refresh...');

            // Use auth service's refresh method (with circuit breaker and coordination)
            if (_tokenRefreshCallback != null) {
              try {
                await _coordinatedRefresh();
                // If refresh succeeded, retry the original request with updated token
                debugPrint(
                    '[API] Coordinated refresh completed. Retrying original request...');

                // Get the updated token and set it in the request headers
                final newToken =
                    await _storageService.getSecureString(AppConfig.tokenKey);
                if (newToken != null && newToken.isNotEmpty) {
                  error.requestOptions.headers['Authorization'] =
                      'Bearer $newToken';
                  final response = await _dio.fetch(error.requestOptions);
                  return handler.resolve(response);
                } else {
                  debugPrint(
                      '[API] No valid token after refresh, failing request');
                  return handler.next(error);
                }
              } catch (refreshError) {
                debugPrint('[API] Coordinated refresh failed: $refreshError');
                // If refresh fails, clear invalid tokens to prevent infinite loops
                await _storageService.removeSecure(AppConfig.tokenKey);
                await _storageService.removeSecure(AppConfig.refreshTokenKey);
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
    // Prevent concurrent refresh attempts - return existing future if refresh in progress
    if (_refreshFuture != null) {
      debugPrint(
          '[API] Refresh already in progress, waiting for existing attempt');
      return await _refreshFuture!;
    }

    // Check cooldown period to prevent rapid retry storms
    if (_lastRefreshAttempt != null &&
        DateTime.now().difference(_lastRefreshAttempt!) < _refreshCooldown) {
      debugPrint('[API] Refresh cooldown active, skipping attempt');
      return null;
    }

    // Create shared future for this refresh attempt
    _refreshFuture = _performRefresh();
    _lastRefreshAttempt = DateTime.now();

    try {
      final result = await _refreshFuture!;
      return result;
    } finally {
      _refreshFuture = null;
    }
  }

  /// Performs the actual token refresh with retry logic
  Future<String?> _performRefresh() async {
    // Retry logic for long sessions - attempt refresh up to 3 times with exponential backoff
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        final refreshToken =
            await _storageService.getSecureString(AppConfig.refreshTokenKey);
        if (refreshToken == null || refreshToken.isEmpty) {
          debugPrint(
              '[API] No refresh token available for refresh (attempt $attempt)');
          return null;
        }

        // Validate refresh token before using it
        try {
          if (JwtDecoder.isExpired(refreshToken)) {
            debugPrint('[API] Refresh token is expired, cannot refresh');
            await _storageService.removeSecure(AppConfig.tokenKey);
            await _storageService.removeSecure(AppConfig.refreshTokenKey);
            clearAuthToken();
            return null;
          }
        } catch (e) {
          debugPrint('[API] Invalid refresh token format: $e');
          await _storageService.removeSecure(AppConfig.tokenKey);
          await _storageService.removeSecure(AppConfig.refreshTokenKey);
          clearAuthToken();
          return null;
        }

        // Create a new Dio instance to avoid interceptor loops
        final refreshDio = Dio(_dio.options);
        // Add extended timeouts for token refresh to handle poor network conditions
        refreshDio.options.connectTimeout = const Duration(seconds: 120);
        refreshDio.options.receiveTimeout = const Duration(seconds: 120);
        // Remove auth header from refresh dio to prevent loops
        refreshDio.options.headers.remove('Authorization');

        debugPrint(
            '[API] Attempting token refresh via dedicated method (attempt $attempt/3)');
        final response = await refreshDio.post(
          '/auth/refresh',
          data: {'refresh_token': refreshToken},
        );

        if (response.statusCode == 200 && response.data != null) {
          final responseData = response.data as Map<String, dynamic>;
          final newToken = responseData['token'] as String?;
          final newRefreshToken = responseData['refresh_token'] as String?;

          if (newToken != null && newToken.isNotEmpty &&
              newRefreshToken != null && newRefreshToken.isNotEmpty) {

            // Validate new token before saving
            try {
              if (!JwtDecoder.isExpired(newToken) &&
                  JwtDecoder.getRemainingTime(newToken).inSeconds > 60) {
                // Save the new tokens
                await _storageService.setSecureString(AppConfig.tokenKey, newToken);
                await _storageService.setSecureString(
                    AppConfig.refreshTokenKey, newRefreshToken);

                // Update the token in Dio
                setAuthToken(newToken);

                debugPrint(
                    '[API] Token refreshed successfully via refreshToken method (attempt $attempt)');
                return newToken;
              } else {
                debugPrint(
                    '[API] Received expired/expiring token from refresh response (attempt $attempt)');
              }
            } catch (e) {
              debugPrint('[API] Received invalid token format from refresh: $e');
            }
          } else {
            debugPrint(
                '[API] Received null/empty tokens from refresh response (attempt $attempt)');
          }
        } else {
          debugPrint(
              '[API] Token refresh failed with status: ${response.statusCode} (attempt $attempt)');
        }
      } catch (e) {
        debugPrint('[API] Error refreshing token (attempt $attempt/3): $e');

        // For 401 errors (invalid/expired refresh token), clear tokens and stop retrying
        if (e is DioException && e.response?.statusCode == 401) {
          debugPrint(
              '[API] Refresh token invalid/expired (401) - clearing stored tokens');
          await _storageService.removeSecure(AppConfig.tokenKey);
          await _storageService.removeSecure(AppConfig.refreshTokenKey);
          clearAuthToken();
          break; // Don't retry with invalid refresh token
        }

        // For rate limit (429) or network errors, wait before retrying (exponential backoff)
        if (attempt < 3 &&
            (e is DioException &&
                (e.type == DioExceptionType.connectionError ||
                    e.type == DioExceptionType.connectionTimeout ||
                    e.type == DioExceptionType.receiveTimeout ||
                    e.type == DioExceptionType.sendTimeout ||
                    e.response?.statusCode == 429 ||
                    e.response?.statusCode == 503 ||
                    e.response?.statusCode == 502))) {
          final waitTime =
              Duration(seconds: attempt * 5); // 5s, 10s for attempts 1,2
          debugPrint(
              '[API] Error ${e.response?.statusCode ?? e.type}, waiting ${waitTime.inSeconds}s before retry...');
          await Future.delayed(waitTime);
          continue; // Retry
        }
      }

      // If we reach here on the last attempt, all retries failed
      if (attempt == 3) {
        debugPrint(
            '[API] All token refresh attempts failed, but maintaining user session');
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
    debugPrint(
        '[API] 🔑 _ensureAuthToken called - checking current auth state');

    // Check if the token is already set in the Dio instance
    if (_dio.options.headers.containsKey('Authorization')) {
      debugPrint('[API] 🔑 Found Authorization header in Dio instance');
      // Verify the token format and expiration
      String authHeader = _dio.options.headers['Authorization'] as String;
      if (authHeader.startsWith('Bearer ') && authHeader.length > 10) {
        final tokenPart = authHeader.substring(7); // Remove 'Bearer ' prefix

        // Check if token is expired with buffer time
        try {
          // Add 30 second buffer to prevent edge case expiration during request
          if (JwtDecoder.isExpired(tokenPart) ||
              JwtDecoder.getRemainingTime(tokenPart).inSeconds <= 30) {
            debugPrint(
                '[API] 🔑 Current token is expired/expiring soon, clearing and refreshing');
            _dio.options.headers.remove('Authorization');
          } else {
            // Token is valid and not expired
            debugPrint('[API] 🔑 Current token is valid and not expiring soon');
            return true;
          }
        } catch (e) {
          // Invalid token format, clear it and report error
          debugPrint(
              '[API] 🔑 Invalid JWT token format detected, clearing: $e');
          _dio.options.headers.remove('Authorization');
          // Clear invalid token from storage too
          await _storageService.removeSecure(AppConfig.tokenKey);
        }
      } else {
        // Invalid header format, clear it and try again
        debugPrint('[API] 🔑 Invalid auth header format detected, clearing');
        _dio.options.headers.remove('Authorization');
      }
    } else {
      debugPrint('[API] 🔑 No Authorization header found in Dio instance');
    }

    // If not set or invalid/expired, try to get it from storage
    debugPrint('[API] 🔑 Checking token in storage');
    final token = await _storageService.getSecureString(AppConfig.tokenKey);
    if (token != null && token.isNotEmpty) {
      debugPrint('[API] 🔑 Found token in storage, validating');
      // Validate the token from storage before using it
      try {
        // Add buffer time to prevent edge case expiration
        if (!JwtDecoder.isExpired(token) &&
            JwtDecoder.getRemainingTime(token).inSeconds > 30) {
          // Token is valid and not expiring soon, set it
          debugPrint('[API] 🔑 Stored token is valid, setting as auth token');
          setAuthToken(token);
          return true;
        } else {
          debugPrint('[API] 🔑 Stored token is expired/expiring soon, attempting refresh');
          // Clear expired token from storage
          await _storageService.removeSecure(AppConfig.tokenKey);
        }
      } catch (e) {
        debugPrint('[API] 🔑 Invalid stored JWT token: $e');
        // Clear invalid token from storage
        await _storageService.removeSecure(AppConfig.tokenKey);
      }
    } else {
      debugPrint('[API] 🔑 No token found in storage');
    }

    // No valid token in storage, try to refresh it
    debugPrint(
        '[API] 🔑 Attempting token refresh via ApiClient.refreshToken()');
    try {
      final newToken = await refreshToken();
      if (newToken != null && newToken.isNotEmpty) {
        debugPrint('[API] 🔑 Token refresh successful');
        return true; // refreshToken already sets the auth header
      }
    } catch (e) {
      debugPrint('[API] 🔑 ApiClient refresh failed: $e');
      // Continue to try AuthService callback
    }

    // If ApiClient refresh failed, try the AuthService refresh callback as a fallback
    if (_tokenRefreshCallback != null) {
      debugPrint(
          '[API] 🔑 ApiClient refresh failed, trying AuthService refresh callback');
      try {
        await _tokenRefreshCallback!();
        // Check if the callback successfully set a new token
        final refreshedToken =
            await _storageService.getSecureString(AppConfig.tokenKey);
        if (refreshedToken != null && refreshedToken.isNotEmpty) {
          try {
            if (!JwtDecoder.isExpired(refreshedToken) &&
                JwtDecoder.getRemainingTime(refreshedToken).inSeconds > 30) {
              debugPrint(
                  '[API] 🔑 AuthService refresh successful, setting token');
              setAuthToken(refreshedToken);
              return true;
            } else {
              debugPrint('[API] 🔑 AuthService provided expired/expiring token');
            }
          } catch (e) {
            debugPrint('[API] 🔑 AuthService provided invalid token: $e');
          }
        }
      } catch (e) {
        debugPrint('[API] 🔑 AuthService refresh callback failed: $e');
      }
    }

    debugPrint(
        '[API] 🔑 No valid auth token available - AUTHENTICATION WILL FAIL');
    return false;
  }

  /// Makes a GET request to the API
  Future<dynamic> get(String endpoint,
      {Map<String, dynamic>? queryParams}) async {
    try {
      // Determine if this request should include an auth token.
      // By default, ALL API routes require authentication unless they are
      // explicitly public (e.g. /auth/*, /public/*, /users/register).
      final bool isPublicEndpoint =
          endpoint.startsWith('/auth/') || endpoint == '/users/register';

      if (!isPublicEndpoint) {
        final hasToken = await _ensureAuthToken();
        if (!hasToken) {
          throw UnauthorizedException(
              'Not authenticated - please log in first');
        }
      }

      // Set timeout to prevent hanging requests
      final options = Options(
        headers: await _getHeaders(),
        sendTimeout: const Duration(seconds: 45),
        receiveTimeout: const Duration(seconds: 45),
      );

      String fullEndpoint = endpoint;
      if (AppConfig.useRustAchievements &&
          endpoint.startsWith('/achievements')) {
        fullEndpoint = 'http://localhost:8080$endpoint'; // Or deployed Rust URL
      }
      // Make API call
      final response = await _dio.get(
        fullEndpoint,
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
      // Require token for rucks/*, users/*, achievements/*, and duels/* endpoints, EXCEPT for users/register
      bool requiresAuth = ((endpoint.startsWith('/rucks') ||
                  endpoint.startsWith('/users/') ||
                  endpoint.startsWith('/achievements/') ||
                  endpoint.startsWith('/duels/') ||
                  endpoint.startsWith('/goals')) &&
              endpoint != '/users/register') ||
          endpoint.startsWith('/duel-') ||
          endpoint.startsWith('/observability') ||
          endpoint ==
              '/device-token'; // Ensure device token registration is authenticated
      // Explicitly do not set auth token for auth/refresh endpoint
      bool excludeAuth = endpoint == '/auth/refresh';

      if (requiresAuth && !excludeAuth) {
        final hasToken = await _ensureAuthToken();
        if (!hasToken) {
          throw UnauthorizedException(
              'Not authenticated - please log in first');
        }
      }

      // Debug logging for auth/refresh request
      if (endpoint == '/auth/refresh') {
        AppLogger.sessionCompletion(
            'Sending refresh token request to $endpoint',
            context: {
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

      String fullEndpoint = endpoint;
      if (AppConfig.useRustAchievements &&
          endpoint.startsWith('/achievements')) {
        fullEndpoint = 'http://localhost:8080$endpoint';
      }
      final response = await _dio.post(
        fullEndpoint,
        data: body,
        options: options,
      );

      // Debug logging for /auth/refresh response
      if (endpoint == '/auth/refresh') {
        AppLogger.sessionCompletion(
            'Refresh token response status: ${response.statusCode}',
            context: {});
        AppLogger.sessionCompletion(
            'Refresh token response body: ${response.data}',
            context: {});
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
          throw UnauthorizedException(
              'Not authenticated - please log in first');
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
          throw UnauthorizedException(
              'Not authenticated - please log in first');
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
          throw UnauthorizedException(
              'Not authenticated - please log in first');
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
  Future<dynamic> addLocationPoint(
      String ruckId, Map<String, dynamic> locationData) async {
    return await post('/rucks/$ruckId/location', locationData);
  }

  /// Makes a POST request to add multiple location points to a ruck session (batch)
  Future<dynamic> addLocationPoints(
      String ruckId, List<Map<String, dynamic>> locationPoints) async {
    return await post('/rucks/$ruckId/location', {'points': locationPoints});
  }

  /// Makes a POST request to add heart rate samples to a ruck session
  Future<dynamic> addHeartRateSamples(
      String ruckId, List<Map<String, dynamic>> heartRateSamples) async {
    // Match the pattern of addLocationPoint, which is working
    // The base URL already handles the /api prefix correctly
    return await post(
        '/rucks/$ruckId/heartrate', {'samples': heartRateSamples});
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
      AppLogger.sessionCompletion('Error fetching current user profile',
          context: {
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
      AppLogger.sessionCompletion('Error fetching user profile ($userId)',
          context: {
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
      headers['Authorization'] =
          _dio.options.headers['Authorization'] as String;
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
              return NotFoundException(
                  'API endpoint not found. Check that your server is running and the URL is correct.');
            }
          }

          switch (statusCode) {
            case 400:
              return BadRequestException(data is Map
                  ? data['message'] ?? 'Bad request'
                  : 'Bad request');
            case 401:
              return UnauthorizedException(data is Map
                  ? data['message'] ?? 'Unauthorized'
                  : 'Unauthorized');
            case 403:
              return ForbiddenException(
                  data is Map ? data['message'] ?? 'Forbidden' : 'Forbidden');
            case 404:
              return NotFoundException(data is Map
                  ? data['message'] ?? 'Resource not found'
                  : 'Resource not found');
            case 409:
              return ConflictException(
                  data is Map ? data['message'] ?? 'Conflict' : 'Conflict');
            case 500:
            case 501:
            case 502:
            case 503:
              return ServerException(data is Map
                  ? data['message'] ?? 'Server error'
                  : 'Server error');
            default:
              return ApiException(data is Map
                  ? data['message'] ?? 'API error: $statusCode'
                  : 'API error: $statusCode');
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
  Future<dynamic> postSessionCompletion(
      String path, Map<String, dynamic> data) async {
    try {
      await _ensureAuthToken();

      // Check payload size and chunk if necessary
      final payloadSize = data.toString().length;
      AppLogger.sessionCompletion('Session completion payload size check',
          context: {
            'payload_size_bytes': payloadSize,
            'path': path,
          });

      // If payload is large (>1MB), use chunked upload approach
      if (payloadSize > 1048576) {
        // 1MB threshold
        return await _chunkedSessionCompletion(path, data);
      }

      // For smaller payloads, use enhanced single request with longer timeouts
      return await _singleRequestSessionCompletion(path, data);
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Single request completion with enhanced timeouts for session completion
  Future<dynamic> _singleRequestSessionCompletion(
      String path, Map<String, dynamic> data) async {
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
  Future<dynamic> _chunkedSessionCompletion(
      String path, Map<String, dynamic> data) async {
    AppLogger.sessionCompletion('Using chunked upload completion', context: {
      'path': path,
      'original_payload_size_bytes': data.toString().length,
    });

    // Split large arrays into chunks
    final Map<String, dynamic> baseData = Map.from(data);
    final List<dynamic> route = baseData.remove('route') ?? [];
    final List<dynamic> heartRateSamples =
        baseData.remove('heart_rate_samples') ?? [];

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

    // Upload heart rate data in chunks if it exists
    if (heartRateSamples.isNotEmpty) {
      await _uploadHeartRateDataInChunks(sessionId, heartRateSamples);
    }

    AppLogger.sessionCompletion('Chunked upload completed successfully',
        context: {
          'session_id': sessionId,
          'route_points': route.length,
          'heart_rate_samples': heartRateSamples.length,
        });

    return response.data;
  }

  /// Upload heart rate data in manageable chunks
  Future<void> _uploadHeartRateDataInChunks(
      String sessionId, List<dynamic> heartRateSamples) async {
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
