import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:rucking_app/core/services/auth_service.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/social/data/repositories/social_repository.dart';
import 'package:rucking_app/features/social/presentation/bloc/social_bloc.dart';

/// Initialize the social feature dependencies
void initSocialFeature(GetIt sl) {
  // Register SocialBloc as a singleton in GetIt to ensure state is shared across all screens
  sl.registerLazySingleton<SocialBloc>(
    () => SocialBloc(
      socialRepository: sl(),
      authBloc: sl<AuthBloc>(),
    ),
  );

  // Register SocialRepository
  sl.registerLazySingleton<SocialRepository>(
    () => SocialRepository(
      httpClient: http.Client(),
      authService: sl<AuthService>(),
    ),
  );
}
