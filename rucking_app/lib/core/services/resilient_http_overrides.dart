import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../utils/app_logger.dart';

/// Global HTTP overrides to make all network requests more resilient
/// This prevents fatal crashes from connection interruptions
class ResilientHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    
    // Configure more resilient timeouts
    client.connectionTimeout = const Duration(seconds: 15);
    client.idleTimeout = const Duration(seconds: 5);
    
    // Add user agent
    client.userAgent = 'RuckingApp/3.0.0 (Flutter)';
    
    return _ResilientHttpClient(client);
  }
}

/// Wrapper HTTP client that handles connection interruptions gracefully
class _ResilientHttpClient implements HttpClient {
  final HttpClient _inner;
  
  _ResilientHttpClient(this._inner);

  @override
  bool get autoUncompress => _inner.autoUncompress;

  @override
  set autoUncompress(bool value) => _inner.autoUncompress = value;

  @override
  Duration? get connectionTimeout => _inner.connectionTimeout;

  @override
  set connectionTimeout(Duration? value) => _inner.connectionTimeout = value;

  @override
  Duration get idleTimeout => _inner.idleTimeout;

  @override
  set idleTimeout(Duration value) => _inner.idleTimeout = value;

  @override
  int? get maxConnectionsPerHost => _inner.maxConnectionsPerHost;

  @override
  set maxConnectionsPerHost(int? value) => _inner.maxConnectionsPerHost = value;

  @override
  String? get userAgent => _inner.userAgent;

  @override
  set userAgent(String? value) => _inner.userAgent = value;

  @override
  void addCredentials(Uri url, String realm, HttpClientCredentials credentials) {
    _inner.addCredentials(url, realm, credentials);
  }

  @override
  void addProxyCredentials(String host, int port, String realm, HttpClientCredentials credentials) {
    _inner.addProxyCredentials(host, port, realm, credentials);
  }

  @override
  set authenticate(Future<bool> Function(Uri url, String scheme, String? realm)? f) {
    _inner.authenticate = f;
  }

  @override
  set authenticateProxy(Future<bool> Function(String host, int port, String scheme, String? realm)? f) {
    _inner.authenticateProxy = f;
  }

  @override
  set badCertificateCallback(bool Function(X509Certificate cert, String host, int port)? callback) {
    _inner.badCertificateCallback = callback;
  }

  @override
  void close({bool force = false}) {
    _inner.close(force: force);
  }

  @override
  set connectionFactory(Future<ConnectionTask<Socket>> Function(Uri url, String? proxyHost, int? proxyPort)? f) {
    _inner.connectionFactory = f;
  }

  @override
  set findProxy(String Function(Uri url)? f) {
    _inner.findProxy = f;
  }

  // Core methods with enhanced error handling
  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      _withErrorHandling(() => _inner.delete(host, port, path), 'DELETE', '$host:$port$path');

  @override
  Future<HttpClientRequest> deleteUrl(Uri url) =>
      _withErrorHandling(() => _inner.deleteUrl(url), 'DELETE', url.toString());

  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      _withErrorHandling(() => _inner.get(host, port, path), 'GET', '$host:$port$path');

  @override
  Future<HttpClientRequest> getUrl(Uri url) =>
      _withErrorHandling(() => _inner.getUrl(url), 'GET', url.toString());

  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      _withErrorHandling(() => _inner.head(host, port, path), 'HEAD', '$host:$port$path');

  @override
  Future<HttpClientRequest> headUrl(Uri url) =>
      _withErrorHandling(() => _inner.headUrl(url), 'HEAD', url.toString());

  @override
  Future<HttpClientRequest> open(String method, String host, int port, String path) =>
      _withErrorHandling(() => _inner.open(method, host, port, path), method, '$host:$port$path');

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      _withErrorHandling(() => _inner.openUrl(method, url), method, url.toString());

  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      _withErrorHandling(() => _inner.patch(host, port, path), 'PATCH', '$host:$port$path');

  @override
  Future<HttpClientRequest> patchUrl(Uri url) =>
      _withErrorHandling(() => _inner.patchUrl(url), 'PATCH', url.toString());

  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      _withErrorHandling(() => _inner.post(host, port, path), 'POST', '$host:$port$path');

  @override
  Future<HttpClientRequest> postUrl(Uri url) =>
      _withErrorHandling(() => _inner.postUrl(url), 'POST', url.toString());

  @override
  Future<HttpClientRequest> put(String host, int port, String path) =>
      _withErrorHandling(() => _inner.put(host, port, path), 'PUT', '$host:$port$path');

  @override
  Future<HttpClientRequest> putUrl(Uri url) =>
      _withErrorHandling(() => _inner.putUrl(url), 'PUT', url.toString());

  /// Enhanced error handling wrapper for HTTP requests
  Future<HttpClientRequest> _withErrorHandling(
    Future<HttpClientRequest> Function() requestFunction,
    String method,
    String urlString,
  ) async {
    try {
      return await requestFunction();
    } on SocketException catch (e) {
      if (kDebugMode) {
        AppLogger.debug('Socket exception for $method $urlString: $e');
      }
      rethrow; // Let the calling code handle this gracefully
    } on HttpException catch (e) {
      if (kDebugMode) {
        AppLogger.debug('HTTP exception for $method $urlString: $e');
      }
      rethrow; // Let the calling code handle this gracefully
    } on TimeoutException catch (e) {
      if (kDebugMode) {
        AppLogger.debug('Timeout exception for $method $urlString: $e');
      }
      rethrow; // Let the calling code handle this gracefully
    } catch (e) {
      if (kDebugMode) {
        AppLogger.debug('Unexpected HTTP error for $method $urlString: $e');
      }
      rethrow; // Let the calling code handle this gracefully
    }
  }

  @override
  set keyLog(Function(String line)? callback) {
    _inner.keyLog = callback;
  }
}
