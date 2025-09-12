import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:rucking_app/core/services/auth_service.dart';
import 'package:rucking_app/core/services/storage_service.dart';

/// An interceptor that automatically refreshes expired authentication tokens
class TokenRefreshInterceptor extends Interceptor {
  final Dio _dio;
  final AuthService _authService;
  final StorageService _storageService;

  // Flag to prevent multiple refresh attempts simultaneously
  bool _isRefreshing = false;

  TokenRefreshInterceptor(this._dio, this._authService, this._storageService);

  @override
  void onError(DioError err, ErrorInterceptorHandler handler) async {
    // Only attempt to refresh if the request failed due to authentication
    if (err.response?.statusCode == 401 && !_isRefreshing) {
      try {
        _isRefreshing = true;

        // Get the current token to check if it exists
        final token = await _storageService.getAuthToken();
        if (token == null) {
          // No token, can't refresh
          _isRefreshing = false;
          return handler.next(err);
        }

        debugPrint('[AUTH] Token expired, attempting to refresh');

        // Attempt to refresh the token
        final newToken = await _authService.refreshToken();

        if (newToken != null) {
          debugPrint('[AUTH] Token refreshed successfully');
          // Update the token for future requests
          _dio.options.headers['Authorization'] = 'Bearer $newToken';

          // Retry the failed request with the new token
          final options = Options(
            method: err.requestOptions.method,
            headers: {
              'Authorization': 'Bearer $newToken',
              ...err.requestOptions.headers
            },
          );

          final response = await _dio.request(
            err.requestOptions.path,
            data: err.requestOptions.data,
            queryParameters: err.requestOptions.queryParameters,
            options: options,
          );

          _isRefreshing = false;
          return handler.resolve(response);
        }
      } catch (e) {
        debugPrint('[AUTH] Token refresh failed: $e');
        // If refresh fails, log the error but don't logout - let user continue
        debugPrint(
            '[AUTH] Token refresh failed but keeping user authenticated');
      } finally {
        _isRefreshing = false;
      }
    }

    // If we get here, either it's not a 401 or we couldn't refresh the token
    return handler.next(err);
  }
}
