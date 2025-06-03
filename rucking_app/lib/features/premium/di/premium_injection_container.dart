import 'package:get_it/get_it.dart';
import 'package:rucking_app/features/premium/domain/services/premium_service.dart';
import 'package:rucking_app/features/premium/data/services/premium_service_impl.dart';
import 'package:rucking_app/features/premium/presentation/bloc/premium_bloc.dart';
import 'package:rucking_app/features/premium/domain/repositories/premium_repository.dart';
import 'package:rucking_app/features/premium/data/repositories/premium_repository_impl.dart';
import 'package:rucking_app/features/premium/data/services/forced_sharing_service.dart';
import 'package:rucking_app/core/services/revenue_cat_service.dart';

/// Initializes premium feature dependencies
void initPremiumFeature(GetIt getIt) {
  // Register premium repository
  getIt.registerLazySingleton<PremiumRepository>(
    () => PremiumRepositoryImpl(getIt<RevenueCatService>()),
  );

  // Register premium service implementation
  getIt.registerLazySingleton<PremiumService>(
    () => PremiumServiceImpl(getIt<RevenueCatService>()),
  );

  // Register forced sharing service for freemium model
  getIt.registerLazySingleton<ForcedSharingService>(
    () => ForcedSharingService(getIt<PremiumService>()),
  );

  // Register premium bloc
  getIt.registerFactory<PremiumBloc>(
    () => PremiumBloc(getIt<PremiumService>()),
  );
}