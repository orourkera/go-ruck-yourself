import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/auth_service.dart';
import 'package:rucking_app/core/services/location_service.dart';
import 'package:rucking_app/core/services/storage_service.dart';
import 'package:rucking_app/core/services/revenue_cat_service.dart';
import 'package:rucking_app/core/services/watch_service.dart';
import 'package:rucking_app/core/security/ssl_pinning.dart';
import 'package:rucking_app/core/security/token_refresh_interceptor.dart';
import 'package:rucking_app/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:rucking_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/health_integration/domain/health_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/session_history_bloc.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/session_bloc.dart';
import 'package:rucking_app/features/ruck_session/data/repositories/session_repository.dart';
import 'package:rucking_app/core/config/app_config.dart';
import 'package:rucking_app/features/ruck_buddies/di/ruck_buddies_injection_container.dart';

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
  getIt.registerSingleton<StorageService>(StorageServiceImpl(getIt<SharedPreferences>(), getIt<FlutterSecureStorage>()));
  getIt.registerSingleton<AuthService>(AuthServiceImpl(getIt<ApiClient>(), getIt<StorageService>()));
  
  // Connect services to resolve circular dependencies
  apiClient.setStorageService(getIt<StorageService>());
  
  // Add token refresh interceptor after auth service is initialized
  final tokenRefreshInterceptor = TokenRefreshInterceptor(
    getIt<Dio>(), 
    getIt<AuthService>(), 
    getIt<StorageService>()
  );
  getIt<Dio>().interceptors.add(tokenRefreshInterceptor);
  
  getIt.registerSingleton<LocationService>(LocationServiceImpl());
  getIt.registerSingleton<HealthService>(HealthService());
  getIt.registerSingleton<RevenueCatService>(RevenueCatService());
  
  // Watch service depends on location, health, auth
  getIt.registerSingleton<WatchService>(
    WatchService(
      getIt<LocationService>(),
      getIt<HealthService>(),
      getIt<AuthService>(),
    ),
  );
  
  // Repositories
  getIt.registerSingleton<AuthRepository>(
    AuthRepositoryImpl(getIt<AuthService>())
  );
  
  // Session repository for operations like delete
  getIt.registerSingleton<SessionRepository>(
    SessionRepository(apiClient: getIt<ApiClient>())
  );
  
  // Blocs
  getIt.registerFactory<AuthBloc>(() => AuthBloc(getIt<AuthRepository>()));
  getIt.registerFactory<SessionHistoryBloc>(() => SessionHistoryBloc(
    apiClient: getIt<ApiClient>(),
  ));
  getIt.registerFactory<ActiveSessionBloc>(() => ActiveSessionBloc(
        apiClient: getIt<ApiClient>(),
        locationService: getIt<LocationService>(),
        healthService: getIt<HealthService>(),
        watchService: getIt<WatchService>(),
      ));
      
  // Register session bloc for operations like delete
  getIt.registerFactory<SessionBloc>(() => SessionBloc(
    sessionRepository: getIt<SessionRepository>(),
  ));
  
  // Initialize Ruck Buddies feature
  initRuckBuddiesFeature(getIt);
}

/// Configures Dio with base options and interceptors
Dio _configureDio() {
  final Dio dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl, // Use AppConfig for environment switching
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ),
  );
  
  // Configure SSL certificate pinning
  SslPinningService.setupSecureHttpClient(dio);
  
  // Add interceptors
  dio.interceptors.add(LogInterceptor(
    requestBody: true,
    responseBody: true,
  ));
  
  return dio;
} 