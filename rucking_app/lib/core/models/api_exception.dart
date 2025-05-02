/// Custom exception class for API-related errors
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? endpoint;
  final Map<String, dynamic>? response;

  ApiException({
    required this.message,
    this.statusCode,
    this.endpoint,
    this.response,
  });

  @override
  String toString() {
    return 'ApiException: $message${statusCode != null ? ' (Status code: $statusCode)' : ''}${endpoint != null ? ' - Endpoint: $endpoint' : ''}';
  }
}
