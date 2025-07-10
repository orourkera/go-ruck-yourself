import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

class PushNotificationTest {
  static final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  
  /// Complete diagnostic test for push notification setup
  static Future<Map<String, dynamic>> runDiagnostics() async {
    final results = <String, dynamic>{};
    
    try {
      AppLogger.info('🔔 Starting push notification diagnostics...');
      
      // 1. Check platform
      results['platform'] = Platform.isIOS ? 'iOS' : 'Android';
      results['is_debug'] = kDebugMode;
      
      // 2. Check notification permissions
      final settings = await _firebaseMessaging.getNotificationSettings();
      results['permission_status'] = settings.authorizationStatus.toString();
      results['alert_permission'] = settings.alert.toString();
      results['badge_permission'] = settings.badge.toString();
      results['sound_permission'] = settings.sound.toString();
      
      AppLogger.info('🔔 Permission Status: ${settings.authorizationStatus}');
      AppLogger.info('🔔 Alert: ${settings.alert}');
      AppLogger.info('🔔 Badge: ${settings.badge}');
      AppLogger.info('🔔 Sound: ${settings.sound}');
      
      // 3. Check APNs token (iOS only)
      if (Platform.isIOS) {
        try {
          final apnsToken = await _firebaseMessaging.getAPNSToken();
          results['apns_token_available'] = apnsToken != null;
          results['apns_token_length'] = apnsToken?.length ?? 0;
          if (apnsToken != null) {
            AppLogger.info('🔔 APNs Token: ${apnsToken.substring(0, 20)}...');
          } else {
            AppLogger.warning('🔔 APNs Token: NULL');
          }
        } catch (e) {
          results['apns_token_error'] = e.toString();
          AppLogger.error('🔔 APNs Token Error: $e');
        }
      }
      
      // 4. Check FCM token
      try {
        final fcmToken = await _firebaseMessaging.getToken();
        results['fcm_token_available'] = fcmToken != null;
        results['fcm_token_length'] = fcmToken?.length ?? 0;
        if (fcmToken != null) {
          AppLogger.info('🔔 FCM Token (FULL): $fcmToken');
          AppLogger.info('🔔 FCM Token Length: ${fcmToken.length} characters');
        } else {
          AppLogger.warning('🔔 FCM Token: NULL');
        }
      } catch (e) {
        results['fcm_token_error'] = e.toString();
        AppLogger.error('🔔 FCM Token Error: $e');
      }
      
      // 5. Test notification settings request
      try {
        final requestedSettings = await _firebaseMessaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );
        results['permission_request_status'] = requestedSettings.authorizationStatus.toString();
        AppLogger.info('🔔 Permission Request Result: ${requestedSettings.authorizationStatus}');
      } catch (e) {
        results['permission_request_error'] = e.toString();
        AppLogger.error('🔔 Permission Request Error: $e');
      }
      
      // 6. Environment check
      results['build_mode'] = kDebugMode ? 'debug' : 'release';
      results['expected_aps_environment'] = kDebugMode ? 'development' : 'production';
      
      // 7. Bundle ID check
      if (Platform.isIOS) {
        // Note: Bundle ID should match Firebase project configuration
        results['bundle_id_note'] = 'Check that bundle ID matches Firebase project';
      }
      
      AppLogger.info('🔔 Diagnostics completed successfully');
      
    } catch (e) {
      results['diagnostic_error'] = e.toString();
      AppLogger.error('🔔 Diagnostics failed: $e');
    }
    
    return results;
  }
  
  /// Test push notification setup with detailed logging
  static Future<void> testSetup() async {
    AppLogger.info('🧪 Starting push notification test setup...');
    
    final diagnostics = await runDiagnostics();
    
    AppLogger.info('🧪 === PUSH NOTIFICATION DIAGNOSTICS ===');
    diagnostics.forEach((key, value) {
      AppLogger.info('🧪 $key: $value');
    });
    AppLogger.info('🧪 === END DIAGNOSTICS ===');
    
    // Check for common issues
    if (diagnostics['permission_status'] != 'AuthorizationStatus.authorized') {
      AppLogger.warning('❌ ISSUE: Notification permission not granted');
      AppLogger.info('💡 FIX: Go to Settings > Notifications > Your App > Allow Notifications');
    }
    
    if (diagnostics['apns_token_available'] == false && Platform.isIOS) {
      AppLogger.warning('❌ CRITICAL: APNs token not available');
      AppLogger.info('💡 FIXES TO TRY:');
      AppLogger.info('   1. Check Firebase Console: Project Settings > Cloud Messaging');
      AppLogger.info('   2. Verify APNs Authentication Key (.p8) is uploaded');
      AppLogger.info('   3. Ensure Bundle ID matches: com.getrucky.gfy');
      AppLogger.info('   4. Test on physical device (not simulator)');
      AppLogger.info('   5. Verify provisioning profile includes push notifications');
    }
    
    if (diagnostics['fcm_token_available'] == false) {
      AppLogger.warning('❌ ISSUE: FCM token not available');
      AppLogger.info('💡 FIX: Check Firebase configuration and network connectivity');
    }
    
    // Environment guidance
    AppLogger.info('ℹ️  ENVIRONMENT INFO:');
    AppLogger.info('   Build Mode: ${diagnostics['build_mode']}');
    AppLogger.info('   Expected APS Environment: ${diagnostics['expected_aps_environment']}');
    AppLogger.info('   Note: Xcode automatically sets aps-environment based on build type');
    
    if (Platform.isIOS) {
      AppLogger.info('📱 iOS PUSH NOTIFICATION CHECKLIST:');
      AppLogger.info('   ✓ Physical device (not simulator)');
      AppLogger.info('   ✓ Push Notifications capability enabled in Xcode');
      AppLogger.info('   ✓ Background Modes > Remote notifications enabled');
      AppLogger.info('   ✓ APNs key uploaded to Firebase Console');
      AppLogger.info('   ✓ Bundle ID matches Firebase project');
      AppLogger.info('   ✓ Provisioning profile includes push notifications');
    }
    
    AppLogger.info('🧪 Test setup completed');
  }
  
  /// Send a test local notification to verify notification display
  static Future<void> sendTestLocalNotification() async {
    try {
      AppLogger.info('🧪 Sending test local notification...');
      
      // Import the flutter_local_notifications plugin
      final FlutterLocalNotificationsPlugin localNotifications = FlutterLocalNotificationsPlugin();
      
      // Initialize if not already done
      const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
      const DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const InitializationSettings initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsIOS,
      );
      
      await localNotifications.initialize(initializationSettings);
      
      // Create notification details
      const AndroidNotificationDetails androidNotificationDetails = AndroidNotificationDetails(
        'test_channel',
        'Test Notifications',
        channelDescription: 'Test notifications for debugging',
        importance: Importance.max,
        priority: Priority.high,
        ticker: 'Test notification ticker',
      );
      
      const DarwinNotificationDetails iosNotificationDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      
      const NotificationDetails notificationDetails = NotificationDetails(
        android: androidNotificationDetails,
        iOS: iosNotificationDetails,
      );
      
      // Send the notification
      await localNotifications.show(
        0,
        'Test Notification 📱',
        'This is a test notification from your app. If you see this, notifications are working!',
        notificationDetails,
      );
      
      AppLogger.info('✅ Test local notification sent successfully');
      
    } catch (e) {
      AppLogger.error('❌ Failed to send test local notification', exception: e);
    }
  }
}
