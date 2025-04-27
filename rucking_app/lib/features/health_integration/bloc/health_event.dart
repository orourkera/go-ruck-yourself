part of 'health_bloc.dart';

abstract class HealthEvent extends Equatable {
  const HealthEvent();

  @override
  List<Object?> get props => [];
}

class CheckHealthIntegrationAvailability extends HealthEvent {
  const CheckHealthIntegrationAvailability();
}

class RequestHealthAuthorization extends HealthEvent {
  const RequestHealthAuthorization();
}

class DisableHealthIntegration extends HealthEvent {
  const DisableHealthIntegration();
}

class MarkHealthIntroSeen extends HealthEvent {
  const MarkHealthIntroSeen();
}

class SetHasAppleWatch extends HealthEvent {
  final bool hasWatch;
  
  const SetHasAppleWatch({required this.hasWatch});
  
  @override
  List<Object?> get props => [hasWatch];
}

class WriteHealthData extends HealthEvent {
  final double distanceMeters;
  final double caloriesBurned;
  final DateTime startTime;
  final DateTime endTime;

  const WriteHealthData({
    required this.distanceMeters,
    required this.caloriesBurned,
    required this.startTime,
    required this.endTime,
  });

  @override
  List<Object?> get props => [distanceMeters, caloriesBurned, startTime, endTime];
}

class SaveRuckWorkout extends HealthEvent {
  final double distanceMeters;
  final double caloriesBurned;
  final DateTime startTime;
  final DateTime endTime;
  final double? ruckWeightKg;
  final double? elevationGainMeters;
  final double? elevationLossMeters;
  final double? heartRate;

  const SaveRuckWorkout({
    required this.distanceMeters,
    required this.caloriesBurned,
    required this.startTime,
    required this.endTime,
    this.ruckWeightKg,
    this.elevationGainMeters,
    this.elevationLossMeters,
    this.heartRate,
  });

  @override
  List<Object?> get props => [
    distanceMeters, 
    caloriesBurned, 
    startTime, 
    endTime,
    ruckWeightKg,
    elevationGainMeters,
    elevationLossMeters,
    heartRate,
  ];
}
