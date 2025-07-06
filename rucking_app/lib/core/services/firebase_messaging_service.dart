import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:get_it/get_it.dart';
import '../../features/notifications/util/notification_navigation.dart';
import '../../features/notifications/domain/entities/app_notification.dart';
import '../../features/auth/presentation/bloc/auth_bloc.dart';
import '../services/api_client.dart';
import '../services/app_error_handler.dart';

/// Service for handling Firebase Cloud Messaging (FCM) push notifications
class FirebaseMessagingService {
  static final FirebaseMessagingService _instance = FirebaseMessagingService._internal();
  factory FirebaseMessagingService() => _instance;
  FirebaseMessagingService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  
  bool _isInitialized = false;
  String? _deviceToken;

  /// Initialize Firebase Messaging
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      print('🔔 Starting Firebase Messaging initialization...');
      
      // Request permission for notifications (non-blocking)
      _requestNotificationPermissions().catchError((e) {
        print('⚠️ Permission request failed: $e');
      });
      
      // Initialize local notifications
      await _initializeLocalNotifications();
      
      // Get FCM token with timeout and retry logic
      print('🔔 Requesting FCM token...');
      
      // On iOS, we need to ensure APNS token is available first
      if (Platform.isIOS) {
        print('🔔 iOS detected - checking APNS token...');
        try {
          // Wait for APNS token to be available
          String? apnsToken;
          int attempts = 0;
          while (apnsToken == null && attempts < 10) {
            apnsToken = await _firebaseMessaging.getAPNSToken();
            if (apnsToken == null) {
              print('🔔 APNS token not ready, waiting... (attempt ${attempts + 1}/10)');
              await Future.delayed(const Duration(seconds: 1));
              attempts++;
            } else {
              print('🔔 APNS token obtained: ${apnsToken.substring(0, 32)}...');
            }
          }
          
          if (apnsToken == null) {
            print('⚠️ APNS token still not available after waiting');
          }
        } catch (e) {
          print('⚠️ APNS token check failed: $e');
        }
      }
      
      _deviceToken = await _firebaseMessaging.getToken().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          print('⚠️ FCM token request timed out, attempting to retry...');
          return null;
        },
      );
      
      // If token is null, try to get it again with a different approach
      if (_deviceToken == null) {
        print('🔔 Retrying FCM token request...');
        try {
          await Future.delayed(const Duration(seconds: 2));
          _deviceToken = await _firebaseMessaging.getToken(vapidKey: null);
        } catch (e) {
          print('⚠️ Second token attempt failed: $e');
        }
      }
      
      print('🔔 FCM Token result: ${_deviceToken ?? "STILL NULL"}');
      
      if (_deviceToken == null) {
        print('⚠️ Warning: FCM token is null - checking Firebase configuration...');
        
        // Check if Firebase is properly configured
        try {
          final notificationSettings = await _firebaseMessaging.getNotificationSettings();
          print('🔔 Notification permission status: ${notificationSettings.authorizationStatus}');
          print('🔔 Alert setting: ${notificationSettings.alert}');
          print('🔔 Badge setting: ${notificationSettings.badge}');
          print('🔔 Sound setting: ${notificationSettings.sound}');
        } catch (e) {
          print('❌ Failed to get notification settings: $e');
        }
        
        _isInitialized = true; // Still mark as initialized to prevent retries
        return;
      }
      
      // Send token to backend (non-blocking)
      _registerDeviceToken(_deviceToken!).catchError((e) {
        print('⚠️ Device token registration failed: $e');
      });
      
      // Listen for token refresh
      _firebaseMessaging.onTokenRefresh.listen((newToken) async {
        print('🔔 FCM Token refreshed: $newToken');
        _deviceToken = newToken;
        _registerDeviceToken(newToken).catchError((e) {
          print('⚠️ Token refresh registration failed: $e');
        });
      });
      
      // Handle foreground messages
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      
      // Handle background message taps
      FirebaseMessaging.onMessageOpenedApp.listen(_handleBackgroundMessageTap);
      
      // Handle app launch from terminated state
      final initialMessage = await _firebaseMessaging.getInitialMessage();
      if (initialMessage != null) {
        print('🔔 App launched from notification: ${initialMessage.messageId}');
        _handleBackgroundMessageTap(initialMessage);
      }
      
      _isInitialized = true;
      print('✅ Firebase Messaging initialized successfully');
      
    } catch (e) {
      // Monitor Firebase messaging initialization failures (critical for notifications)
      await AppErrorHandler.handleCriticalError(
        'firebase_messaging_init',
        e,
        context: {
          'platform': Platform.isAndroid ? 'android' : 'ios',
          'firebase_core_initialized': Firebase.apps.isNotEmpty,
        },
      );
      
      print('❌ Error initializing Firebase Messaging: $e');
      _isInitialized = true; // Mark as initialized to prevent blocking retries
      // Don't rethrow - let app continue without push notifications
    }
  }

  /// Request notification permissions
  Future<void> _requestNotificationPermissions() async {
    if (Platform.isIOS) {
      // Request iOS permissions
      final settings = await _firebaseMessaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      
      print('iOS notification permission status: ${settings.authorizationStatus}');
    } else {
      // Request Android permissions
      final status = await Permission.notification.request();
      print('Android notification permission status: $status');
    }
  }

  /// Initialize local notifications for foreground display
  Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onLocalNotificationTap,
    );
    
    // Create notification channel for Android
    if (Platform.isAndroid) {
      await _createNotificationChannel();
    }
  }

  /// Create Android notification channel
  Future<void> _createNotificationChannel() async {
    const channel = AndroidNotificationChannel(
      'rucking_app_notifications',
      'Rucking App Notifications',
      description: 'Notifications for the Rucking App',
      importance: Importance.high,
      playSound: true,
    );
    
    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// Register device token with backend
  Future<void> _registerDeviceToken(String token) async {
    try {
      print('🔔 Registering device token with backend...');
      final apiClient = GetIt.I<ApiClient>();
      
      // Check if user is authenticated before registering token
      final authBloc = GetIt.I<AuthBloc>();
      final authState = authBloc.state;
      if (authState is! Authenticated) {
        print('🔔 User not authenticated, skipping device token registration');
        return;
      }
      
      final deviceId = await _getDeviceId();
      final deviceType = Platform.isIOS ? 'ios' : 'android';
      
      final response = await apiClient.post('/device-token', {
        'fcm_token': token,
        'device_id': deviceId,
        'device_type': deviceType,
        'app_version': '1.0.0', // You might want to get this from package_info
      });
      
      print('🔔 Device token registration response: $response');
      print('🔔 Device token registered successfully with backend');
    } catch (e) {
      // Monitor device token registration failures (affects push notification delivery)
      await AppErrorHandler.handleError(
        'firebase_token_registration',
        e,
        context: {
          'token_length': token.length,
          'platform': Platform.isAndroid ? 'android' : 'ios',
          'has_auth': GetIt.instance.isRegistered<ApiClient>(),
        },
      );
      
      print('❌ Failed to register device token: $e');
      // Don't throw - we want Firebase to still work even if backend registration fails
    }
  }

  /// Get unique device identifier
  Future<String> _getDeviceId() async {
    // TODO: Implement device ID generation
    // You might want to use device_info_plus package
    return 'device_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Handle foreground messages (when app is open)
  void _handleForegroundMessage(RemoteMessage message) {
    print('🔔 Received foreground message: ${message.messageId}');
    print('🔔 Title: ${message.notification?.title}');
    print('🔔 Body: ${message.notification?.body}');
    print('🔔 Data: ${message.data}');
    
    // Show local notification
    _showLocalNotification(message);
  }

  /// Show local notification for foreground messages
  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    final data = message.data;
    
    if (notification != null) {
      const androidDetails = AndroidNotificationDetails(
        'rucking_app_notifications',
        'Rucking App Notifications',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        playSound: true,
      );
      
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      
      const details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );
      
      await _localNotifications.show(
        message.hashCode,
        notification.title,
        notification.body,
        details,
        payload: jsonEncode(data),
      );
    }
  }

  /// Handle background message taps (when app is in background)
  void _handleBackgroundMessageTap(RemoteMessage message) {
    print('Background message tapped: ${message.messageId}');
    _navigateFromNotification(message.data);
  }

  /// Handle local notification taps
  void _onLocalNotificationTap(NotificationResponse response) {
    if (response.payload != null) {
      final data = jsonDecode(response.payload!);
      _navigateFromNotification(data);
    }
  }

  /// Navigate based on notification data
  void _navigateFromNotification(Map<String, dynamic> data) {
    final context = _getNavigatorContext();
    if (context == null) return;
    
    // Create AppNotification from data
    final notification = AppNotification(
      id: data['notification_id'] ?? '',
      type: data['type'] ?? '',
      message: data['message'] ?? data['body'] ?? '',
      data: data,
      createdAt: DateTime.now(),
      isRead: false,
    );
    
    // Use existing navigation helper
    NotificationNavigation.navigateToNotificationDestination(context, notification);
  }

  /// Get current navigator context
  BuildContext? _getNavigatorContext() {
    // TODO: Implement proper navigation context retrieval
    // You might need to use a global key or navigation service
    return null;
  }

  /// Get current FCM token
  String? get deviceToken => _deviceToken;

  /// Get initialization status for debugging
  bool get isInitialized => _isInitialized;

  /// Test notification setup and provide diagnostic information
  Future<Map<String, dynamic>> testNotificationSetup() async {
    final results = <String, dynamic>{};
    
    try {
      print('🧪 Starting notification system diagnostics...');
      
      // 1. Check Firebase initialization
      results['firebase_initialized'] = Firebase.apps.isNotEmpty;
      print('✅ Firebase apps: ${Firebase.apps.length}');
      
      // 2. Check FCM token
      try {
        final token = await _firebaseMessaging.getToken().timeout(
          const Duration(seconds: 10),
          onTimeout: () => null,
        );
        results['fcm_token_available'] = token != null;
        results['fcm_token_length'] = token?.length ?? 0;
        results['fcm_token_preview'] = token?.substring(0, min(20, token.length ?? 0));
        print('✅ FCM Token available: ${token != null}');
        if (token != null) {
          print('🔑 Token preview: ${token.substring(0, min(20, token.length))}...');
        }
      } catch (e) {
        results['fcm_token_error'] = e.toString();
        print('❌ FCM Token error: $e');
      }
      
      // 3. Check notification permissions
      try {
        final settings = await _firebaseMessaging.getNotificationSettings();
        results['permission_status'] = settings.authorizationStatus.toString();
        results['alert_enabled'] = settings.alert == AppleNotificationSetting.enabled;
        results['badge_enabled'] = settings.badge == AppleNotificationSetting.enabled;
        results['sound_enabled'] = settings.sound == AppleNotificationSetting.enabled;
        print('✅ Permission status: ${settings.authorizationStatus}');
        print('✅ Alert: ${settings.alert}, Badge: ${settings.badge}, Sound: ${settings.sound}');
      } catch (e) {
        results['permission_error'] = e.toString();
        print('❌ Permission check error: $e');
      }
      
      // 4. Test device token registration with backend
      try {
        if (_deviceToken != null) {
          await _registerDeviceToken(_deviceToken!);
          results['backend_registration'] = 'success';
          print('✅ Backend registration successful');
        } else {
          results['backend_registration'] = 'no_token';
          print('⚠️ No device token for backend registration');
        }
      } catch (e) {
        results['backend_registration_error'] = e.toString();
        print('❌ Backend registration error: $e');
      }
      
      // 5. Test local notifications
      try {
        await _testLocalNotification();
        results['local_notification'] = 'sent';
        print('✅ Local test notification sent');
      } catch (e) {
        results['local_notification_error'] = e.toString();
        print('❌ Local notification error: $e');
      }
      
      // 6. Check API connectivity
      try {
        final apiClient = GetIt.I<ApiClient>();
        await apiClient.get('/notifications').timeout(const Duration(seconds: 10));
        results['api_connectivity'] = 'success';
        print('✅ API connectivity successful');
      } catch (e) {
        results['api_connectivity_error'] = e.toString();
        print('❌ API connectivity error: $e');
      }
      
      results['test_completed'] = true;
      results['test_timestamp'] = DateTime.now().toIso8601String();
      
      print('🧪 Notification diagnostics completed');
      
    } catch (e) {
      results['test_error'] = e.toString();
      print('❌ Test setup error: $e');
    }
    
    return results;
  }

  /// Test local notification
  Future<void> _testLocalNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'rucking_app_notifications',
      'Rucking App Notifications',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      playSound: true,
    );
    
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    await _localNotifications.show(
      12345,
      'Test Notification',
      'This is a test notification from RuckingApp',
      details,
      payload: 'test_notification',
    );
  }

  /// Force refresh and register token (for debugging)
  Future<void> testNotificationSetupDiagnostic() async {
    print('🔔 Testing notification setup...');
    print('🔔 Initialized: $_isInitialized');
    print('🔔 Current token: ${_deviceToken ?? "NULL"}');
    
    if (!_isInitialized) {
      print('🔔 Firebase messaging not initialized, initializing now...');
      await initialize();
    }
    
    // Always try to force token refresh for testing
    print('🔔 Forcing token refresh...');
    try {
      // Delete existing token first
      await _firebaseMessaging.deleteToken();
      print('🔔 Previous token deleted');
      
      // On iOS, wait for APNS token before requesting FCM token
      if (Platform.isIOS) {
        print('🔔 iOS detected - waiting for APNS token...');
        String? apnsToken;
        int attempts = 0;
        while (apnsToken == null && attempts < 10) {
          apnsToken = await _firebaseMessaging.getAPNSToken();
          if (apnsToken == null) {
            print('🔔 APNS token not ready, waiting... (attempt ${attempts + 1}/10)');
            await Future.delayed(const Duration(seconds: 1));
            attempts++;
          } else {
            print('🔔 APNS token obtained: ${apnsToken.substring(0, 32)}...');
          }
        }
        
        if (apnsToken == null) {
          print('⚠️ APNS token still not available after waiting');
        }
      }
      
      // Request new token
      print('🔔 Requesting new FCM token...');
      final newToken = await _firebaseMessaging.getToken().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          print('⚠️ Token refresh timed out');
          return null;
        },
      );
      
      _deviceToken = newToken;
      print('🔔 Force refresh result: ${_deviceToken ?? "STILL NULL"}');
      
      if (_deviceToken != null) {
        print('🔔 Token successfully generated! Length: ${_deviceToken!.length}');
      } else {
        print('❌ Token generation failed - checking Firebase app state...');
        
        // Check if Firebase app is properly initialized
        try {
          final app = Firebase.app();
          print('🔔 Firebase app name: ${app.name}');
          print('🔔 Firebase project ID: ${app.options.projectId}');
          
          // Try getting APNS token (iOS only)
          try {
            final apnsToken = await _firebaseMessaging.getAPNSToken();
            print('🔔 APNS Token: ${apnsToken ?? "NULL"}');
          } catch (e) {
            print('🔔 APNS Token check failed (normal on Android): $e');
          }
          
        } catch (e) {
          print('❌ Firebase app check failed: $e');
        }
      }
      
    } catch (e) {
      print('❌ Force token refresh failed: $e');
    }
    
    if (_deviceToken != null) {
      print('🔔 Re-registering device token for testing...');
      try {
        await _registerDeviceToken(_deviceToken!);
      } catch (e) {
        print('❌ Device token registration failed: $e');
      }
    }
    
    // Test notification permissions
    try {
      final settings = await _firebaseMessaging.getNotificationSettings();
      print('🔔 Notification settings: ${settings.authorizationStatus}');
      print('🔔 Alert: ${settings.alert}');
      print('🔔 Badge: ${settings.badge}');
      print('🔔 Sound: ${settings.sound}');
    } catch (e) {
      print('❌ Failed to get notification settings: $e');
    }
    
    print('🔔 Notification setup test complete');
  }

  /// Refresh FCM token
  Future<String?> refreshToken() async {
    try {
      await _firebaseMessaging.deleteToken();
      _deviceToken = await _firebaseMessaging.getToken();
      
      if (_deviceToken != null) {
        await _registerDeviceToken(_deviceToken!);
      }
      
      return _deviceToken;
    } catch (e) {
      print('Error refreshing FCM token: $e');
      return null;
    }
  }

  /// Unregister device token
  Future<void> unregisterToken() async {
    try {
      final apiClient = GetIt.I<ApiClient>();
      
      if (_deviceToken != null) {
        await apiClient.delete('/device-token?fcm_token=$_deviceToken');
      }
      
      await _firebaseMessaging.deleteToken();
      _deviceToken = null;
      
      print('Device token unregistered successfully');
    } catch (e) {
      print('Error unregistering device token: $e');
    }
  }

  /// Handle background messages (called from main.dart)
  static Future<void> handleBackgroundMessage(RemoteMessage message) async {
    print('Handling background message: ${message.messageId}');
    // Background message handling logic here
    // Note: Background handlers must be top-level functions or static methods
  }

  /// Manually register device token after authentication
  Future<void> registerTokenAfterAuth() async {
    if (_deviceToken != null) {
      print('🔔 Registering token after authentication...');
      await _registerDeviceToken(_deviceToken!);
    }
  }

  /// Background message handler (must be top-level function)
  @pragma('vm:entry-point')
  Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
    print('Background message received: ${message.messageId}');
    // Handle background message processing here if needed
  }
}
