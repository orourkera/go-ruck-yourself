import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:get_it/get_it.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/app_error_handler.dart';
import 'package:rucking_app/core/services/app_lifecycle_service.dart';
import 'package:rucking_app/core/services/navigation_service.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import '../../features/notifications/util/notification_navigation.dart';
import '../../features/notifications/domain/entities/app_notification.dart';
import '../../features/notifications/presentation/bloc/notification_event.dart';
import '../../features/auth/presentation/bloc/auth_bloc.dart';
import '../../features/live_following/services/voice_message_player.dart';

/// Service for handling Firebase Cloud Messaging (FCM) push notifications
class FirebaseMessagingService {
  static final FirebaseMessagingService _instance =
      FirebaseMessagingService._internal();
  factory FirebaseMessagingService() => _instance;
  FirebaseMessagingService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  String? _deviceToken;
  int _notificationIdCounter = 1000; // Start from 1000 to avoid conflicts
  RemoteMessage? _pendingInitialMessage;
  static const String _pendingRefreshKey =
      'rucking_app.pending_notification_refresh';

  /// Initialize Firebase Messaging
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final isProduction = !kDebugMode;
      AppLogger.info('Starting Firebase Messaging initialization');
      AppLogger.debug(
          'FCM environment: ${isProduction ? 'PRODUCTION' : 'DEVELOPMENT'}');

      // Request permission for notifications (non-blocking)
      _requestNotificationPermissions().catchError(
        (e) => AppLogger.warning('Notification permission request failed: $e'),
      );

      // Initialize local notifications
      await _initializeLocalNotifications();

      // Get FCM token with timeout and retry logic
      AppLogger.debug('🔔 Requesting FCM token...');

      // On iOS, we need to ensure APNS token is available first
      if (Platform.isIOS) {
        AppLogger.debug('🔔 iOS detected - checking APNS token...');
        try {
          // Wait for APNS token to be available
          String? apnsToken;
          int attempts = 0;
          while (apnsToken == null && attempts < 10) {
            apnsToken = await _firebaseMessaging.getAPNSToken();
            if (apnsToken == null) {
              AppLogger.debug(
                  '🔔 APNS token not ready, waiting... (attempt ${attempts + 1}/10)');
              await Future.delayed(const Duration(seconds: 1));
              attempts++;
            } else {
              AppLogger.debug(
                  '🔔 APNS token obtained: ${apnsToken.substring(0, 32)}...');
            }
          }

          if (apnsToken == null) {
            AppLogger.debug('⚠️ APNS token still not available after waiting');
          }
        } catch (e) {
          AppLogger.debug('⚠️ APNS token check failed: $e');
        }
      }

      // Get FCM token with retry logic and proper timeout
      _deviceToken = await _getTokenWithRetry();

      if (_deviceToken == null) {
        AppLogger.warning(
            'Failed to obtain FCM token after multiple attempts; enabling fallback polling');
        AppLifecycleService.instance.notificationBloc
            ?.startFallbackPolling(interval: const Duration(minutes: 2));
        Future.delayed(const Duration(seconds: 30), retryTokenInBackground);
      } else {
        AppLogger.info('FCM token obtained successfully');
        AppLifecycleService.instance.notificationBloc?.stopPolling();
      }

      if (_deviceToken == null) {
        AppLogger.debug(
            '⚠️ Warning: FCM token is null - checking Firebase configuration...');

        // Check if Firebase is properly configured
        try {
          final notificationSettings =
              await _firebaseMessaging.getNotificationSettings();
          AppLogger.debug(
              '🔔 Notification permission status: ${notificationSettings.authorizationStatus}');
          AppLogger.debug('🔔 Alert setting: ${notificationSettings.alert}');
          AppLogger.debug('🔔 Badge setting: ${notificationSettings.badge}');
          AppLogger.debug('🔔 Sound setting: ${notificationSettings.sound}');
        } catch (e) {
          AppLogger.debug('❌ Failed to get notification settings: $e');
        }

        _isInitialized = true; // Still mark as initialized to prevent retries
        return;
      }

      // Send token to backend only if user is authenticated (non-blocking)
      _registerDeviceTokenIfAuthenticated(_deviceToken!).catchError((e) {
        AppLogger.debug('⚠️ Device token registration failed: $e');
      });

      // Listen for token refresh
      _firebaseMessaging.onTokenRefresh.listen((newToken) async {
        AppLogger.info('FCM token refreshed');
        _deviceToken = newToken;
        AppLifecycleService.instance.notificationBloc?.stopPolling();
        _registerDeviceTokenIfAuthenticated(newToken).catchError(
          (e) => AppLogger.warning('Token refresh registration failed: $e'),
        );
      });

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Handle background message taps
      FirebaseMessaging.onMessageOpenedApp.listen(_handleBackgroundMessageTap);

      // Handle app launch from terminated state
      // Only process initial message if app was actually terminated (not just backgrounded)
      final initialMessage = await _firebaseMessaging.getInitialMessage();
      if (initialMessage != null) {
        AppLogger.debug(
            '🔔 App launched from notification: ${initialMessage.messageId}');
        AppLogger.debug('🔔 Initial message type: ${initialMessage.data['type']}');
        AppLogger.debug('🔔 Initial message data: ${initialMessage.data}');
        _pendingInitialMessage = initialMessage;

        // Process initial message after a delay to ensure app is fully loaded
        // Shorter delay for ruck_started notifications for faster navigation
        final isRuckStarted = initialMessage.data['type'] == 'ruck_started';
        final delayDuration = isRuckStarted
            ? const Duration(milliseconds: 1000)
            : const Duration(seconds: 2);

        Future.delayed(delayDuration, () {
          if (_pendingInitialMessage != null) {
            final message = _pendingInitialMessage!;
            _pendingInitialMessage = null;

            AppLogger.info('Processing initial notification navigation');
            _navigateFromNotification(message.data);
            _triggerImmediateRefresh();
          }
        });
      }

      _isInitialized = true;
      await processQueuedNotificationRefresh();
      AppLogger.info('Firebase Messaging initialized successfully');
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

      AppLogger.debug('❌ Error initializing Firebase Messaging: $e');
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

      AppLogger.debug(
          'iOS notification permission status: ${settings.authorizationStatus}');
    } else {
      // Request Android permissions
      final status = await Permission.notification.request();
      AppLogger.debug('Android notification permission status: $status');
    }
  }

  /// Initialize local notifications for foreground display
  Future<void> _initializeLocalNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
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

    final androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(channel);
    }
  }

  /// Register device token with backend
  Future<void> _registerDeviceToken(String token) async {
    try {
      final apiClient = GetIt.I<ApiClient>();
      final deviceId = await _getDeviceId();
      final deviceType = Platform.isIOS ? 'ios' : 'android';

      // Get actual app version
      final packageInfo = await PackageInfo.fromPlatform();
      final appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';

      final response = await apiClient.post('/device-token', {
        'fcm_token': token,
        'device_id': deviceId,
        'device_type': deviceType,
        'app_version': appVersion,
      });

      AppLogger.debug('🔔 Device token registration response: $response');
      AppLogger.debug('🔔 Device token registered successfully with backend');
    } catch (e) {
      // Monitor device token registration failures (affects push notification delivery)
      try {
        await AppErrorHandler.handleError(
          'firebase_token_registration',
          e,
          context: {
            'token_length': token.length,
            'platform': Platform.isAndroid ? 'android' : 'ios',
            'has_auth': GetIt.instance.isRegistered<ApiClient>(),
          },
        );
      } catch (errorHandlerException) {
        // If error reporting fails, log it but don't crash the app
        AppLogger.debug(
            'Error reporting failed during Firebase token registration: $errorHandlerException');
      }

      AppLogger.debug('❌ Failed to register device token: $e');
      // Don't throw - we want Firebase to still work even if backend registration fails
    }
  }

  /// Register device token with backend only if user is authenticated
  Future<void> _registerDeviceTokenIfAuthenticated(String token) async {
    try {
      final authBloc = GetIt.I<AuthBloc>();
      final currentState = authBloc.state;

      if (currentState is Authenticated) {
        AppLogger.debug(
            '🔔 User is authenticated, registering device token...');
        await _registerDeviceToken(token);
      } else {
        AppLogger.debug(
            '⚠️ User not authenticated, skipping device token registration');
        AppLogger.debug(
            '🔔 Token will be registered after user authentication');
      }
    } catch (e) {
      AppLogger.debug(
          '⚠️ Error checking authentication for token registration: $e');
      // Fallback to attempt registration anyway
      await _registerDeviceToken(token);
    }
  }

  /// Get unique device identifier
  Future<String> _getDeviceId() async {
    try {
      final DeviceInfoPlugin deviceInfoPlugin = DeviceInfoPlugin();

      if (Platform.isIOS) {
        final IosDeviceInfo iosInfo = await deviceInfoPlugin.iosInfo;
        final id = iosInfo.identifierForVendor;
        if (id != null && id.isNotEmpty) {
          return 'ios_$id';
        }
        return 'ios_unknown_${DateTime.now().millisecondsSinceEpoch}';
      } else if (Platform.isAndroid) {
        final AndroidDeviceInfo androidInfo =
            await deviceInfoPlugin.androidInfo;
        final id = androidInfo.id;
        if (id.isNotEmpty) {
          return 'android_$id';
        }
        return 'android_unknown_${DateTime.now().millisecondsSinceEpoch}';
      } else {
        // Fallback for other platforms
        return 'platform_${Platform.operatingSystem}_${DateTime.now().millisecondsSinceEpoch}';
      }
    } catch (e) {
      AppLogger.warning('[FIREBASE_MESSAGING] Failed to get device ID: $e');
      // Fallback to timestamp-based ID if device info fails
      return 'fallback_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  /// Get FCM token with retry logic to handle TOO_MANY_REGISTRATIONS
  Future<String?> _getTokenWithRetry({int maxAttempts = 3}) async {
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        AppLogger.debug('🔔 FCM token request attempt $attempt/$maxAttempts');

        // On iOS, verify APNS token is still available
        if (Platform.isIOS) {
          final apnsToken = await _firebaseMessaging.getAPNSToken();
          AppLogger.debug(
              '🔔 APNS token check: ${apnsToken != null ? "Available" : "Not available"}');
        }

        final token = await _firebaseMessaging.getToken().timeout(
          const Duration(seconds: 20),
          onTimeout: () {
            AppLogger.debug(
                '⚠️ FCM token request timed out on attempt $attempt');
            return null;
          },
        );

        if (token != null && token.isNotEmpty) {
          AppLogger.debug(
              '✅ FCM token obtained successfully on attempt $attempt');
          AppLogger.debug('🔔 Token length: ${token.length} chars');
          return token;
        }

        AppLogger.debug('⚠️ FCM token was null/empty on attempt $attempt');
      } catch (e) {
        AppLogger.debug('❌ FCM token request failed on attempt $attempt: $e');

        // Check if it's the TOO_MANY_REGISTRATIONS error
        if (e.toString().contains('TOO_MANY_REGISTRATIONS')) {
          AppLogger.debug(
              '🚨 TOO_MANY_REGISTRATIONS detected - attempting cleanup');

          try {
            // Delete existing tokens and wait longer
            await _firebaseMessaging.deleteToken();
            AppLogger.debug(
                '🗑️ Deleted existing tokens due to registration limit');

            // Wait longer before retry
            await Future.delayed(Duration(seconds: attempt * 3));
          } catch (deleteError) {
            AppLogger.debug(
                '⚠️ Failed to delete token during cleanup: $deleteError');
          }
        } else {
          // For other errors, wait progressively longer
          await Future.delayed(Duration(seconds: attempt * 2));
        }
      }
    }

    AppLogger.debug('❌ Failed to obtain FCM token after $maxAttempts attempts');
    return null;
  }

  /// Handle foreground messages (when app is open)
  void _handleForegroundMessage(RemoteMessage message) {
    AppLogger.debug('Received foreground message: ${message.messageId}');

    // Special handling for voice messages - auto-play audio
    final messageType = message.data['type'];
    if (messageType == 'ruck_message') {
      _handleVoiceMessage(message);
    }

    _showLocalNotification(message);
    _triggerImmediateRefresh();
  }

  /// Handle voice message - auto-play audio
  void _handleVoiceMessage(RemoteMessage message) {
    try {
      // Log all message data for debugging
      AppLogger.info('[VOICE_MESSAGE] Message data: ${message.data}');
      AppLogger.info('[VOICE_MESSAGE] Message type: ${message.data['type']}');

      final hasAudio = message.data['has_audio'] == 'true';
      AppLogger.info('[VOICE_MESSAGE] Has audio flag: $hasAudio');

      if (!hasAudio) {
        AppLogger.info(
            '[VOICE_MESSAGE] Notification received without audio payload');
        return;
      }

      final audioUrl = message.data['audio_url'];
      AppLogger.info('[VOICE_MESSAGE] Audio URL received: $audioUrl');

      if (audioUrl != null &&
          audioUrl.isNotEmpty &&
          audioUrl.toLowerCase() != 'null' &&
          audioUrl.toLowerCase() != 'none') {
        AppLogger.info('[VOICE_MESSAGE] Attempting to auto-play voice message');
        AppLogger.info('[VOICE_MESSAGE] URL length: ${audioUrl.length}');
        AppLogger.info('[VOICE_MESSAGE] URL starts with: ${audioUrl.substring(0, audioUrl.length > 50 ? 50 : audioUrl.length)}');

        VoiceMessagePlayer().playMessageAudio(audioUrl);
      } else {
        AppLogger.warning('[VOICE_MESSAGE] No valid audio URL in message');
        AppLogger.warning('[VOICE_MESSAGE] audioUrl value: $audioUrl');
      }
    } catch (e, stackTrace) {
      AppLogger.error('[VOICE_MESSAGE] Error handling voice message: $e');
      AppLogger.error('[VOICE_MESSAGE] Stack trace: $stackTrace');
    }
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

      // Generate unique notification ID to prevent duplicates
      final uniqueId = _generateUniqueNotificationId();

      await _localNotifications.show(
        uniqueId,
        notification.title,
        notification.body,
        details,
        payload: jsonEncode(data),
      );
    }
  }

  /// Handle background message taps (when app is in background)
  void _handleBackgroundMessageTap(RemoteMessage message) {
    AppLogger.debug('Background message tapped: ${message.messageId}');
    AppLogger.debug('Notification data: ${message.data}');
    AppLogger.debug('Notification type: ${message.data['type']}');

    // Add a small delay to ensure the app is fully in foreground before navigating
    // This prevents the app from appearing to restart
    Future.delayed(const Duration(milliseconds: 500), () {
      // Ensure we have the necessary data for navigation
      final data = Map<String, dynamic>.from(message.data);

      // If this is a ruck_started notification, ensure we have the required fields
      if (data['type'] == 'ruck_started') {
        AppLogger.info('Processing ruck_started notification tap');
        AppLogger.info('Ruck ID: ${data['ruck_id']}');
        AppLogger.info('Rucker name: ${data['rucker_name']}');
      }

      _navigateFromNotification(data);
      _triggerImmediateRefresh();
    });
  }

  /// Handle local notification taps
  void _onLocalNotificationTap(NotificationResponse response) {
    if (response.payload == null) return;
    final raw = response.payload!;
    Map<String, dynamic>? data;
    try {
      data = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      // Backward-compat for simple string payloads
      data = {'type': raw, 'message': raw};
    }
    _navigateFromNotification(data);
  }

  /// Navigate based on notification data
  void _navigateFromNotification(Map<String, dynamic> data) {
    // Try to get context, with retry logic if needed
    BuildContext? context = _getNavigatorContext();

    // If context is not immediately available, try again after a delay
    if (context == null) {
      AppLogger.warning('Navigation context not available, retrying...');
      Future.delayed(const Duration(milliseconds: 500), () {
        context = _getNavigatorContext();
        if (context != null) {
          _performNavigation(context!, data);
        } else {
          AppLogger.error('Failed to get navigation context after retry');
        }
      });
      return;
    }

    _performNavigation(context, data);
  }

  void _performNavigation(BuildContext context, Map<String, dynamic> data) {
    // Create AppNotification from data
    final notification = AppNotification(
      id: data['notification_id'] ?? '',
      type: data['type'] ?? '',
      message: data['message'] ?? data['body'] ?? '',
      data: data,
      createdAt: DateTime.now(),
      isRead: false,
    );

    AppLogger.info('Navigating to destination for notification type: ${notification.type}');

    // Use existing navigation helper
    NotificationNavigation.navigateToNotificationDestination(
        context, notification);
  }

  /// Get current navigator context
  BuildContext? _getNavigatorContext() {
    // Use the global navigation service to get the current context
    return NavigationService.instance.context;
  }

  /// Get current FCM token
  String? get deviceToken => _deviceToken;

  /// Get initialization status for debugging
  bool get isInitialized => _isInitialized;

  /// Test notification setup and provide diagnostic information
  Future<Map<String, dynamic>> testNotificationSetup() async {
    final results = <String, dynamic>{};

    try {
      AppLogger.debug('🧪 Starting notification system diagnostics...');

      // 1. Check Firebase initialization
      results['firebase_initialized'] = Firebase.apps.isNotEmpty;
      AppLogger.debug('✅ Firebase apps: ${Firebase.apps.length}');

      // 2. Check FCM token
      try {
        final token = await _firebaseMessaging.getToken().timeout(
              const Duration(seconds: 10),
              onTimeout: () => null,
            );
        final tokenLength = token?.length ?? 0;
        results['fcm_token_available'] = token != null;
        results['fcm_token_length'] = tokenLength;
        results['fcm_token_preview'] =
            token != null ? token.substring(0, min(20, tokenLength)) : '';
        AppLogger.debug('✅ FCM Token available: ${token != null}');
        if (token != null) {
          AppLogger.debug(
              '🔑 Token preview: ${token.substring(0, min(20, tokenLength))}...');
        }
      } catch (e) {
        results['fcm_token_error'] = e.toString();
        AppLogger.debug('❌ FCM Token error: $e');
      }

      // 3. Check notification permissions
      try {
        final settings = await _firebaseMessaging.getNotificationSettings();
        results['permission_status'] = settings.authorizationStatus.toString();
        results['alert_enabled'] =
            settings.alert == AppleNotificationSetting.enabled;
        results['badge_enabled'] =
            settings.badge == AppleNotificationSetting.enabled;
        results['sound_enabled'] =
            settings.sound == AppleNotificationSetting.enabled;
        AppLogger.debug('✅ Permission status: ${settings.authorizationStatus}');
        AppLogger.debug(
            '✅ Alert: ${settings.alert}, Badge: ${settings.badge}, Sound: ${settings.sound}');
      } catch (e) {
        results['permission_error'] = e.toString();
        AppLogger.debug('❌ Permission check error: $e');
      }

      // 4. Test device token registration with backend
      try {
        if (_deviceToken != null) {
          await _registerDeviceToken(_deviceToken!);
          results['backend_registration'] = 'success';
          AppLogger.debug('✅ Backend registration successful');
        } else {
          results['backend_registration'] = 'no_token';
          AppLogger.debug('⚠️ No device token for backend registration');
        }
      } catch (e) {
        results['backend_registration_error'] = e.toString();
        AppLogger.debug('❌ Backend registration error: $e');
      }

      // 5. Test local notifications
      try {
        await _testLocalNotification();
        results['local_notification'] = 'sent';
        AppLogger.debug('✅ Local test notification sent');
      } catch (e) {
        results['local_notification_error'] = e.toString();
        AppLogger.debug('❌ Local notification error: $e');
      }

      // 6. Check API connectivity
      try {
        final apiClient = GetIt.I<ApiClient>();
        await apiClient
            .get('/notifications')
            .timeout(const Duration(seconds: 15)); // Increased from 10s
        results['api_connectivity'] = 'success';
        AppLogger.debug('✅ API connectivity successful');
      } catch (e) {
        results['api_connectivity_error'] = e.toString();
        AppLogger.debug('❌ API connectivity error: $e');
      }

      results['test_completed'] = true;
      results['test_timestamp'] = DateTime.now().toIso8601String();

      AppLogger.debug('🧪 Notification diagnostics completed');
    } catch (e) {
      results['test_error'] = e.toString();
      AppLogger.debug('❌ Test setup error: $e');
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

  /// Show a local notification
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    dynamic payload,
  }) async {
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

    // Support both raw strings and Map payloads; encode Map to JSON
    final String? encodedPayload = (() {
      if (payload == null) return null;
      if (payload is String) return payload;
      try {
        return jsonEncode(payload);
      } catch (_) {
        return payload.toString();
      }
    })();

    await _localNotifications.show(
      id,
      title,
      body,
      details,
      payload: encodedPayload,
    );
  }

  /// Generate unique notification ID to prevent duplicates
  int _generateUniqueNotificationId() {
    _notificationIdCounter++;
    if (_notificationIdCounter > 999999) {
      _notificationIdCounter = 1000; // Reset to avoid overflow
    }
    return _notificationIdCounter;
  }

  /// Force refresh and register token (for debugging)
  Future<void> testNotificationSetupDiagnostic() async {
    AppLogger.debug('🔔 Testing notification setup...');
    AppLogger.debug('🔔 Initialized: $_isInitialized');
    AppLogger.debug('🔔 Current token: ${_deviceToken ?? "NULL"}');

    if (!_isInitialized) {
      AppLogger.debug(
          '🔔 Firebase messaging not initialized, initializing now...');
      await initialize();
    }

    // Always try to force token refresh for testing
    AppLogger.debug('🔔 Forcing token refresh...');
    try {
      // Delete existing token first
      await _firebaseMessaging.deleteToken();
      AppLogger.debug('🔔 Previous token deleted');

      // On iOS, wait for APNS token before requesting FCM token
      if (Platform.isIOS) {
        AppLogger.debug('🔔 iOS detected - waiting for APNS token...');
        String? apnsToken;
        int attempts = 0;
        while (apnsToken == null && attempts < 10) {
          apnsToken = await _firebaseMessaging.getAPNSToken();
          if (apnsToken == null) {
            AppLogger.debug(
                '🔔 APNS token not ready, waiting... (attempt ${attempts + 1}/10)');
            await Future.delayed(const Duration(seconds: 1));
            attempts++;
          } else {
            AppLogger.debug(
                '🔔 APNS token obtained: ${apnsToken.substring(0, 32)}...');
          }
        }

        if (apnsToken == null) {
          AppLogger.debug('⚠️ APNS token still not available after waiting');
        }
      }

      // Request new token
      AppLogger.debug('🔔 Requesting new FCM token...');
      final newToken = await _firebaseMessaging.getToken().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          AppLogger.debug('⚠️ Token refresh timed out');
          return null;
        },
      );

      _deviceToken = newToken;
      AppLogger.debug(
          '🔔 Force refresh result: ${_deviceToken ?? "STILL NULL"}');

      if (_deviceToken != null) {
        AppLogger.debug(
            '🔔 Token successfully generated! Length: ${_deviceToken!.length}');
      } else {
        AppLogger.debug(
            '❌ Token generation failed - checking Firebase app state...');

        // Check if Firebase app is properly initialized
        try {
          final app = Firebase.app();
          AppLogger.debug('🔔 Firebase app name: ${app.name}');
          AppLogger.debug('🔔 Firebase project ID: ${app.options.projectId}');

          // Try getting APNS token (iOS only)
          try {
            final apnsToken = await _firebaseMessaging.getAPNSToken();
            AppLogger.debug('🔔 APNS Token: ${apnsToken ?? "NULL"}');
          } catch (e) {
            AppLogger.debug(
                '🔔 APNS Token check failed (normal on Android): $e');
          }
        } catch (e) {
          AppLogger.debug('❌ Firebase app check failed: $e');
        }
      }
    } catch (e) {
      AppLogger.debug('❌ Force token refresh failed: $e');
    }

    if (_deviceToken != null) {
      AppLogger.debug('🔔 Re-registering device token for testing...');
      try {
        await _registerDeviceToken(_deviceToken!);
      } catch (e) {
        AppLogger.debug('❌ Device token registration failed: $e');
      }
    }

    // Test notification permissions
    try {
      final settings = await _firebaseMessaging.getNotificationSettings();
      AppLogger.debug(
          '🔔 Notification settings: ${settings.authorizationStatus}');
      AppLogger.debug('🔔 Alert: ${settings.alert}');
      AppLogger.debug('🔔 Badge: ${settings.badge}');
      AppLogger.debug('🔔 Sound: ${settings.sound}');
    } catch (e) {
      AppLogger.debug('❌ Failed to get notification settings: $e');
    }

    AppLogger.debug('🔔 Notification setup test complete');
  }

  /// Refresh FCM token with proper cleanup
  Future<String?> refreshToken() async {
    try {
      AppLogger.debug('🔄 Refreshing FCM token...');

      // Unregister old token from backend first
      if (_deviceToken != null) {
        try {
          final apiClient = GetIt.I<ApiClient>();
          await apiClient.delete('/device-token?fcm_token=$_deviceToken');
          AppLogger.debug('🗑️ Unregistered old token from backend');
        } catch (e) {
          AppLogger.debug('⚠️ Failed to unregister old token: $e');
        }
      }

      // Delete the FCM token
      await _firebaseMessaging.deleteToken();
      _deviceToken = null;

      // Wait a moment before requesting new token
      await Future.delayed(const Duration(seconds: 2));

      // Get new token with retry logic
      _deviceToken = await _getTokenWithRetry();

      if (_deviceToken != null) {
        await _registerDeviceToken(_deviceToken!);
        AppLogger.debug('✅ FCM token refreshed successfully');
      } else {
        AppLogger.debug('❌ FCM token refresh failed');
      }

      return _deviceToken;
    } catch (e) {
      AppLogger.debug('Error refreshing FCM token: $e');
      return null;
    }
  }

  /// Retry token retrieval in background when network conditions improve
  Future<void> retryTokenInBackground() async {
    if (_deviceToken != null) {
      return; // Already have token
    }

    AppLogger.debug('Attempting background FCM token retrieval');

    try {
      _deviceToken = await _getTokenWithRetry(maxAttempts: 2);

      if (_deviceToken != null) {
        await _registerDeviceToken(_deviceToken!);
        AppLogger.info('Background FCM token retrieval successful');
        AppLifecycleService.instance.notificationBloc?.stopPolling();
      } else {
        AppLogger.warning('Background FCM token retrieval failed');
        AppLifecycleService.instance.notificationBloc
            ?.startFallbackPolling(interval: const Duration(minutes: 2));
      }
    } catch (e) {
      AppLogger.error('Background FCM token retry error: $e');
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

      AppLogger.debug('Device token unregistered successfully');
    } catch (e) {
      AppLogger.debug('Error unregistering device token: $e');
    }
  }

  /// Clean up FCM registration issues (for TOO_MANY_REGISTRATIONS recovery)
  Future<bool> cleanupRegistrations() async {
    try {
      AppLogger.debug('🧹 Starting FCM registration cleanup...');

      // Step 1: Unregister current token from backend
      if (_deviceToken != null) {
        try {
          final apiClient = GetIt.I<ApiClient>();
          await apiClient.delete('/device-token?fcm_token=$_deviceToken');
          AppLogger.debug('🗑️ Cleaned up backend registration');
        } catch (e) {
          AppLogger.debug('⚠️ Backend cleanup failed: $e');
        }
      }

      // Step 2: Delete FCM tokens (may need multiple attempts)
      for (int i = 0; i < 3; i++) {
        try {
          await _firebaseMessaging.deleteToken();
          AppLogger.debug('🗑️ Deleted FCM token (attempt ${i + 1})');
          await Future.delayed(const Duration(seconds: 2));
        } catch (e) {
          AppLogger.debug('⚠️ Token deletion attempt ${i + 1} failed: $e');
        }
      }

      // Step 3: Clear local state
      _deviceToken = null;
      _isInitialized = false;

      // Step 4: Wait before attempting reinitialization
      await Future.delayed(const Duration(seconds: 5));

      // Step 5: Reinitialize with clean state
      await initialize();

      AppLogger.debug('✅ FCM registration cleanup completed');
      return _deviceToken != null;
    } catch (e) {
      AppLogger.debug('❌ FCM cleanup failed: $e');

      // Report cleanup failure for monitoring
      await AppErrorHandler.handleError(
        'fcm_cleanup_failure',
        e,
        context: {
          'platform': Platform.isAndroid ? 'android' : 'ios',
          'had_token': (_deviceToken != null).toString(),
        },
      );

      return false;
    }
  }

  /// Handle background messages (called from main.dart)
  static Future<void> handleBackgroundMessage(RemoteMessage message) async {
    try {
      await Firebase.initializeApp();
    } catch (_) {
      // ignore if already initialized
    }
    await _queueRefreshFlag();
    debugPrint('Queued notification refresh for background message');
  }

  /// Manually register device token after authentication
  Future<void> registerTokenAfterAuth() async {
    if (_deviceToken != null) {
      AppLogger.debug('Registering device token after authentication');
      await _registerDeviceToken(_deviceToken!);
    } else {
      AppLogger.warning(
          'No device token available to register after authentication');
    }
  }

  /// Background message handler (must be top-level function)
  @pragma('vm:entry-point')
  Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
    await handleBackgroundMessage(message);
  }

  /// Process pending initial message when app launches from notification
  Future<void> processPendingInitialMessage() async {
    if (_pendingInitialMessage == null) return;

    final context = _getNavigatorContext();
    if (context == null) {
      // Schedule for later if context not ready
      WidgetsBinding.instance.addPostFrameCallback((_) {
        processPendingInitialMessage();
      });
      return;
    }

    _handleBackgroundMessageTap(_pendingInitialMessage!);
    _pendingInitialMessage = null;
  }

  void _triggerImmediateRefresh() {
    final bloc = AppLifecycleService.instance.notificationBloc;
    if (bloc != null) {
      bloc.add(const NotificationsRequested());
    } else {
      _queueRefreshFlag();
    }
  }

  static Future<void> _queueRefreshFlag() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pendingRefreshKey, true);
  }

  Future<void> processQueuedNotificationRefresh() async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getBool(_pendingRefreshKey) ?? false;
    if (!pending) return;
    await prefs.remove(_pendingRefreshKey);
    final bloc = AppLifecycleService.instance.notificationBloc;
    if (bloc != null) {
      bloc.add(const NotificationsRequested());
    } else {
      await _queueRefreshFlag();
    }
  }
}
