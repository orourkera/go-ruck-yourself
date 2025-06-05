import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/services/api_client.dart';

// Data Sources
import '../data/datasources/duels_remote_datasource.dart';

// Repositories
import '../data/repositories/duels_repository_impl.dart';
import '../domain/repositories/duels_repository.dart';

// Use Cases
import '../domain/usecases/create_duel.dart';
import '../domain/usecases/get_duels.dart';
import '../domain/usecases/get_duel_details.dart';
import '../domain/usecases/join_duel.dart';
import '../domain/usecases/update_duel_progress.dart';
import '../domain/usecases/get_duel_invitations.dart';
import '../domain/usecases/respond_to_invitation.dart';
import '../domain/usecases/get_user_duel_stats.dart';
import '../domain/usecases/get_duel_stats_leaderboard.dart';
import '../domain/usecases/get_duel_leaderboard.dart';
import '../domain/usecases/get_duel_comments.dart';
import '../domain/usecases/add_duel_comment.dart';
import '../domain/usecases/update_duel_comment.dart';
import '../domain/usecases/delete_duel_comment.dart';

// BLoCs
import '../presentation/bloc/duel_list/duel_list_bloc.dart';
import '../presentation/bloc/duel_detail/duel_detail_bloc.dart';
import '../presentation/bloc/create_duel/create_duel_bloc.dart';
import '../presentation/bloc/duel_stats/duel_stats_bloc.dart';
import '../presentation/bloc/duel_invitations/duel_invitations_bloc.dart';

/// Call this from the global service locator to wire up the Duels feature.
void initDuelsFeature(GetIt sl) {
  // Data Sources
  sl.registerLazySingleton<DuelsRemoteDataSource>(
    () => DuelsRemoteDataSourceImpl(apiClient: sl<ApiClient>()),
  );

  // Repositories
  sl.registerLazySingleton<DuelsRepository>(
    () => DuelsRepositoryImpl(remoteDataSource: sl()),
  );

  // Use Cases
  sl.registerLazySingleton(() => CreateDuel(sl()));
  sl.registerLazySingleton(() => GetDuels(sl()));
  sl.registerLazySingleton(() => GetDuelDetails(sl()));
  sl.registerLazySingleton(() => JoinDuel(sl()));
  sl.registerLazySingleton(() => UpdateDuelProgress(sl()));
  sl.registerLazySingleton(() => GetDuelInvitations(sl()));
  sl.registerLazySingleton(() => RespondToInvitation(sl()));
  sl.registerLazySingleton(() => GetUserDuelStats(sl()));
  sl.registerLazySingleton(() => GetDuelStatsLeaderboard(sl()));
  sl.registerLazySingleton(() => GetDuelLeaderboard(sl()));
  sl.registerLazySingleton(() => GetDuelComments(sl()));
  sl.registerLazySingleton(() => AddDuelComment(sl()));
  sl.registerLazySingleton(() => UpdateDuelComment(sl()));
  sl.registerLazySingleton(() => DeleteDuelComment(sl()));

  // BLoCs
  sl.registerFactory(() => DuelListBloc(
    getDuels: sl(),
    joinDuel: sl(),
  ));

  sl.registerFactory(() => DuelDetailBloc(
    getDuelDetails: sl(),
    getDuelLeaderboard: sl(),
    joinDuel: sl(),
    updateDuelProgress: sl(),
    getDuelComments: sl(),
    addDuelComment: sl(),
    updateDuelComment: sl(),
    deleteDuelComment: sl(),
  ));

  sl.registerFactory(() => CreateDuelBloc(
    createDuel: sl(),
  ));

  sl.registerFactory(() => DuelStatsBloc(
    getUserDuelStats: sl(),
    getDuelStatsLeaderboard: sl(),
  ));

  sl.registerFactory(() => DuelInvitationsBloc(
    getDuelInvitations: sl(),
    respondToInvitation: sl(),
  ));
}
