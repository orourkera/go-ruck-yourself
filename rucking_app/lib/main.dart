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
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  FlutterError.onError = (details) {
    // AppLogger.error('Flutter Error: ${details.exception}');
    // AppLogger.error('Stack trace: ${details.stack}');
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    // AppLogger.error('Platform Error: $error');
    // AppLogger.error('Stack trace: $stack');
    return true;
  };

  // Attach Bloc observer for detailed logging of state changes & errors
  Bloc.observer = AppBlocObserver();
  
  // Load environment variables from .env
  await dotenv.load();
  
  // Initialize dependency injection after env vars are loaded
  await setupServiceLocator();
  
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
  
  // Initialize Firebase
  await Firebase.initializeApp();
  
  // Initialize Supabase
  final supabaseUrl = dotenv.env['SUPABASE_URL'];
  final supabaseKey = dotenv.env['SUPABASE_ANON_KEY'];
  
  if (supabaseUrl == null || supabaseKey == null || supabaseUrl.isEmpty || supabaseKey.isEmpty) {
    AppLogger.error('Supabase configuration missing from .env file');
    throw Exception('SUPABASE_URL and SUPABASE_ANON_KEY must be set in .env file');
  }
  
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseKey,
    debug: true,
  );
  
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
  }

  @override
  void onError(BlocBase bloc, Object error, StackTrace stackTrace) {
    AppLogger.error('${bloc.runtimeType} $error');
    super.onError(bloc, error, stackTrace);
  }
}