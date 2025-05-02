import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart' as crypto;

/// SSL Certificate pinning implementation for the app
/// This helps protect against man-in-the-middle attacks
class SslPinningService {
  // These are the SHA-256 fingerprints of the certificates we trust
  // In a real app, you would pin your API server's certificate(s)
  static const List<String> _trustedCertificates = [
    // Example: "5E:XX:XX:XX:XX...", // Replace with actual production certificate fingerprints
  ];

  /// Configure Dio HTTP client with SSL certificate pinning
  static void setupSecureHttpClient(Dio dio) {
    // Only apply pinning in release mode and on real devices (not simulators)
    if (kReleaseMode && !Platform.isLinux && !Platform.isWindows) {
      (dio.httpClientAdapter as IOHttpClientAdapter).onHttpClientCreate = 
        (HttpClient client) {
          client.badCertificateCallback = (X509Certificate cert, String host, int port) {
            // In debug mode, allow all connections for easier development
            if (kDebugMode) return true;
            
            // In release mode, verify the certificate
            return _validateCertificate(cert);
          };
          return client;
        };
    }
  }

  /// Validate a certificate against our pinned certificates
  static bool _validateCertificate(X509Certificate cert) {
    // Get the certificate fingerprint (SHA-256)
    final fingerprint = crypto.sha256.convert(cert.der).toString().toUpperCase();
    
    // Debug log for traceability during development
    if (kDebugMode) {
      debugPrint('Certificate fingerprint: $fingerprint');
    }
    
    // Check if the fingerprint matches any of our trusted certificates
    return _trustedCertificates.contains(fingerprint);
  }
}
