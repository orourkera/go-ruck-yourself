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
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    String? operationName,
  }) async {
    try {
      return await _apiClient.get(path, queryParameters: queryParameters, headers: headers);
    } catch (e) {
      await _handleError('api_get', e, {
        'path': path,
        'operation': operationName ?? 'get_request',
        'has_query_params': queryParameters?.isNotEmpty ?? false,
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
      return await _apiClient.post(path, data, headers: headers);
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
      return await _apiClient.put(path, data, headers: headers);
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
      return await _apiClient.patch(path, data, headers: headers);
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
      return await _apiClient.delete(path, headers: headers);
    } catch (e) {
      await _handleError('api_delete', e, {
        'path': path,
        'operation': operationName ?? 'delete_request',
      });
      rethrow;
    }
  }

  /// Enhanced multipart POST request with automatic error handling
  Future<dynamic> postMultipart(
    String path, {
    Map<String, String>? fields,
    Map<String, dynamic>? files,
    Map<String, String>? headers,
    String? operationName,
  }) async {
    try {
      return await _apiClient.postMultipart(
        path,
        fields: fields,
        files: files,
        headers: headers,
      );
    } catch (e) {
      await _handleError('api_multipart_post', e, {
        'path': path,
        'operation': operationName ?? 'multipart_upload',
        'has_fields': fields?.isNotEmpty ?? false,
        'has_files': files?.isNotEmpty ?? false,
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
    final user = await _authService.getCurrentUser();
    await AppErrorHandler.handleError(
      operation,
      error,
      context: context,
      userId: user?.userId,
      sendToBackend: true,
    );
  }
}
