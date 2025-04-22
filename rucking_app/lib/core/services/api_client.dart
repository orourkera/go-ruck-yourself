import 'package:dio/dio.dart';
import 'package:rucking_app/core/services/storage_service.dart';
import 'package:rucking_app/core/api/api_exceptions.dart';

/// Client for handling API requests to the backend
class ApiClient {
  // Note: Dio is already configured with the base URL in service_locator.dart
  final Dio _dio;
  late final StorageService _storageService;
  
  ApiClient(this._dio) {
    // Add logging interceptor for debugging
    _dio.interceptors.add(LogInterceptor(
      requestHeader: true,
      requestBody: true,
      responseHeader: true,
      responseBody: true,
      error: true,
    ));
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
  
  /// Makes a GET request to the API
  Future<dynamic> get(String endpoint) async {
    try {
      // For ruck sessions, verify we have a token first
      if (endpoint.contains('/rucks')) {
        final token = await _storageService.getAuthToken();
        if (token == null) {
          throw UnauthorizedException('Not authenticated - please log in first');
        }
        
        // Ensure token is set in headers
        _dio.options.headers['Authorization'] = 'Bearer $token';
      }
      
      // Add token if available
      final options = await _getOptions();
      
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
    // For ruck sessions, verify we have a token first
    if (endpoint.contains('/rucks')) {
      final token = await _storageService.getAuthToken();
      if (token == null) {
        throw UnauthorizedException('Not authenticated - please log in first');
      }
      
      // Ensure token is set in headers
      _dio.options.headers['Authorization'] = 'Bearer $token';
    }
    
    try {
      final response = await _dio.post(
        endpoint,
        data: body,
        options: Options(headers: await _getHeaders()),
      );
      
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
  
  /// Returns headers for API requests
  Future<Map<String, String>> _getHeaders() async {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    
    try {
      // Check if storage service is initialized
      final token = await _storageService.getAuthToken();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    } catch (e) {
      // Storage service might not be initialized yet
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