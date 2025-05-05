import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/app.dart';
import 'package:rucking_app/core/services/service_locator.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:rucking_app/features/health_integration/bloc/health_bloc.dart';
import 'package:rucking_app/features/health_integration/domain/health_service.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'features/ruck_session/domain/models/heart_rate_sample.dart';
import 'features/ruck_session/domain/models/heart_rate_sample_adapter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(HeartRateSampleAdapter());
  // Initialize dependency injection
  await setupServiceLocator();
  // Load environment variables from .env
  await dotenv.load();
  
  // Configure RevenueCat
  await Purchases.configure(PurchasesConfiguration(dotenv.env['REVENUECAT_API_KEY']!));
  
  // Initialize Firebase
  await Firebase.initializeApp();
  
  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  // Optionally open the heart rate samples box here, or where needed:
  // await Hive.openBox<List>('heart_rate_samples');
  
  runApp(const RuckingApp());
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