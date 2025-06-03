import 'package:get_it/get_it.dart';
import 'package:rucking_app/features/premium/presentation/bloc/premium_bloc.dart';
import 'package:rucking_app/features/premium/domain/services/premium_service.dart';
import 'package:rucking_app/core/services/revenue_cat_service.dart';

/// Premium feature module for dependency injection
class PremiumModule {
  static void configure(GetIt getIt) {
    // Services
    getIt.registerLazySingleton<PremiumService>(
      () => PremiumServiceImpl(getIt<RevenueCatService>()),
    );
    
    // BLoCs
    getIt.registerLazySingleton<PremiumBloc>(
      () => PremiumBloc(getIt<PremiumService>()),
    );
  }
}