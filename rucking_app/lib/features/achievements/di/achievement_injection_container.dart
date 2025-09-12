import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/achievement_cache_service.dart';
import 'package:rucking_app/features/achievements/data/repositories/achievement_repository_impl.dart';
import 'package:rucking_app/features/achievements/domain/repositories/achievement_repository.dart';
import 'package:rucking_app/features/achievements/presentation/bloc/achievement_bloc.dart';

/// Call this from the global service locator to wire up the Achievements feature.
void initAchievementFeature(GetIt sl) {
  // Cache service
  sl.registerLazySingleton<AchievementCacheService>(
    () => AchievementCacheService(),
  );

  // Repository
  sl.registerLazySingleton<AchievementRepository>(
    () => AchievementRepositoryImpl(
      apiClient: sl<ApiClient>(),
      cacheService: sl<AchievementCacheService>(),
    ),
  );

  // Bloc
  sl.registerFactory(() => AchievementBloc(
        achievementRepository: sl(),
      ));
}
