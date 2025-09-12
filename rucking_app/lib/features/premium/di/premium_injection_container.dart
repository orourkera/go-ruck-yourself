import 'package:get_it/get_it.dart';
import 'package:rucking_app/features/premium/services/premium_service.dart';
import 'package:rucking_app/features/premium/presentation/bloc/premium_bloc.dart';

final getIt = GetIt.instance;

/// Simple premium dependency setup
void setupPremiumDependencies() {
  // Service
  getIt.registerLazySingleton<PremiumService>(
    () => PremiumService(getIt()),
  );

  // BLoC
  getIt.registerFactory<PremiumBloc>(
    () => PremiumBloc(getIt<PremiumService>()),
  );
}
