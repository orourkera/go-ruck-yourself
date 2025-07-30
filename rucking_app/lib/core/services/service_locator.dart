import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/enhanced_api_client.dart';
import 'package:rucking_app/core/services/auth_service.dart';
import 'package:rucking_app/core/services/avatar_service.dart';
import 'package:rucking_app/core/services/location_service.dart';
import 'package:rucking_app/core/services/storage_service.dart';
import 'package:rucking_app/core/services/active_session_storage.dart';
import 'package:rucking_app/core/services/app_startup_service.dart';
import 'package:rucking_app/core/services/app_lifecycle_service.dart';
import 'package:rucking_app/core/services/revenue_cat_service.dart';
import 'package:rucking_app/core/services/watch_service.dart';
import 'package:rucking_app/core/services/duel_completion_service.dart';
import 'package:rucking_app/core/security/ssl_pinning.dart';
import 'package:rucking_app/features/ruck_session/domain/services/heart_rate_service.dart';
import 'package:rucking_app/features/ruck_session/domain/services/split_tracking_service.dart';
import 'package:rucking_app/core/security/token_refresh_interceptor.dart';
import 'package:rucking_app/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:rucking_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:rucking_app/features/clubs/data/repositories/clubs_repository_impl.dart';
import 'package:rucking_app/features/clubs/domain/repositories/clubs_repository.dart';
import 'package:rucking_app/features/clubs/presentation/bloc/clubs_bloc.dart';
import 'package:rucking_app/features/health_integration/domain/health_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/session_history_bloc.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/session_bloc.dart';
import 'package:rucking_app/features/ruck_session/data/repositories/session_repository.dart';
import 'package:rucking_app/core/config/app_config.dart';
import 'package:rucking_app/features/ruck_buddies/di/ruck_buddies_injection_container.dart';
import 'package:rucking_app/features/social/di/social_injection_container.dart';
import 'package:rucking_app/features/health_integration/bloc/health_bloc.dart';
import 'package:rucking_app/features/notifications/di/notification_injection_container.dart';
import 'package:rucking_app/features/achievements/di/achievement_injection_container.dart';
import 'package:rucking_app/features/premium/di/premium_injection_container.dart';
import 'package:rucking_app/features/duels/di/duels_injection_container.dart';
import 'package:rucking_app/features/leaderboard/di/leaderboard_injection_container.dart';
// AllTrails Integration
import 'package:rucking_app/core/repositories/routes_repository.dart';
import 'package:rucking_app/core/repositories/planned_rucks_repository.dart';
import 'package:rucking_app/core/services/gpx_service.dart';
import 'package:rucking_app/core/services/gpx_export_service.dart';
import 'package:rucking_app/core/services/route_progress_tracker.dart';
import 'package:rucking_app/core/services/route_navigation_service.dart';
import 'package:rucking_app/core/utils/eta_calculator.dart';
import 'package:rucking_app/features/planned_rucks/presentation/bloc/planned_ruck_bloc.dart';
import 'package:rucking_app/features/planned_rucks/presentation/bloc/route_import_bloc.dart';
import 'package:rucking_app/core/services/battery_optimization_service.dart';
import 'package:rucking_app/core/services/terrain_service.dart';
import 'package:rucking_app/core/services/terrain_tracker.dart';
import 'package:rucking_app/core/services/connectivity_service.dart';
import 'package:rucking_app/core/services/google_places_service.dart';
import 'package:rucking_app/core/services/clubs_cache_service.dart';
import 'package:rucking_app/core/services/events_cache_service.dart';
import 'package:rucking_app/features/events/data/repositories/events_repository_impl.dart';
import 'package:rucking_app/features/events/domain/repositories/events_repository.dart';
import 'package:rucking_app/features/events/presentation/bloc/events_bloc.dart';
import 'package:rucking_app/features/events/presentation/bloc/event_comments_bloc.dart';
import 'package:rucking_app/features/events/presentation/bloc/event_progress_bloc.dart';
import 'package:rucking_app/core/services/feature_flags.dart';
import 'package:rucking_app/core/services/dau_tracking_service.dart';
import 'package:rucking_app/core/services/firebase_messaging_service.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_coordinator.dart';
import 'package:rucking_app/features/profile/data/repositories/profile_repository_impl.dart';
import 'package:rucking_app/features/profile/domain/repositories/profile_repository.dart';
import 'package:rucking_app/features/profile/presentation/bloc/public_profile_bloc.dart';
import 'package:rucking_app/features/profile/presentation/bloc/social_list_bloc.dart';

// Global service locator instance
final GetIt getIt = GetIt.instance;

/// Sets up the service locator with all dependencies
Future<void> setupServiceLocator() async {
  print('🔧 [ServiceLocator] Starting service locator setup...');
  
  try {
  // External services
  final sharedPrefs = await SharedPreferences.getInstance();
  getIt.registerSingleton<SharedPreferences>(sharedPrefs);
  
  // Configure FlutterSecureStorage with Android-specific options for better reliability
  const secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      // Use AES encryption and ensure data persists across app kills
      preferencesKeyPrefix: 'ruck_secure_',
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  getIt.registerSingleton<FlutterSecureStorage>(secureStorage);
  
  // Core services - order matters!
  getIt.registerSingleton<Dio>(_configureDio());
  final apiClient = ApiClient(getIt<Dio>());
  getIt.registerSingleton<ApiClient>(apiClient);
  getIt.registerSingleton<StorageService>(StorageServiceImpl(getIt<SharedPreferences>(), getIt<FlutterSecureStorage>()));
  getIt.registerSingleton<AuthService>(AuthServiceImpl(getIt<ApiClient>(), getIt<StorageService>()));
  getIt.registerSingleton<EnhancedApiClient>(EnhancedApiClient(apiClient));
  getIt.registerSingleton<AvatarService>(AvatarService(
    authService: getIt<AuthService>(),
    apiClient: getIt<ApiClient>(),
  ));
  
  // Feature flags
  getIt.registerSingleton<FeatureFlags>(FeatureFlags(getIt<StorageService>()));
  await getIt<FeatureFlags>().initialize();
  
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
  getIt.registerSingleton<AppLifecycleService>(AppLifecycleService.instance);
  
  // Watch service depends on location, health, auth
  getIt.registerSingleton<WatchService>(
    WatchService(
      getIt<LocationService>(),
      getIt<HealthService>(),
      getIt<AuthService>(),
    ),
  );
  
  // Register HeartRateService which centralizes heart rate handling
  getIt.registerSingleton<HeartRateService>(
    HeartRateService(
      watchService: getIt<WatchService>(),
      healthService: getIt<HealthService>(),
    ),
  );
  
  // Register SplitTrackingService which depends on WatchService
  getIt.registerSingleton<SplitTrackingService>(
    SplitTrackingService(watchService: getIt<WatchService>()),
  );
  
  // Register TerrainService
  getIt.registerSingleton<TerrainService>(TerrainService());
  
  // Register TerrainTracker  
  getIt.registerSingleton<TerrainTracker>(TerrainTracker());
  
  // Register ConnectivityService
  getIt.registerSingleton<ConnectivityService>(ConnectivityServiceImpl());
  
  // Register GooglePlacesService
  getIt.registerSingleton<GooglePlacesService>(GooglePlacesService());
  
  // Register ClubsCacheService
  getIt.registerSingleton<ClubsCacheService>(ClubsCacheService());
  
  // Register EventsCacheService
  getIt.registerSingleton<EventsCacheService>(EventsCacheService());
  
  // Repositories
  getIt.registerSingleton<AuthRepository>(
    AuthRepositoryImpl(getIt<AuthService>())
  );
  
  // Clubs repository
  getIt.registerSingleton<ClubsRepository>(
    ClubsRepositoryImpl(getIt<ApiClient>())
  );
  
  // Events repository
  getIt.registerSingleton<EventsRepository>(
    EventsRepositoryImpl(getIt<ApiClient>(), getIt<AvatarService>())
  );
  
  // Session repository for operations like delete
  getIt.registerSingleton<SessionRepository>(
    SessionRepository(apiClient: getIt<ApiClient>())
  );
  
  // Session storage for offline persistence
  getIt.registerSingleton<ActiveSessionStorage>(
    ActiveSessionStorage(getIt<SharedPreferences>())
  );
  
  // App startup service for session recovery
  getIt.registerSingleton<AppStartupService>(
    AppStartupService(getIt<ActiveSessionStorage>())
  );
  
  // DAU tracking service
  getIt.registerSingleton<DauTrackingService>(
    DauTrackingService.instance
  );
  
  // Firebase messaging service
  getIt.registerSingleton<FirebaseMessagingService>(
    FirebaseMessagingService()
  );
  
  // Profile repository
  getIt.registerSingleton<ProfileRepository>(
    ProfileRepositoryImpl(getIt<ApiClient>())
  );
  
  // Blocs
  print('🔧 [ServiceLocator] Registering AuthBloc...');
  getIt.registerLazySingleton<AuthBloc>(() => AuthBloc(getIt<AuthRepository>()));
  getIt.registerFactory<SessionHistoryBloc>(() => SessionHistoryBloc(
    sessionRepository: getIt<SessionRepository>(),
  ));
  // Register the new refactored coordinator
  final coordinator = () => ActiveSessionCoordinator(
    sessionRepository: getIt<SessionRepository>(),
    locationService: getIt<LocationService>(),
    authService: getIt<AuthService>(),
    watchService: getIt<WatchService>(),
    storageService: getIt<StorageService>(),
    apiClient: getIt<ApiClient>(),
    connectivityService: getIt<ConnectivityService>(),
    splitTrackingService: getIt<SplitTrackingService>(),
    terrainTracker: getIt<TerrainTracker>(),
    heartRateService: getIt<HeartRateService>(),
  );
  
  // Register as the generic Bloc type that widgets expect
  // Note: ActiveSessionCoordinator extends Bloc<ActiveSessionEvent, ActiveSessionState>
  getIt.registerFactory<Bloc<ActiveSessionEvent, ActiveSessionState>>(coordinator);
      
  // Register ActiveSessionBloc for screens that expect the traditional bloc
  getIt.registerFactory<ActiveSessionBloc>(() => ActiveSessionBloc(
    apiClient: getIt<ApiClient>(),
    locationService: getIt<LocationService>(),
    healthService: getIt<HealthService>(),
    watchService: getIt<WatchService>(),
    heartRateService: getIt<HeartRateService>(),
    splitTrackingService: getIt<SplitTrackingService>(),
    terrainTracker: getIt<TerrainTracker>(),
    sessionRepository: getIt<SessionRepository>(),
    activeSessionStorage: getIt<ActiveSessionStorage>(),
    connectivityService: getIt<ConnectivityService>(),
  ));
  
  // Register session bloc for operations like delete
  getIt.registerFactory<SessionBloc>(() => SessionBloc(
    sessionRepository: getIt<SessionRepository>(),
  ));

  getIt.registerFactory<HealthBloc>(() => HealthBloc(healthService: getIt<HealthService>()));
  
  // AllTrails Integration Services
  print('🔧 [ServiceLocator] Registering AllTrails services...');
  getIt.registerSingleton<RoutesRepository>(RoutesRepository());
  getIt.registerSingleton<PlannedRucksRepository>(PlannedRucksRepository());
  getIt.registerSingleton<GpxService>(GpxService());
  getIt.registerSingleton<GPXExportService>(GPXExportService());
  getIt.registerSingleton<ETACalculator>(ETACalculator());
  
  // AllTrails BLoCs
  print('🔧 [ServiceLocator] Registering AllTrails BLoCs...');
  getIt.registerLazySingleton<PlannedRuckBloc>(() => PlannedRuckBloc(
    plannedRucksRepository: getIt<PlannedRucksRepository>(),
  ));
  getIt.registerLazySingleton<RouteImportBloc>(() => RouteImportBloc(
    routesRepository: getIt<RoutesRepository>(),
    plannedRucksRepository: getIt<PlannedRucksRepository>(),
    gpxService: getIt<GpxService>(),
    authService: getIt<AuthService>(),
  ));
  getIt.registerFactory<ProfileBloc>(() => ProfileBloc(
    avatarService: getIt<AvatarService>(),
    authBloc: getIt<AuthBloc>(),
  ));
  
  // Clubs bloc
  getIt.registerFactory<ClubsBloc>(() => ClubsBloc(getIt<ClubsRepository>()));

  // Events blocs
  getIt.registerFactory<EventsBloc>(() => EventsBloc(getIt<EventsRepository>(), getIt<LocationService>()));
  getIt.registerFactory<EventCommentsBloc>(() => EventCommentsBloc(getIt<EventsRepository>()));
  getIt.registerFactory<EventProgressBloc>(() => EventProgressBloc(getIt<EventsRepository>()));

  // Public profile bloc
  getIt.registerFactory<PublicProfileBloc>(() => PublicProfileBloc(getIt<ProfileRepository>()));
  
  // Social list bloc for followers/following
  getIt.registerFactory<SocialListBloc>(() => SocialListBloc(getIt<ProfileRepository>()));

  // Initialize Ruck Buddies feature
  initRuckBuddiesFeature(getIt);
  
  // Initialize Social feature
  initSocialFeature(getIt);
  
  // Initialize Notification feature
  initNotificationFeature(getIt);
  
  // Initialize Achievement feature
  initAchievementFeature(getIt);
  
  // Initialize Duels feature
  initDuelsFeature(getIt);
  
  // Initialize Leaderboard feature
  await initLeaderboardDependencies();
  
  // Initialize Premium feature
  setupPremiumDependencies();
  
  print('🔧 [ServiceLocator] Service locator setup completed successfully!');
  
  } catch (e, stackTrace) {
    print('🔧 [ServiceLocator] ERROR during setup: $e');
    print('🔧 [ServiceLocator] Stack trace: $stackTrace');
    rethrow;
  }
}

/// Configures Dio with base options and interceptors
Dio _configureDio() {
  final Dio dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl, // Use AppConfig for environment switching
      connectTimeout: const Duration(seconds: 15), // Increased for poor network conditions
      receiveTimeout: const Duration(seconds: 30), // Increased from 8s to 30s for server load and slow networks
      sendTimeout: const Duration(seconds: 15), // Increased for large uploads
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ),
  );
  
  // Configure SSL certificate pinning (non-fatal)
  try {
    SslPinningService.setupSecureHttpClient(dio);
  } catch (e) {
    // If SSL pinning setup fails (e.g., missing certs while offline), log and continue with default security
    print('[WARNING] SSL pinning setup failed: $e - continuing without pinning');
  }
  
  // Add interceptors
  dio.interceptors.add(LogInterceptor(
    requestBody: true,
    responseBody: true,
  ));
  
  return dio;
} 