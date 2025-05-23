import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
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
    on<SetHasAppleWatch>(_onSetHasAppleWatch);
  }

  Future<void> _onCheckAvailability(
    CheckHealthIntegrationAvailability event,
    Emitter<HealthState> emit,
  ) async {
    emit(HealthLoading());
    final isAvailable = await healthService.isHealthIntegrationAvailable();
    if (isAvailable) {
      final hasSeenIntro = await healthService.hasSeenIntro();
      final hasWatch = await healthService.hasAppleWatch();
      emit(HealthAvailable(hasSeenIntro: hasSeenIntro, hasAppleWatch: hasWatch));
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
    debugPrint('[HealthBloc] writeHealthData → $success'); // Added debug logging
    emit(HealthDataWriteStatus(success: success));
  }

  Future<void> _onSaveRuckWorkout(
    SaveRuckWorkout event,
    Emitter<HealthState> emit,
  ) async {
    emit(HealthLoading());
    final success = await healthService.saveWorkout(
      startDate: event.startTime,
      endDate: event.endTime,
      distanceKm: event.distanceMeters / 1000, // Convert meters to km
      caloriesBurned: event.caloriesBurned.toInt(), // Convert to int
      ruckWeightKg: event.ruckWeightKg,
      elevationGainMeters: event.elevationGainMeters,
      elevationLossMeters: event.elevationLossMeters,
      heartRate: event.heartRate,
    );
    AppLogger.info('Health workout save result: $success');
    emit(HealthDataWriteStatus(success: success));
  }

  Future<void> _onMarkHealthIntroSeen(
    MarkHealthIntroSeen event,
    Emitter<HealthState> emit,
  ) async {
    await healthService.setHasSeenIntro();
    emit(const HealthIntroShown());
  }

  Future<void> _onSetHasAppleWatch(
    SetHasAppleWatch event,
    Emitter<HealthState> emit,
  ) async {
    await healthService.setHasAppleWatch(event.hasWatch);
    
    // Update the state - get current seen intro status
    final hasSeenIntro = await healthService.hasSeenIntro();
    
    if (state is HealthAvailable) {
      emit(HealthAvailable(
        hasSeenIntro: hasSeenIntro, 
        hasAppleWatch: event.hasWatch
      ));
    }
    
    // Mark intro as seen
    await healthService.setHasSeenIntro();
    emit(const HealthIntroShown());
  }
  
  Future<void> _onDisableHealthIntegration(
    DisableHealthIntegration event,
    Emitter<HealthState> emit,
  ) async {
    emit(HealthLoading());
    await healthService.setHealthIntegrationEnabled(false);
    emit(HealthDisabled());
  }

  // Convenience method to disable health integration
  void setHealthIntegrationEnabled(bool enabled) {
    if (!enabled) {
      add(const DisableHealthIntegration());
    }
  }
}
