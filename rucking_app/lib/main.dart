import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/app.dart';
import 'package:rucking_app/core/services/service_locator.dart';
import 'package:rucking_app/core/services/tracking_transparency_service.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/services/location_service.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/session_bloc.dart';
import 'package:rucking_app/features/social/presentation/bloc/social_bloc.dart';
import 'package:rucking_app/features/achievements/presentation/bloc/achievement_bloc.dart';
import 'package:rucking_app/features/premium/presentation/bloc/premium_bloc.dart';
import 'package:rucking_app/features/premium/presentation/bloc/premium_event.dart';
import 'package:rucking_app/features/duels/presentation/bloc/duel_list/duel_list_bloc.dart';
import 'package:rucking_app/features/duels/presentation/bloc/duel_detail/duel_detail_bloc.dart';
import 'package:rucking_app/features/duels/presentation/bloc/create_duel/create_duel_bloc.dart';
import 'package:rucking_app/features/duels/presentation/bloc/duel_stats/duel_stats_bloc.dart';
import 'package:rucking_app/features/duels/presentation/bloc/duel_invitations/duel_invitations_bloc.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:rucking_app/core/services/firebase_messaging_service.dart';
import 'package:rucking_app/core/services/session_recovery_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase first
  await Firebase.initializeApp();
  
  // 🔥 CRITICAL: Initialize Firebase Crashlytics for crash reporting
  FlutterError.onError = (errorDetails) {
    // Send Flutter framework errors to Crashlytics
    FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
    // Also print for development
    FlutterError.presentError(errorDetails);
    AppLogger.error('Flutter Error: ${errorDetails.exceptionAsString()}');
    if (errorDetails.stack != null) {
      AppLogger.error('Stack trace: ${errorDetails.stack}');
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
  
  // Load environment variables from .env
  await dotenv.load();
  
  // --------------------------
  // Initialize Supabase FIRST (with network error handling)
  // --------------------------
  final supabaseUrl = dotenv.env['SUPABASE_URL'];
  final supabaseKey = dotenv.env['SUPABASE_ANON_KEY'];

  if (supabaseUrl == null || supabaseKey == null || supabaseUrl.isEmpty || supabaseKey.isEmpty) {
    AppLogger.error('Supabase configuration missing from .env file');
    throw Exception('SUPABASE_URL and SUPABASE_ANON_KEY must be set in .env file');
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
  
  // Initialize dependency injection after env vars & Supabase are loaded
  try {
    await setupServiceLocator();
    AppLogger.info('Service locator initialized successfully');
  } catch (e) {
    AppLogger.error('Failed to initialize some services (network issue): $e');
    // Continue anyway - essential services should still work
  }
  
  // Request App Tracking Transparency authorization
  // This is required for iOS 14.5+ to comply with Apple's App Store guidelines
  try {
    // Show tracking authorization dialog
    // It's best to delay showing the authorization request until the app is fully launched
    await Future.delayed(const Duration(milliseconds: 200));
    await TrackingTransparencyService.requestTrackingAuthorization();
  } catch (e) {
    AppLogger.error('Error requesting tracking authorization: $e');
  }
  
  // Request location permissions early to prevent crashes when starting workouts
  try {
    final locationService = getIt<LocationService>();
    final hasPermission = await locationService.hasLocationPermission();
    
    if (!hasPermission) {
      AppLogger.info('Requesting location permission at app startup...');
      await locationService.requestLocationPermission();
    } else {
      AppLogger.info('Location permission already granted.');
    }
  } catch (e) {
    AppLogger.error('Error requesting location permission: $e');
  }
  
  // Disable RevenueCat debug logs for production
  Purchases.setDebugLogsEnabled(false);
  // Removed Purchases.configure from main.dart. Now handled in RevenueCatService.
  
  // Initialize Firebase Messaging background handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  
  // 🔥 Set user identifier in Crashlytics for better debugging
  FirebaseCrashlytics.instance.setUserIdentifier('user_startup');
  
  // 🔥 Log that app is starting (will help track startup crashes)
  FirebaseCrashlytics.instance.log('App starting up - version 2.5.0+20');
  
  // Initialize Firebase Messaging Service (non-blocking)
  FirebaseMessagingService().initialize().catchError((error) {
    print('❌ Firebase Messaging initialization failed: $error');
  });
  
  // 🔄 CRITICAL: Recover any locally saved sessions from previous app crashes/network failures
  SessionRecoveryService.recoverSavedSessions().catchError((error) {
    AppLogger.error('Session recovery failed: $error');
  });
  
  // Supabase already initialized earlier
  
  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  // Trigger authentication check on the singleton AuthBloc instance
  getIt<AuthBloc>().add(AuthCheckRequested());
  
  runApp(
    MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>(
          create: (context) => getIt<AuthBloc>(),
        ),
        BlocProvider<SessionBloc>(
          create: (context) {
            return getIt<SessionBloc>();
          },
        ),
        BlocProvider<SocialBloc>(
          create: (context) {
            return getIt<SocialBloc>();
          },
        ),
        BlocProvider<AchievementBloc>(
          create: (context) {
            return getIt<AchievementBloc>();
          },
        ),
        BlocProvider<PremiumBloc>(
          create: (context) {
            return getIt<PremiumBloc>();
          },
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
      ],
      child: RuckingApp(),
    ),
  );
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
    
    super.onError(bloc, error, stackTrace);
  }
}

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await FirebaseMessagingService.handleBackgroundMessage(message);
}