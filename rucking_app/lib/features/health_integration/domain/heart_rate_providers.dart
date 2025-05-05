import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rucking_app/features/health_integration/domain/health_service.dart';
import 'package:rucking_app/features/ruck_session/domain/models/heart_rate_sample.dart';

/// Provider for the singleton HealthService
final healthServiceProvider = Provider<HealthService>((ref) => HealthService());

/// StreamProvider for live heart rate samples (every 5 seconds)
final heartRateStreamProvider = StreamProvider<HeartRateSample>((ref) {
  final healthService = ref.watch(healthServiceProvider);
  return healthService.heartRateStream;
});

/// FutureProvider to check if health integration is enabled
final healthIntegrationEnabledProvider = FutureProvider<bool>((ref) async {
  final healthService = ref.watch(healthServiceProvider);
  return await healthService.isHealthIntegrationEnabled();
});
