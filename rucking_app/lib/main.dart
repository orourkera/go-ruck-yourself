import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'dart:io';
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/app.dart';
import 'package:rucking_app/core/services/service_locator.dart';
import 'package:rucking_app/core/services/tracking_transparency_service.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/services/location_service.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/session_bloc.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';
import 'package:rucking_app/features/social/presentation/bloc/social_bloc.dart';
import 'package:rucking_app/features/achievements/presentation/bloc/achievement_bloc.dart';
import 'package:rucking_app/features/premium/presentation/bloc/premium_bloc.dart';
import 'package:rucking_app/features/premium/presentation/bloc/premium_event.dart';
import 'package:rucking_app/features/duels/presentation/bloc/duel_list/duel_list_bloc.dart';
import 'package:rucking_app/features/duels/presentation/bloc/duel_detail/duel_detail_bloc.dart';
import 'package:rucking_app/features/duels/presentation/bloc/create_duel/create_duel_bloc.dart';
import 'package:rucking_app/features/duels/presentation/bloc/duel_stats/duel_stats_bloc.dart';
import 'package:rucking_app/features/duels/presentation/bloc/duel_invitations/duel_invitations_bloc.dart';
import 'package:rucking_app/features/leaderboard/presentation/bloc/leaderboard_bloc.dart';
import 'package:rucking_app/features/planned_rucks/presentation/bloc/planned_ruck_bloc.dart';
import 'package:rucking_app/features/planned_rucks/presentation/bloc/route_import_bloc.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:rucking_app/core/services/firebase_messaging_service.dart';
import 'package:rucking_app/core/services/remote_config_service.dart';
import 'package:rucking_app/core/services/session_recovery_service.dart';
import 'package:rucking_app/core/services/memory_monitor_service.dart';
import 'package:rucking_app/core/services/active_session_storage.dart';
import 'package:rucking_app/core/services/watch_error_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:sentry/sentry.dart';
import 'dart:async';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:rucking_app/core/services/resilient_http_overrides.dart';

void main() async {
  // 🔥 CRITICAL: Wrap entire app in runZonedGuarded to catch ALL uncaught exceptions
  // This is the MOST IMPORTANT crash handling - catches async errors that bypass other handlers
  runZonedGuarded(
    () async {
      // Ensure Flutter binding is initialized inside the zone to prevent zone mismatch
      WidgetsFlutterBinding.ensureInitialized();
      
      // Set up resilient HTTP overrides to prevent connection crashes
      HttpOverrides.global = ResilientHttpOverrides();
      
      // Critical: Set binary messenger instance
      _setUpBinaryMessenger();
      
      // Run app with proper error handling + Sentry initialization
      await _runApp();
    },
    (error, stackTrace) async {
      // This catches ALL uncaught async exceptions that would otherwise crash the app silently
      AppLogger.error('🚨 UNCAUGHT ASYNC ERROR: $error');
      AppLogger.error('Stack: $stackTrace');
      
      try {
        // Send to Crashlytics IMMEDIATELY before app potentially crashes
        await FirebaseCrashlytics.instance.recordError(
          error, 
          stackTrace, 
          fatal: true,
          information: [
            'UNCAUGHT_ASYNC_EXCEPTION',
            'This error was caught by runZonedGuarded',
            'App version: ${await _getAppVersion()}',
          ],
        );
        
        // Force send crash report immediately (don't wait for next app launch)
        await FirebaseCrashlytics.instance.sendUnsentReports();
        
        AppLogger.info('Crash report sent successfully');
      } catch (crashlyticsError) {
        AppLogger.error('Failed to send crash report: $crashlyticsError');
        // Last resort: print to console so we can see it in logs
        print('🚨 CRASH REPORT FAILED - UNCAUGHT ERROR: $error');
        print('Stack: $stackTrace');
      }
    },
  );
}

Future<void> _runApp() async {
  
  // 🛡️ CRITICAL: ANR Prevention - Configure Flutter engine for stability
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  
  // 🛡️ Prevent surface lifecycle issues that cause ANR
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  
  // Load environment variables
  await dotenv.load(fileName: ".env");
  
  // Initialize Sentry for error monitoring
  await SentryFlutter.init(
    (options) {
      options.dsn = dotenv.env['SENTRY_DSN'] ?? '';
      options.environment = dotenv.env['SENTRY_ENVIRONMENT'] ?? 'production';
      // Avoid hardcoding release; optionally provide via env
      final release = dotenv.env['SENTRY_RELEASE'];
      if (release != null && release.isNotEmpty) {
        options.release = release;
      }
      
      // Performance Monitoring
      options.tracesSampleRate = 0.1; // 10% of transactions for performance monitoring
      options.enableAutoSessionTracking = true;
      options.attachStacktrace = true;
      options.captureFailedRequests = true;
      options.sendDefaultPii = false; // Don't send personally identifiable information
      
      // 🔧 FIX: Keep profiling disabled for iOS compatibility 
      options.profilesSampleRate = 0.0; // Disable profiling
      
      // Enhanced Configuration for 9.3.0
      options.beforeSend = (event, hint) {
        // Drop events related to common bot/WordPress URLs to reduce noise.
        // This mirrors our server filters and extends them for client events.
        const patterns = <String>[
          'wp-admin', 'wp-login', 'xmlrpc.php',
          '/wp-content/', '/wp-includes/', '/wordpress/', '/drupal/',
          'phpmyadmin', '/cgi-bin/',
          '.php', '.asp', '.jsp', '.do',
          '/.env', '/.git/', '/config/', '/backup/', '/tmp/', '/var/'
        ];

        bool containsBlocked(String value) {
          final v = value.toLowerCase();
          for (final p in patterns) {
            if (v.contains(p)) return true;
          }
          return false;
        }

        try {
          // Check event.request URL if present
          final reqUrl = event.request?.url ?? '';
          if (reqUrl.isNotEmpty && containsBlocked(reqUrl)) {
            return null;
          }

          // Check exception stack frames (file names/abs paths)
          final exceptions = event.exceptions;
          if (exceptions != null) {
            for (final ex in exceptions) {
              final frames = ex.stackTrace?.frames;
              if (frames == null) continue;
              for (final f in frames) {
                final fileStr = ([f.fileName ?? '', f.absPath ?? '']
                      ..removeWhere((e) => e.isEmpty))
                    .join(' ');
                if (fileStr.isNotEmpty && containsBlocked(fileStr)) {
                  return null;
                }
              }
            }
          }

          // Check HTTP breadcrumbs for blocked URLs
          final breadcrumbs = event.breadcrumbs;
          if (breadcrumbs != null) {
            for (final b in breadcrumbs) {
              final data = b.data;
              if (data == null) continue;
              final url = (data['url'] ?? data['request_uri'] ?? '').toString();
              if (url.isNotEmpty && containsBlocked(url)) {
                return null;
              }
            }
          }
        } catch (_) {
          // Never let filtering throw
        }

        return event; // keep
      };
    },
    appRunner: () => _initializeApp(),
  );
  
  // Set global tags after initialization
  final appVersion = await _getAppVersion();
  Sentry.configureScope((scope) => scope
    ..setTag('platform', 'flutter')
    ..setTag('app', 'rucking_app')
    ..setTag('version', appVersion)
  );
}

/// Helper function to get app version for crash reports
Future<String> _getAppVersion() async {
  try {
    final packageInfo = await PackageInfo.fromPlatform();
    return '${packageInfo.version}+${packageInfo.buildNumber}';
  } catch (e) {
    return 'unknown';
  }
}

/// Heuristic to classify benign Flutter framework errors as non-fatal.
/// We primarily downgrade common image loading/decoding failures that surface via
/// ImageStreamCompleter as FlutterError reports so they don't crash the app.
bool _isLikelyNonFatalFlutterError(FlutterErrorDetails errorDetails) {
  final Object exception = errorDetails.exception;
  final String message = errorDetails.exceptionAsString().toLowerCase();
  final String? library = errorDetails.library?.toLowerCase();

  // From dart:io and dart:async
  if (exception is HttpException ||
      exception is SocketException ||
      exception is TimeoutException) {
    return true;
  }

  // Image decoding issues (engine often surfaces an ImageCodecException type)
  // Avoid direct type reference for broader engine compatibility
  final String exceptionTypeName = exception.runtimeType.toString();
  if (exceptionTypeName.contains('ImageCodecException')) {
    return true;
  }

  // Image-related libraries commonly used by Flutter when loading/decoding
  if (library != null && (library.contains('image') || library.contains('painting'))) {
    return true;
  }

  // Message heuristics for image failures
  if (message.contains('image') &&
      (message.contains('codec') ||
       message.contains('decode') ||
       message.contains('failed') ||
       message.contains('load') ||
       message.contains('stream'))) {
    return true;
  }

  return false;
}

/// Set up binary messenger (moved from main for organization)
void _setUpBinaryMessenger() {
  // Binary messenger setup if needed
}

Future<void> _initializeApp() async {
  
  // Initialize Firebase first
  await Firebase.initializeApp();
  
  // 🔥 CRITICAL: Initialize Firebase Crashlytics for crash reporting
  FlutterError.onError = (errorDetails) {
    // Route Flutter framework errors to Crashlytics with correct severity
    try {
      final nonFatal = _isLikelyNonFatalFlutterError(errorDetails);
      if (nonFatal) {
        // Report as non-fatal to avoid crashing on benign issues (e.g., image load failures)
        FirebaseCrashlytics.instance.recordFlutterError(errorDetails);
      } else {
        FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
      }
    } catch (_) {
      // Defensive: never let reporting throw
    } finally {
      // Also print for development
      FlutterError.presentError(errorDetails);
      AppLogger.error('Flutter Error: ${errorDetails.exceptionAsString()}');
      if (errorDetails.stack != null) {
        AppLogger.error('Stack trace: ${errorDetails.stack}');
      }
    }
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    // Send platform errors to Crashlytics
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    AppLogger.error('Platform Error: $error');
    AppLogger.error('Stack trace: $stack');
    return true; // Mark as handled
  };

  // Attach Bloc observer for detailed logging of state changes & errors
  Bloc.observer = AppBlocObserver();
  
  // Load environment variables from .env (optional)
  String? supabaseUrl;
  String? supabaseKey;
  
  try {
    await dotenv.load(fileName: '.env');
    AppLogger.info('.env file loaded successfully');
    supabaseUrl = dotenv.env['SUPABASE_URL'];
    supabaseKey = dotenv.env['SUPABASE_ANON_KEY'];
  } catch (e) {
    AppLogger.warning('.env file not found or could not be loaded, using environment variables: $e');
    // Fall back to system environment variables
    supabaseUrl = Platform.environment['SUPABASE_URL'];
    supabaseKey = Platform.environment['SUPABASE_ANON_KEY'];
    
    // No hardcoded fallback - force proper configuration
    if ((supabaseUrl == null || supabaseUrl.isEmpty) && 
        (supabaseKey == null || supabaseKey.isEmpty)) {
      AppLogger.error('Supabase configuration not found in .env file or environment variables');
      AppLogger.error('Please ensure SUPABASE_URL and SUPABASE_ANON_KEY are set in .env file');
    }
  }
  
  // --------------------------
  // Initialize Supabase FIRST (with network error handling)
  // --------------------------
  if (supabaseUrl == null || supabaseKey == null || supabaseUrl.isEmpty || supabaseKey.isEmpty) {
    AppLogger.error('Supabase configuration missing from .env file or environment variables');
    throw Exception('SUPABASE_URL and SUPABASE_ANON_KEY must be set in .env file or environment variables');
  }

  try {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseKey,
    );
    AppLogger.info('Supabase initialized successfully');
  } catch (e) {
    AppLogger.error('Failed to initialize Supabase (network issue): $e');
    // Continue anyway - app can still work in offline mode
  }
  
  // 🌐 Initialize Firebase Remote Config for feature flags
  try {
    AppLogger.info('🌐 Initializing Firebase Remote Config...');
    await RemoteConfigService.instance.initialize();
    AppLogger.info('✅ Firebase Remote Config initialized successfully');
  } catch (e) {
    AppLogger.warning('⚠️ Failed to initialize Firebase Remote Config (will use defaults): $e');
    // Continue anyway - feature flags will use hardcoded defaults
  }
  
  // Initialize dependency injection after env vars & Supabase are loaded
  try {
    await setupServiceLocator();
    AppLogger.info('Service locator initialized successfully');
  } catch (e) {
    AppLogger.error('Failed to initialize some services (network issue): $e');
    // Continue anyway - essential services should still work
  }
  
  // Initialize watch error service for Sentry reporting
  await WatchErrorService.initialize();
  
  // 🔥 CRASH RECOVERY: Check for crashed sessions after services are initialized
  try {
    print('[MAIN_DEBUG] Attempting to get ActiveSessionBloc');
    final activeSessionBloc = getIt<ActiveSessionBloc>();
    print('[MAIN_DEBUG] Got ActiveSessionBloc, adding CheckForCrashedSession');
    activeSessionBloc.add(CheckForCrashedSession());
    print('[MAIN_DEBUG] Added CheckForCrashedSession event');
    AppLogger.info('Session crash recovery check triggered');
  } catch (e) {
    print('[MAIN_DEBUG] Error during session crash recovery: $e');
    AppLogger.error('Error during session crash recovery: $e');
    // Continue anyway - not critical for app startup
  }
  
  // Debug: Check if AuthBloc is registered
  print('🔍 [Main] Checking if AuthBloc is registered...');
  if (getIt.isRegistered<AuthBloc>()) {
    print('✅ [Main] AuthBloc is registered!');
  } else {
    print('❌ [Main] AuthBloc is NOT registered!');
  }
  
  // Request App Tracking Transparency authorization will be done after UI is loaded
  // This prevents the prompt from appearing before the app UI is ready
  
  // REMOVED: Automatic location permission request at startup to prevent conflicts
  // Location permissions will be requested only when actually needed (e.g., starting a session)
  // This prevents stuck Android system dialogs
  
  // Disable RevenueCat debug logs for production
  Purchases.setDebugLogsEnabled(false);
  // Removed Purchases.configure from main.dart. Now handled in RevenueCatService.
  
  // Initialize Firebase Messaging background handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  
  // 🔥 Set user identifier in Crashlytics for better debugging
  FirebaseCrashlytics.instance.setUserIdentifier('user_startup');
  
  // 🔥 Log that app is starting (will help track startup crashes)
  FirebaseCrashlytics.instance.log('App starting up - version 2.5.0+22');
  
  // Enable debug mode for better crash detection in development
  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
  
  // Log additional context for debugging
  FirebaseCrashlytics.instance.setCustomKey('build_number', '22');
  FirebaseCrashlytics.instance.setCustomKey('app_name', 'RuckingApp');
  FirebaseCrashlytics.instance.log('Crashlytics initialized with debug collection enabled');
  
  // Initialize Firebase Messaging Service (non-blocking)
  FirebaseMessagingService().initialize().catchError((error) async {
    print('❌ Firebase Messaging initialization failed: $error');
    
    // Handle TOO_MANY_REGISTRATIONS error with automatic cleanup
    if (error.toString().contains('TOO_MANY_REGISTRATIONS')) {
      print('🚨 TOO_MANY_REGISTRATIONS detected - attempting automatic cleanup');
      
      try {
        final success = await FirebaseMessagingService().cleanupRegistrations();
        if (success) {
          print('✅ FCM registration cleanup successful');
        } else {
          print('❌ FCM registration cleanup failed');
        }
      } catch (cleanupError) {
        print('❌ FCM cleanup error: $cleanupError');
      }
    }
  });
  
  // 🔄 CRITICAL: Recover any locally saved sessions from previous app crashes/network failures
  SessionRecoveryService.recoverSavedSessions().catchError((error) {
    AppLogger.error('Session recovery failed: $error');
  });
  
  // 🧠 Start memory monitoring to prevent crashes
  MemoryMonitorService.startMonitoring();
  
  // Supabase already initialized earlier
  
  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  // Trigger authentication check on the singleton AuthBloc instance
  print('🔍 [Main] Attempting to get AuthBloc...');
  try {
    final authBloc = getIt<AuthBloc>();
    print('✅ [Main] Successfully got AuthBloc!');
    authBloc.add(AuthCheckRequested());
  } catch (e) {
    print('❌ [Main] Failed to get AuthBloc: $e');
    rethrow;
  }
  
  // 🔄 Session Recovery is active and handled in the UI layer
  print('📝 [Main] Session recovery ready - handled by AppStartupService');
  
  // Run the app
  runApp(
    MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>(
          create: (context) => getIt<AuthBloc>(),
        ),
        BlocProvider<SessionBloc>(
          create: (context) => getIt<SessionBloc>(),
        ),
        BlocProvider<ActiveSessionBloc>(
          create: (context) => getIt<ActiveSessionBloc>(),
        ),
        BlocProvider<SocialBloc>(
          create: (context) => getIt<SocialBloc>(),
        ),
        BlocProvider<AchievementBloc>(
          create: (context) => getIt<AchievementBloc>(),
        ),
        BlocProvider<PremiumBloc>(
          create: (context) => getIt<PremiumBloc>(),
        ),
        // Duels feature BLoCs
        BlocProvider<DuelListBloc>(
          create: (context) => getIt<DuelListBloc>(),
        ),
        BlocProvider<DuelDetailBloc>(
          create: (context) => getIt<DuelDetailBloc>(),
        ),
        BlocProvider<CreateDuelBloc>(
          create: (context) => getIt<CreateDuelBloc>(),
        ),
        BlocProvider<DuelStatsBloc>(
          create: (context) => getIt<DuelStatsBloc>(),
        ),
        BlocProvider<DuelInvitationsBloc>(
          create: (context) => getIt<DuelInvitationsBloc>(),
        ),
        BlocProvider<LeaderboardBloc>(
          create: (context) => getIt<LeaderboardBloc>(),
        ),
        // AllTrails Integration BLoCs
        BlocProvider<PlannedRuckBloc>(
          create: (context) => getIt<PlannedRuckBloc>(),
        ),
        BlocProvider<RouteImportBloc>(
          create: (context) => getIt<RouteImportBloc>(),
        ),
      ],
      child: RuckingApp(),
    ),
  );
  
  // 🚨 CRITICAL: Request App Tracking Transparency AFTER UI is loaded
  // This ensures the ATT prompt appears properly for App Store Review
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      AppLogger.info('[Main] App UI loaded, requesting ATT authorization...');
      // Delay to ensure the app is fully visible and interactive
      await Future.delayed(const Duration(milliseconds: 5000)); // Extended for iOS 18.6 compatibility
      final hasPermission = await TrackingTransparencyService.requestTrackingAuthorization();
      AppLogger.info('[Main] ATT authorization result: $hasPermission');
    } catch (e) {
      AppLogger.error('[Main] Error requesting tracking authorization: $e');
    }
  });

  // Update check intentionally disabled per product decision
  
  // 🛡️ ANR Prevention: Initialize heavy services after surface is stable
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      // Wait for Flutter surface to be fully rendered
      await Future.delayed(const Duration(milliseconds: 1000));
      
      // Initialize heavy services in background
      AppLogger.info('[Main] Starting deferred service initialization...');
      
      // These don't block the UI thread
      unawaited(Future(() async {
        try {
          await FirebaseCrashlytics.instance.sendUnsentReports();
          AppLogger.info('[Main] Crashlytics reports sent');
        } catch (e) {
          AppLogger.error('[Main] Error sending crashlytics reports: $e');
        }
      }));
      
    } catch (e) {
      AppLogger.error('[Main] Error in deferred initialization: $e');
    }
  });

  WidgetsBinding.instance.addObserver(AppLifecycleObserver(
    onBackground: () {
      final blocState = getIt<ActiveSessionBloc>().state;
      if (blocState is ActiveSessionRunning) {
        Sentry.captureMessage('App backgrounded during active session', level: SentryLevel.warning, withScope: (scope) {
          scope.setTag('session_id', blocState.sessionId ?? 'unknown');
          scope.setExtra('duration', blocState.elapsedSeconds);
        });
      }
    },
  ));
}

/// Custom BlocObserver for debugging
class AppBlocObserver extends BlocObserver {
  @override
  void onChange(BlocBase bloc, Change change) {
    super.onChange(bloc, change);
    
    // Skip logging for ActiveSessionBloc to avoid excessive location point logging
    if (bloc.runtimeType.toString() == 'ActiveSessionBloc') {
      return;
    }
    
    AppLogger.info('${bloc.runtimeType} $change');
    
    // 🔥 Log important state changes to Crashlytics
    if (bloc.runtimeType.toString() == 'AuthBloc' || 
        bloc.runtimeType.toString() == 'SessionBloc') {
      FirebaseCrashlytics.instance.log('${bloc.runtimeType} state: ${change.nextState.runtimeType}');
    }
  }

  @override
  void onError(BlocBase bloc, Object error, StackTrace stackTrace) {
    AppLogger.error('${bloc.runtimeType} $error');
    
    // 🔥 CRITICAL: Send all bloc errors to Crashlytics
    FirebaseCrashlytics.instance.recordError(
      error, 
      stackTrace, 
      reason: '${bloc.runtimeType} error',
      fatal: false,
    );
    
    // Also send to Sentry with better context
    Sentry.captureException(
      error,
      stackTrace: stackTrace,
      withScope: (scope) {
        scope.setTag('error_type', 'bloc_error');
        scope.setTag('bloc_type', bloc.runtimeType.toString());
      },
    );
    
    super.onError(bloc, error, stackTrace);
  }
}

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await FirebaseMessagingService.handleBackgroundMessage(message);
}

class AppLifecycleObserver extends WidgetsBindingObserver {
  final VoidCallback onBackground;

  AppLifecycleObserver({required this.onBackground});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      onBackground();
    }
  }
}
