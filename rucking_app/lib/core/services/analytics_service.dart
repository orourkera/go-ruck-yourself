import 'dart:io';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

/// Analytics service for tracking user events and funnels
class AnalyticsService {
  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;
  static FirebaseAnalyticsObserver? _observer;

  /// Get the analytics observer for navigation tracking
  static FirebaseAnalyticsObserver get observer {
    _observer ??= FirebaseAnalyticsObserver(analytics: _analytics);
    return _observer!;
  }

  // App Install & Launch Events
  static const String _appFirstOpen = 'app_first_open';
  static const String _appOpen = 'app_open';

  // Onboarding Funnel Events
  static const String _onboardingStarted = 'onboarding_started';
  static const String _onboardingLocationStep = 'onboarding_location_step';
  static const String _onboardingHealthStep = 'onboarding_health_step';
  static const String _onboardingBatteryStep = 'onboarding_battery_step';
  static const String _onboardingCompleted = 'onboarding_completed';
  static const String _onboardingSkipped = 'onboarding_skipped';

  // Sign Up Funnel Events
  static const String _signUpScreenViewed = 'sign_up_screen_viewed';
  static const String _signUpAttempted = 'sign_up_attempted';
  static const String _signUpCompleted = 'sign_up_completed';
  static const String _signUpFailed = 'sign_up_failed';
  static const String _signInCompleted = 'sign_in_completed';

  // Permission Events
  static const String _locationPermissionGranted = 'location_permission_granted';
  static const String _locationPermissionDenied = 'location_permission_denied';
  static const String _healthPermissionGranted = 'health_permission_granted';
  static const String _healthPermissionDenied = 'health_permission_denied';
  static const String _batteryOptimizationEnabled = 'battery_optimization_enabled';
  static const String _batteryOptimizationSkipped = 'battery_optimization_skipped';

  /// Initialize analytics and set collection settings
  static Future<void> initialize() async {
    try {
      // Enable analytics collection
      await _analytics.setAnalyticsCollectionEnabled(true);
      AppLogger.info('[ANALYTICS] Firebase Analytics initialized');
    } catch (e) {
      AppLogger.error('[ANALYTICS] Failed to initialize: $e');
    }
  }

  /// Set user ID for tracking (call after authentication)
  static Future<void> setUserId(String? userId) async {
    try {
      await _analytics.setUserId(id: userId);
      if (userId != null) {
        AppLogger.info('[ANALYTICS] User ID set: ${userId.substring(0, 8)}...');
      }
    } catch (e) {
      AppLogger.error('[ANALYTICS] Failed to set user ID: $e');
    }
  }

  /// Set user properties for segmentation
  static Future<void> setUserProperty({
    required String name,
    required String? value,
  }) async {
    try {
      await _analytics.setUserProperty(name: name, value: value);
      AppLogger.debug('[ANALYTICS] User property set: $name = $value');
    } catch (e) {
      AppLogger.error('[ANALYTICS] Failed to set user property: $e');
    }
  }

  // ============= APP INSTALL & LAUNCH TRACKING =============

  /// Track app first open (for download-to-registration funnel)
  static Future<void> trackAppFirstOpen() async {
    try {
      // Use shared preferences to check if this is truly first open
      final prefs = await SharedPreferences.getInstance();
      final hasOpenedBefore = prefs.getBool('has_opened_app_before') ?? false;

      if (!hasOpenedBefore) {
        trackEvent(_appFirstOpen, {
          'timestamp': DateTime.now().toIso8601String(),
          'platform': Platform.isIOS ? 'ios' : 'android',
        });
        await prefs.setBool('has_opened_app_before', true);
      }
    } catch (e) {
      AppLogger.error('[ANALYTICS] Failed to track first open: $e');
    }
  }

  /// Track app open (every launch)
  static void trackAppOpen({bool isAuthenticated = false}) {
    trackEvent(_appOpen, {
      'timestamp': DateTime.now().toIso8601String(),
      'is_authenticated': isAuthenticated,
      'platform': Platform.isIOS ? 'ios' : 'android',
    });
  }

  // ============= ONBOARDING FUNNEL TRACKING =============

  /// Track onboarding started
  static void trackOnboardingStarted({String? source}) {
    trackEvent(_onboardingStarted, {
      'source': source ?? 'organic',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Track reaching location permission step
  static void trackOnboardingLocationStep({required bool alreadyGranted}) {
    trackEvent(_onboardingLocationStep, {
      'already_granted': alreadyGranted,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Track reaching health permission step
  static void trackOnboardingHealthStep({required bool alreadyGranted}) {
    trackEvent(_onboardingHealthStep, {
      'already_granted': alreadyGranted,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Track reaching battery optimization step
  static void trackOnboardingBatteryStep() {
    trackEvent(_onboardingBatteryStep, {
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Track onboarding completion
  static void trackOnboardingCompleted({
    required bool locationGranted,
    required bool healthGranted,
    required bool batteryOptimized,
  }) {
    trackEvent(_onboardingCompleted, {
      'location_granted': locationGranted,
      'health_granted': healthGranted,
      'battery_optimized': batteryOptimized,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Track onboarding skipped
  static void trackOnboardingSkipped({required String step}) {
    trackEvent(_onboardingSkipped, {
      'skipped_at_step': step,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  // ============= SIGN UP FUNNEL TRACKING =============

  /// Track sign up screen viewed
  static void trackSignUpScreenViewed({String? source}) {
    trackEvent(_signUpScreenViewed, {
      'source': source ?? 'organic',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Track sign up attempted
  static void trackSignUpAttempted({required String method}) {
    trackEvent(_signUpAttempted, {
      'method': method, // 'email', 'google', 'apple'
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Track sign up completed
  static void trackSignUpCompleted({
    required String method,
    required String userId,
  }) {
    trackEvent(_signUpCompleted, {
      'method': method,
      'user_id': userId,
      'timestamp': DateTime.now().toIso8601String(),
    });

    // Also set user properties for cohort analysis
    setUserProperty(name: 'sign_up_method', value: method);
    setUserProperty(name: 'sign_up_date', value: DateTime.now().toIso8601String().split('T')[0]);
  }

  /// Track sign up failed
  static void trackSignUpFailed({
    required String method,
    required String error,
  }) {
    trackEvent(_signUpFailed, {
      'method': method,
      'error': error,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Track sign in completed
  static void trackSignInCompleted({
    required String method,
    required String userId,
  }) {
    trackEvent(_signInCompleted, {
      'method': method,
      'user_id': userId,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  // ============= PERMISSION TRACKING =============

  /// Track location permission result
  static void trackLocationPermission({required bool granted}) {
    trackEvent(
      granted ? _locationPermissionGranted : _locationPermissionDenied,
      {'timestamp': DateTime.now().toIso8601String()},
    );
  }

  /// Track health permission result
  static void trackHealthPermission({required bool granted}) {
    trackEvent(
      granted ? _healthPermissionGranted : _healthPermissionDenied,
      {'timestamp': DateTime.now().toIso8601String()},
    );
  }

  /// Track battery optimization result
  static void trackBatteryOptimization({required bool enabled}) {
    trackEvent(
      enabled ? _batteryOptimizationEnabled : _batteryOptimizationSkipped,
      {'timestamp': DateTime.now().toIso8601String()},
    );
  }

  /// Track Strava connection from onboarding
  static void trackStravaConnection({required bool connected, String? source}) {
    trackEvent(
      connected ? 'strava_connected' : 'strava_skipped',
      {
        'source': source ?? 'onboarding',
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  // ============= EXISTING METHODS (ENHANCED) =============

  /// Track deep link events
  static void trackDeepLink(String link) {
    trackEvent('deep_link_opened', {
      'link': link,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Track sharing events
  static void trackShare(String type, String id) {
    trackEvent('content_shared', {
      'content_type': type,
      'content_id': id,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Track general events
  static void trackEvent(String eventName, Map<String, dynamic> parameters) {
    try {
      // Log locally for debugging
      AppLogger.debug('[ANALYTICS] Event: $eventName, Params: $parameters');

      // Convert dynamic map to Object map for Firebase Analytics
      final Map<String, Object> firebaseParams = {};
      parameters.forEach((key, value) {
        if (value != null) {
          firebaseParams[key] = value;
        }
      });

      // Send to Firebase
      _analytics.logEvent(
        name: eventName,
        parameters: firebaseParams,
      );
    } catch (e) {
      AppLogger.error('[ANALYTICS] Failed to track event $eventName: $e');
    }
  }

  /// Track screen views
  static void trackScreenView({
    required String screenName,
    String? screenClass,
  }) {
    try {
      _analytics.logScreenView(
        screenName: screenName,
        screenClass: screenClass ?? screenName,
      );
      AppLogger.debug('[ANALYTICS] Screen view: $screenName');
    } catch (e) {
      AppLogger.error('[ANALYTICS] Failed to track screen view: $e');
    }
  }
}
