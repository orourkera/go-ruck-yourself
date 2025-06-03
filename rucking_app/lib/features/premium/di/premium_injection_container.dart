import 'package:get_it/get_it.dart';
import 'package:rucking_app/features/premium/presentation/bloc/premium_bloc.dart';
import 'package:rucking_app/features/premium/domain/services/premium_service.dart';
import 'package:rucking_app/core/services/revenue_cat_service.dart';

/// Initializes premium feature dependencies
void initPremiumFeature(GetIt sl) {
  // Register PremiumService implementation
  sl.registerLazySingleton<PremiumService>(() => PremiumServiceImpl(
    sl<RevenueCatService>(),
  ));
  
  // Register PremiumBloc as a singleton to maintain state across app
  sl.registerLazySingleton<PremiumBloc>(() => PremiumBloc(
    sl<PremiumService>(),
  ));
}