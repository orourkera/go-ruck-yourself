import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/app.dart';
import 'package:rucking_app/core/services/service_locator.dart';
import 'package:rucking_app/core/services/tracking_transparency_service.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:rucking_app/features/health_integration/bloc/health_bloc.dart';
import 'package:rucking_app/features/health_integration/domain/health_service.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_tracking_transparency/app_tracking_transparency.dart'; 

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize dependency injection
  await setupServiceLocator();
  
  // Load environment variables from .env
  await dotenv.load();
  
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
  
  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  runApp(
    ProviderScope(
      child: const RuckingApp(),
    ),
  );
}

/// Custom BlocObserver for debugging
class AppBlocObserver extends BlocObserver {
  @override
  void onChange(BlocBase bloc, Change change) {
    super.onChange(bloc, change);
    AppLogger.info('${bloc.runtimeType} $change');
  }

  @override
  void onError(BlocBase bloc, Object error, StackTrace stackTrace) {
    AppLogger.error('${bloc.runtimeType} $error');
    super.onError(bloc, error, stackTrace);
  }
}