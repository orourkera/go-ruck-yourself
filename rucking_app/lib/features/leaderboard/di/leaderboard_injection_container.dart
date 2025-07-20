import 'package:get_it/get_it.dart';
import '../data/repositories/leaderboard_repository.dart';
import '../presentation/bloc/leaderboard_bloc.dart';
import '../../../core/services/api_client.dart';

/// Well I'll be! This here sets up all them dependencies slicker than a whistle
final sl = GetIt.instance;

/// Initialize leaderboard dependencies like organizing a barn
Future<void> initLeaderboardDependencies() async {
  // Repository - the data wrangler
  sl.registerLazySingleton<LeaderboardRepository>(
    () => LeaderboardRepository(
      apiClient: sl<ApiClient>(),
    ),
  );

  // Bloc - the state manager that's smarter than a whip
  sl.registerFactory<LeaderboardBloc>(
    () => LeaderboardBloc(
      repository: sl<LeaderboardRepository>(),
    ),
  );
}
