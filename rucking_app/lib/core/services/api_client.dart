import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:rucking_app/core/services/storage_service.dart';
import 'package:rucking_app/core/api/api_exceptions.dart';

/// Client for handling API requests to the backend
class ApiClient {
  final String _baseUrl = 'http://localhost:8000/api'; // Local development server
  final Dio _dio;
  late final StorageService _storageService;
  final bool useMockData = false; // Use the real backend
  
  ApiClient(this._dio) {
    // Update Dio base URL to use our local server
    _dio.options.baseUrl = _baseUrl;
    
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
  Future<Map<String, dynamic>> get(String endpoint) async {
    try {
      // Use mock data if enabled
      if (useMockData) {
        return getMockData(endpoint);
      }
      
      // Add token if available
      final options = await _getOptions();
      
      // Make API call
      final response = await _dio.get<Map<String, dynamic>>(
        endpoint, // Don't add baseUrl here as Dio already has it
        options: options,
      );
      
      return response.data ?? {};
    } catch (e) {
      // If we get a 404, try to use mock data instead
      if (e is DioException && e.response?.statusCode == 404) {
        print('API 404 Error on GET $endpoint. Using mock data instead.');
        return getMockData(endpoint);
      }
      
      print('API GET Error: $e');
      throw _handleError(e);
    }
  }
  
  /// Makes a POST request to the specified endpoint with the given body
  Future<dynamic> post(String endpoint, Map<String, dynamic> body) async {
    // Use mock data if enabled
    if (useMockData) {
      await Future.delayed(const Duration(milliseconds: 500)); // Simulate network delay
      return getMockData(endpoint);
    }
    
    try {
      final response = await _dio.post(
        endpoint,
        data: body,
        options: Options(headers: await _getHeaders()),
      );
      
      return response.data;
    } catch (e) {
      print('API POST Error: $e');
      if (e is DioException) {
        // Add detailed error information
        print('Status code: ${e.response?.statusCode}, URL: ${e.requestOptions.path}');
        print('Response data: ${e.response?.data}');
      }
      
      // Throw a properly handled error
      throw _handleError(e);
    }
  }
  
  /// Makes a PUT request to the specified endpoint with the given body
  Future<dynamic> put(String endpoint, Map<String, dynamic> body) async {
    // Use mock data if enabled
    if (useMockData) {
      await Future.delayed(const Duration(milliseconds: 500)); // Simulate network delay
      return getMockData(endpoint);
    }
    
    try {
      final response = await _dio.put(
        endpoint,
        data: body,
        options: Options(headers: await _getHeaders()),
      );
      
      return response.data;
    } catch (e) {
      print('API PUT Error: $e');
      if (useMockData) {
        // Fallback to mock data if real request fails
        return getMockData(endpoint);
      }
      rethrow;
    }
  }
  
  /// Makes a DELETE request to the specified endpoint
  Future<dynamic> delete(String endpoint) async {
    // Use mock data if enabled
    if (useMockData) {
      await Future.delayed(const Duration(milliseconds: 500)); // Simulate network delay
      return getMockData(endpoint);
    }
    
    try {
      final response = await _dio.delete(
        endpoint,
        options: Options(headers: await _getHeaders()),
      );
      
      return response.data;
    } catch (e) {
      print('API DELETE Error: $e');
      if (useMockData) {
        // Fallback to mock data if real request fails
        return getMockData(endpoint);
      }
      rethrow;
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
      print('Warning: Storage service not available yet: $e');
    }
    
    return headers;
  }
  
  /// Returns options for API requests (including headers)
  Future<Options> _getOptions() async {
    return Options(
      headers: await _getHeaders(),
    );
  }
  
  /// For development/testing - returns mock data
  Map<String, dynamic> getMockData(String endpoint) {
    // Mock authentication response
    if (endpoint.contains('/auth/login')) {
      return {
        'token': 'mock_token_123456',
        'user': {
          'id': '1',
          'name': 'John Doe',
          'email': 'john.doe@example.com',
          'weight_kg': 75.0,
          'height_cm': 180.0,
        }
      };
    }
    
    // Authentication check
    if (endpoint.contains('/users/profile')) {
      return {
        'id': '1',
        'name': 'John Doe',
        'email': 'john.doe@example.com',
        'weight_kg': 75.0,
        'height_cm': 180.0,
        'date_of_birth': '1990-01-01',
        'created_at': '2023-01-01T00:00:00Z',
        'updated_at': '2023-01-01T00:00:00Z'
      };
    }
    
    // Mock ruck session data
    if (endpoint.contains('/rucks')) {
      return {
        'id': '123',
        'start_time': DateTime.now().toIso8601String(),
        'duration_seconds': 3600,
        'distance_km': 5.2,
        'calories_burned': 450,
      };
    }
    
    return {};
  }
  
  /// Converts API exceptions to app-specific exceptions
  Exception _handleError(dynamic error) {
    print('API Error: $error');
    
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
          
          switch (statusCode) {
            case 400:
              return BadRequestException(data?['message'] ?? 'Bad request');
            case 401:
              return UnauthorizedException(data?['message'] ?? 'Unauthorized');
            case 403:
              return ForbiddenException(data?['message'] ?? 'Forbidden');
            case 404:
              // For 404 errors in development, fall back to mock data
              print('API 404 Error: ${error.requestOptions.path} not found. Using mock data instead.');
              return NotFoundException(data?['message'] ?? 'Resource not found');
            case 409:
              return ConflictException(data?['message'] ?? 'Conflict');
            case 500:
            case 501:
            case 502:
            case 503:
              return ServerException(data?['message'] ?? 'Server error');
            default:
              return ApiException(data?['message'] ?? 'API error: $statusCode');
          }
        
        default:
          return ApiException(error.message ?? 'Unknown API error');
      }
    }
    
    return ApiException('Unexpected error: $error');
  }
} 