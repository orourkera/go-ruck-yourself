import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

/// Service for handling App Tracking Transparency requests
class TrackingTransparencyService {
  /// Request tracking authorization from the user
  /// Returns true if tracking is authorized, false otherwise
  static Future<bool> requestTrackingAuthorization() async {
    try {
      // Check the current status first
      final status = await AppTrackingTransparency.trackingAuthorizationStatus;
      
      // If we've already shown the dialog and received an answer, just return the result
      if (status != TrackingStatus.notDetermined) {
        return status == TrackingStatus.authorized;
      }

      // Initial request - show the system dialog
      final authStatus = await AppTrackingTransparency.requestTrackingAuthorization();
      
      // App can track if the user authorized it
      return authStatus == TrackingStatus.authorized;
    } catch (e) {
      // Log errors but don't crash the app
      AppLogger.error('Error requesting tracking authorization: $e');
      
      // Default to no tracking if there's an error
      return false;
    }
  }

  /// Get the current tracking authorization status
  static Future<bool> isTrackingAuthorized() async {
    try {
      final status = await AppTrackingTransparency.trackingAuthorizationStatus;
      return status == TrackingStatus.authorized;
    } catch (e) {
      AppLogger.error('Error checking tracking authorization status: $e');
      return false;
    }
  }
}
