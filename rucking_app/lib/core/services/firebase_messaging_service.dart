import 'dart:convert';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:get_it/get_it.dart';
import '../../features/notifications/util/notification_navigation.dart';
import '../../features/notifications/domain/entities/app_notification.dart';
import '../services/api_client.dart';

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
      // Request permission for notifications
      await _requestNotificationPermissions();
      
      // Initialize local notifications
      await _initializeLocalNotifications();
      
      // Get FCM token
      _deviceToken = await _firebaseMessaging.getToken();
      print('FCM Token: $_deviceToken');
      
      // Send token to backend
      if (_deviceToken != null) {
        await _registerDeviceToken(_deviceToken!);
      }
      
      // Listen for token refresh
      _firebaseMessaging.onTokenRefresh.listen((newToken) async {
        _deviceToken = newToken;
        await _registerDeviceToken(newToken);
      });
      
      // Handle foreground messages
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      
      // Handle background message taps
      FirebaseMessaging.onMessageOpenedApp.listen(_handleBackgroundMessageTap);
      
      // Handle app launch from terminated state
      final initialMessage = await _firebaseMessaging.getInitialMessage();
      if (initialMessage != null) {
        _handleBackgroundMessageTap(initialMessage);
      }
      
      _isInitialized = true;
      print('Firebase Messaging initialized successfully');
      
    } catch (e) {
      print('Error initializing Firebase Messaging: $e');
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
      final apiClient = GetIt.I<ApiClient>();
      
      await apiClient.post('/device-token', {
        'fcm_token': token,
        'device_type': Platform.isIOS ? 'ios' : 'android',
        'device_id': await _getDeviceId(),
        'app_version': '1.0.0', // TODO: Get actual app version
      });
      
      print('Device token registered successfully');
    } catch (e) {
      print('Error registering device token: $e');
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
    print('Received foreground message: ${message.messageId}');
    
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
}

/// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('Background message received: ${message.messageId}');
  // Handle background message processing here if needed
}
