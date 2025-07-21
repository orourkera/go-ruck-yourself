import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:rucking_app/core/utils/app_logger.dart';

/// Service for handling App Tracking Transparency requests
class TrackingTransparencyService {
  /// Request tracking authorization from the user
  /// Returns true if tracking is authorized, false otherwise
  static Future<bool> requestTrackingAuthorization() async {
    try {
      // Only request on iOS
      if (!Platform.isIOS) {
        AppLogger.info('[ATT] Not iOS platform, skipping ATT request');
        return false;
      }

      AppLogger.info('[ATT] Starting App Tracking Transparency request...');
      
      // Check the current status first
      final status = await AppTrackingTransparency.trackingAuthorizationStatus;
      AppLogger.info('[ATT] Current tracking status: $status');
      
      // If we've already shown the dialog and received an answer, just return the result
      if (status != TrackingStatus.notDetermined) {
        final isAuthorized = status == TrackingStatus.authorized;
        AppLogger.info('[ATT] Previous decision found - tracking authorized: $isAuthorized');
        return isAuthorized;
      }

      // Initial request - show the system dialog
      AppLogger.info('[ATT] Showing ATT permission dialog to user...');
      
      // Additional check before showing dialog
      AppLogger.info('[ATT] Platform check: iOS = ${Platform.isIOS}');
      AppLogger.info('[ATT] App state: UI should be fully loaded');
      
      final authStatus = await AppTrackingTransparency.requestTrackingAuthorization();
      AppLogger.info('[ATT] User decision received: $authStatus');
      AppLogger.info('[ATT] Authorization status enum value: ${authStatus.index}');
      
      // App can track if the user authorized it
      final canTrack = authStatus == TrackingStatus.authorized;
      AppLogger.info('[ATT] Final tracking permission: $canTrack');
      return canTrack;
    } catch (e) {
      // Log errors but don't crash the app
      AppLogger.error('[ATT] Error requesting tracking authorization: $e');
      
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
