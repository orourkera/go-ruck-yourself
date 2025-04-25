import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:rucking_app/features/health_integration/domain/health_service.dart';

part 'health_event.dart';
part 'health_state.dart';

class HealthBloc extends Bloc<HealthEvent, HealthState> {
  final HealthService healthService;

  HealthBloc({required this.healthService, String? userId}) : super(HealthInitial()) {
    // Set the user ID if provided
    if (userId != null && userId.isNotEmpty) {
      healthService.setUserId(userId);
    }
    
    on<CheckHealthIntegrationAvailability>(_onCheckAvailability);
    on<RequestHealthAuthorization>(_onRequestAuthorization);
    on<WriteHealthData>(_onWriteHealthData);
    on<SaveRuckWorkout>(_onSaveRuckWorkout);
    on<MarkHealthIntroSeen>(_onMarkHealthIntroSeen);
    on<DisableHealthIntegration>(_onDisableHealthIntegration);
  }

  Future<void> _onCheckAvailability(
    CheckHealthIntegrationAvailability event,
    Emitter<HealthState> emit,
  ) async {
    emit(HealthLoading());
    final isAvailable = await healthService.isHealthIntegrationAvailable();
    if (isAvailable) {
      final hasSeenIntro = await healthService.hasSeenIntro();
      emit(HealthAvailable(hasSeenIntro: hasSeenIntro));
    } else {
      emit(HealthUnavailable());
    }
  }

  Future<void> _onRequestAuthorization(
    RequestHealthAuthorization event,
    Emitter<HealthState> emit,
  ) async {
    emit(HealthLoading());
    final authorized = await healthService.requestAuthorization();
    emit(HealthAuthorizationStatus(authorized: authorized));
  }

  Future<void> _onWriteHealthData(
    WriteHealthData event,
    Emitter<HealthState> emit,
  ) async {
    emit(HealthLoading());
    final success = await healthService.writeHealthData(
      event.distanceMeters,
      event.caloriesBurned,
      event.startTime,
      event.endTime,
    );
    emit(HealthDataWriteStatus(success: success));
  }

  Future<void> _onSaveRuckWorkout(
    SaveRuckWorkout event,
    Emitter<HealthState> emit,
  ) async {
    emit(HealthLoading());
    final success = await healthService.saveRuckWorkout(
      distanceMeters: event.distanceMeters,
      caloriesBurned: event.caloriesBurned,
      startTime: event.startTime,
      endTime: event.endTime,
      ruckWeightKg: event.ruckWeightKg,
      elevationGainMeters: event.elevationGainMeters,
      elevationLossMeters: event.elevationLossMeters,
      heartRate: event.heartRate,
    );
    emit(HealthDataWriteStatus(success: success));
  }

  Future<void> _onMarkHealthIntroSeen(
    MarkHealthIntroSeen event,
    Emitter<HealthState> emit,
  ) async {
    await healthService.setHasSeenIntro();
    emit(HealthIntroShown());
  }
  
  Future<void> _onDisableHealthIntegration(
    DisableHealthIntegration event,
    Emitter<HealthState> emit,
  ) async {
    emit(HealthLoading());
    await healthService.disableHealthIntegration();
    emit(HealthDisabled());
  }

  // Convenience method to disable health integration
  void disableHealthIntegration() {
    add(const DisableHealthIntegration());
  }
}
