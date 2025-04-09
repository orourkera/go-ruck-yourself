import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:rucking_app/core/api/api_exceptions.dart';

/// API client responsible for making HTTP requests to the backend
class ApiClient {
  final Dio _dio;

  ApiClient(this._dio);

  /// Adds authorization token to requests
  void setAuthToken(String token) {
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  /// Removes authorization token
  void clearAuthToken() {
    _dio.options.headers.remove('Authorization');
  }

  /// Makes a GET request to the specified endpoint
  Future<dynamic> get(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _dio.get(
        endpoint,
        queryParameters: queryParameters,
      );
      return response.data;
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Makes a POST request to the specified endpoint
  Future<dynamic> post(
    String endpoint, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _dio.post(
        endpoint,
        data: data,
        queryParameters: queryParameters,
      );
      return response.data;
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Makes a PUT request to the specified endpoint
  Future<dynamic> put(
    String endpoint, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _dio.put(
        endpoint,
        data: data,
        queryParameters: queryParameters,
      );
      return response.data;
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Makes a DELETE request to the specified endpoint
  Future<dynamic> delete(
    String endpoint, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _dio.delete(
        endpoint,
        data: data,
        queryParameters: queryParameters,
      );
      return response.data;
    } catch (e) {
      throw _handleError(e);
    }
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
          
          switch (statusCode) {
            case 400:
              return BadRequestException(data?['message'] ?? 'Bad request');
            case 401:
              return UnauthorizedException(data?['message'] ?? 'Unauthorized');
            case 403:
              return ForbiddenException(data?['message'] ?? 'Forbidden');
            case 404:
              return NotFoundException(data?['message'] ?? 'Not found');
            case 500:
            case 502:
            case 503:
              return ServerException(data?['message'] ?? 'Server error');
            default:
              return ApiException('API error: $statusCode');
          }
          
        case DioExceptionType.cancel:
          return RequestCancelledException('Request cancelled');
          
        case DioExceptionType.unknown:
          if (error.error is SocketException) {
            return NetworkException('No internet connection');
          }
          return ApiException('Unknown error: ${error.message}');
          
        default:
          return ApiException('API error: ${error.message}');
      }
    }
    
    return ApiException('Unexpected error: $error');
  }
} 