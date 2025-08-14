import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/app_error_handler.dart';
import 'package:rucking_app/core/services/auth_service.dart';
import 'package:get_it/get_it.dart';

/// Enhanced API client wrapper that automatically handles errors with Sentry
class EnhancedApiClient {
  final ApiClient _apiClient;
  final AuthService _authService = GetIt.instance<AuthService>();

  EnhancedApiClient(this._apiClient);

  /// Enhanced GET request with automatic error handling
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParams,
    Map<String, String>? headers,
    String? operationName,
  }) async {
    try {
      return await _apiClient.get(path, queryParams: queryParams);
    } catch (e) {
      await _handleError('api_get', e, {
        'path': path,
        'operation': operationName ?? 'get_request',
        'has_query_params': queryParams?.isNotEmpty ?? false,
      });
      rethrow;
    }
  }

  /// Enhanced POST request with automatic error handling
  Future<dynamic> post(
    String path,
    dynamic data, {
    Map<String, String>? headers,
    String? operationName,
  }) async {
    try {
      return await _apiClient.post(path, data);
    } catch (e) {
      await _handleError('api_post', e, {
        'path': path,
        'operation': operationName ?? 'post_request',
        'has_data': data != null,
      });
      rethrow;
    }
  }

  /// Enhanced PUT request with automatic error handling
  Future<dynamic> put(
    String path,
    dynamic data, {
    Map<String, String>? headers,
    String? operationName,
  }) async {
    try {
      return await _apiClient.put(path, data);
    } catch (e) {
      await _handleError('api_put', e, {
        'path': path,
        'operation': operationName ?? 'put_request',
        'has_data': data != null,
      });
      rethrow;
    }
  }

  /// Enhanced PATCH request with automatic error handling
  Future<dynamic> patch(
    String path,
    dynamic data, {
    Map<String, String>? headers,
    String? operationName,
  }) async {
    try {
      return await _apiClient.patch(path, data);
    } catch (e) {
      await _handleError('api_patch', e, {
        'path': path,
        'operation': operationName ?? 'patch_request',
        'has_data': data != null,
      });
      rethrow;
    }
  }

  /// Enhanced DELETE request with automatic error handling
  Future<dynamic> delete(
    String path, {
    Map<String, String>? headers,
    String? operationName,
  }) async {
    try {
      return await _apiClient.delete(path);
    } catch (e) {
      await _handleError('api_delete', e, {
        'path': path,
        'operation': operationName ?? 'delete_request',
      });
      rethrow;
    }
  }



  /// Centralized error handling
  Future<void> _handleError(
    String operation,
    dynamic error,
    Map<String, dynamic> context,
  ) async {
    String? userId;
    try {
      // Avoid triggering network fetches when not authenticated
      final bool authed = await _authService.isAuthenticated();
      if (authed) {
        try {
          // Best-effort: leverage AuthService caching/deduplication
          final user = await _authService.getCurrentUser();
          userId = user?.userId;
        } catch (_) {
          // Swallow user fetch errors in error handler path
        }
      }
    } catch (_) {
      // If even auth check fails, proceed without userId
    }

    await AppErrorHandler.handleError(
      operation,
      error,
      context: context,
      userId: userId,
      sendToBackend: true,
    );
  }
}
