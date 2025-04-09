/// Base exception for all API related errors
class ApiException implements Exception {
  final String message;
  
  ApiException(this.message);
  
  @override
  String toString() => 'ApiException: $message';
}

/// Exception for network connectivity issues
class NetworkException extends ApiException {
  NetworkException(String message) : super(message);
  
  @override
  String toString() => 'NetworkException: $message';
}

/// Exception for timeout errors
class TimeoutException extends ApiException {
  TimeoutException(String message) : super(message);
  
  @override
  String toString() => 'TimeoutException: $message';
}

/// Exception for 400 Bad Request errors
class BadRequestException extends ApiException {
  BadRequestException(String message) : super(message);
  
  @override
  String toString() => 'BadRequestException: $message';
}

/// Exception for 401 Unauthorized errors
class UnauthorizedException extends ApiException {
  UnauthorizedException(String message) : super(message);
  
  @override
  String toString() => 'UnauthorizedException: $message';
}

/// Exception for 403 Forbidden errors
class ForbiddenException extends ApiException {
  ForbiddenException(String message) : super(message);
  
  @override
  String toString() => 'ForbiddenException: $message';
}

/// Exception for 404 Not Found errors
class NotFoundException extends ApiException {
  NotFoundException(String message) : super(message);
  
  @override
  String toString() => 'NotFoundException: $message';
}

/// Exception for 500, 502, 503 Server errors
class ServerException extends ApiException {
  ServerException(String message) : super(message);
  
  @override
  String toString() => 'ServerException: $message';
}

/// Exception for cancelled requests
class RequestCancelledException extends ApiException {
  RequestCancelledException(String message) : super(message);
  
  @override
  String toString() => 'RequestCancelledException: $message';
} 