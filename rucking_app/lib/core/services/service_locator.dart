import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/config/app_config.dart';
import 'package:rucking_app/core/services/auth_service.dart';
import 'package:rucking_app/core/services/location_service.dart';
import 'package:rucking_app/core/services/storage_service.dart';
import 'package:rucking_app/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:rucking_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Global service locator instance
final GetIt getIt = GetIt.instance;

/// Sets up the service locator with all dependencies
Future<void> setupServiceLocator() async {
  // External services
  final sharedPrefs = await SharedPreferences.getInstance();
  getIt.registerSingleton<SharedPreferences>(sharedPrefs);
  getIt.registerSingleton<FlutterSecureStorage>(const FlutterSecureStorage());
  
  // Core services - order matters!
  getIt.registerSingleton<Dio>(_configureDio());
  final apiClient = ApiClient(getIt<Dio>());
  getIt.registerSingleton<ApiClient>(apiClient);
  
  final storageService = StorageServiceImpl(
    getIt<SharedPreferences>(), 
    getIt<FlutterSecureStorage>()
  );
  getIt.registerSingleton<StorageService>(storageService);
  
  // Connect services to resolve circular dependencies
  apiClient.setStorageService(storageService);
  
  getIt.registerSingleton<AuthService>(
    AuthServiceImpl(
      getIt<ApiClient>(), 
      getIt<StorageService>()
    )
  );
  getIt.registerSingleton<LocationService>(LocationServiceImpl());
  
  // Repositories
  getIt.registerSingleton<AuthRepository>(
    AuthRepositoryImpl(getIt<AuthService>())
  );
  
  // Blocs
  getIt.registerFactory<AuthBloc>(() => AuthBloc(getIt<AuthRepository>()));
}

/// Configures Dio with base options and interceptors
Dio _configureDio() {
  final Dio dio = Dio(
    BaseOptions(
      baseUrl: 'https://getrucky.com/api', // Use production API
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ),
  );
  
  // Add interceptors
  dio.interceptors.add(LogInterceptor(
    requestBody: true,
    responseBody: true,
  ));
  
  return dio;
} 