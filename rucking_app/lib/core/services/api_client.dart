import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:rucking_app/core/services/storage_service.dart';

/// Client for handling API requests to the backend
class ApiClient {
  final String _baseUrl = 'http://localhost:8000/api'; // Local development server
  final Dio _dio;
  late final StorageService _storageService;
  final bool useMockData = true; // Set to true to use mock data instead of the real backend
  
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
  
  /// Makes a GET request to the specified endpoint
  Future<dynamic> get(String endpoint) async {
    // Use mock data if enabled
    if (useMockData) {
      await Future.delayed(const Duration(milliseconds: 500)); // Simulate network delay
      return getMockData(endpoint);
    }
    
    try {
      final response = await _dio.get(
        endpoint,
        options: Options(headers: await _getHeaders()),
      );
      
      return response.data;
    } catch (e) {
      print('API GET Error: $e');
      if (useMockData) {
        // Fallback to mock data if real request fails
        return getMockData(endpoint);
      }
      rethrow;
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
      if (useMockData) {
        // Fallback to mock data if real request fails
        return getMockData(endpoint);
      }
      rethrow;
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
} 