import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/auth_service.dart';
import 'package:rucking_app/features/social/data/repositories/social_repository.dart';
import 'package:rucking_app/features/social/presentation/bloc/social_bloc.dart';

/// Initialize the social feature dependencies
void initSocialFeature(GetIt sl) {
  // Register SocialBloc as a factory in GetIt
  sl.registerFactory<SocialBloc>(
    () => SocialBloc(
      socialRepository: sl(),
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
