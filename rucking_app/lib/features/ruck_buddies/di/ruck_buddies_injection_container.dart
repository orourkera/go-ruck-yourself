import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/features/ruck_buddies/data/datasources/mock_ruck_buddies_datasource.dart';
import 'package:rucking_app/features/ruck_buddies/data/datasources/ruck_buddies_remote_datasource.dart';
import 'package:rucking_app/features/ruck_buddies/data/repositories/ruck_buddies_repository_impl.dart';
import 'package:rucking_app/features/ruck_buddies/domain/repositories/ruck_buddies_repository.dart';
import 'package:rucking_app/features/ruck_buddies/domain/usecases/get_ruck_buddies.dart';
import 'package:rucking_app/features/ruck_buddies/presentation/bloc/ruck_buddies_bloc.dart';

void initRuckBuddiesFeature(GetIt sl) {
  // Bloc
  sl.registerFactory(
    () => RuckBuddiesBloc(
      getRuckBuddies: sl(),
    ),
  );

  // Use cases
  sl.registerLazySingleton(() => GetRuckBuddies(sl()));

  // Repository
  sl.registerLazySingleton<RuckBuddiesRepository>(
    () => RuckBuddiesRepositoryImpl(
      remoteDataSource: sl(),
    ),
  );

  // Data sources
  sl.registerLazySingleton<RuckBuddiesRemoteDataSource>(
    () => RuckBuddiesRemoteDataSourceImpl(
      apiClient: sl(),
    ),
  );

  // No need for NetworkInfo registration anymore
}
