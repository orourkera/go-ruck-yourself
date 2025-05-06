import 'package:dio/dio.dart';
import 'package:rucking_app/core/services/storage_service.dart';
import 'package:rucking_app/core/api/api_exceptions.dart';
import 'package:flutter/foundation.dart';

/// Client for handling API requests to the backend
class ApiClient {
  // Note: Dio is already configured with the base URL in service_locator.dart
  final Dio _dio;
  late final StorageService _storageService;
  
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
  }
  
  /// Set the storage service after it has been initialized
  void setStorageService(StorageService storageService) {
    _storageService = storageService;
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
    // Check if we already have a token in headers
    if (_dio.options.headers.containsKey('Authorization')) {
      return true;
    }
    
    // Try to get token from storage
    final token = await _storageService.getAuthToken();
    if (token == null) {
      return false;
    }
    
    // Set token in headers
    _dio.options.headers['Authorization'] = 'Bearer $token';
    return true;
  }
  
  /// Makes a GET request to the API
  Future<dynamic> get(String endpoint) async {
    try {
      // For authenticated endpoints, verify we have a token first
      if (endpoint.contains('/rucks') || endpoint.contains('/users')) {
        final hasToken = await _ensureAuthToken();
        if (!hasToken) {
          throw UnauthorizedException('Not authenticated - please log in first');
        }
      }
      
      // Set timeout to prevent hanging requests
      final options = Options(
        headers: await _getHeaders(),
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
      );
      
      // Make API call
      final response = await _dio.get(
        endpoint,
        options: options,
      );
      
      return response.data;
    } catch (e) {
      throw _handleError(e);
    }
  }
  
  /// Makes a POST request to the specified endpoint with the given body
  Future<dynamic> post(String endpoint, Map<String, dynamic> body) async {
    try {
      // Require token for /rucks/* and /users/* endpoints, EXCEPT for /users/register
      bool requiresAuth = (endpoint.startsWith('/rucks') || endpoint.startsWith('/users/')) && 
                          endpoint != '/users/register';
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
        print('[API] Sending refresh token request to $endpoint');
        print('[API] Request body: $body');
      }
      
      // Set timeout to prevent hanging requests
      final options = Options(
        headers: await _getHeaders(),
        // For /auth/refresh, explicitly remove the Authorization header if it exists
        validateStatus: (status) {
          return status != null && status < 500;
        },
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
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
        print('[API] Refresh token response status: ${response.statusCode}');
        print('[API] Refresh token response body: ${response.data}');
      }
      
      return response.data;
    } catch (e) {
      throw _handleError(e);
    }
  }
  
  /// Makes a PUT request to the specified endpoint with the given body
  Future<dynamic> put(String endpoint, Map<String, dynamic> body) async {
    try {
      final response = await _dio.put(
        endpoint,
        data: body,
        options: Options(headers: await _getHeaders()),
      );
      
      return response.data;
    } catch (e) {
      throw _handleError(e);
    }
  }
  
  /// Makes a DELETE request to the specified endpoint
  Future<dynamic> delete(String endpoint) async {
    try {
      final response = await _dio.delete(
        endpoint,
        options: Options(headers: await _getHeaders()),
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

  /// Makes a POST request to add heart rate samples to a ruck session
  Future<dynamic> addHeartRateSamples(String ruckId, List<Map<String, dynamic>> heartRateSamples) async {
    return await post('/rucks/$ruckId/heart_rate', {'samples': heartRateSamples});
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
} 