import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/features/notifications/data/datasources/notification_remote_datasource.dart';
import 'package:rucking_app/features/notifications/data/repositories/notification_repository_impl.dart';
import 'package:rucking_app/features/notifications/domain/repositories/notification_repository.dart';
import 'package:rucking_app/features/notifications/presentation/bloc/notification_bloc.dart';

/// Call this from the global service locator to wire up the Notifications feature.
void initNotificationFeature(GetIt sl) {
  // Data source
  sl.registerLazySingleton<NotificationRemoteDataSource>(
    () => NotificationRemoteDataSourceImpl(apiClient: sl<ApiClient>()),
  );

  // Repository
  sl.registerLazySingleton<NotificationRepository>(
    () => NotificationRepositoryImpl(remoteDataSource: sl()),
  );

  // Bloc
  sl.registerFactory(() => NotificationBloc(repository: sl()));
}
