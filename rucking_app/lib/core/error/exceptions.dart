/// Custom exceptions for app error handling
class ServerException implements Exception {
  final String message;
  
  ServerException({required this.message});
}

class CacheException implements Exception {
  final String message;
  
  CacheException({required this.message});
}

class NetworkException implements Exception {
  final String message;
  
  NetworkException({required this.message});
}

class UnauthorizedException implements Exception {
  final String message;
  
  UnauthorizedException({required this.message});
}

class UnexpectedException implements Exception {
  final String message;
  
  UnexpectedException({required this.message});
}
