part of 'active_session_bloc.dart';

abstract class ActiveSessionEvent extends Equatable {
  const ActiveSessionEvent();
  
  @override
  List<Object?> get props => [];
}

class SessionStarted extends ActiveSessionEvent {
  final int? plannedDuration; // in seconds
  final double ruckWeightKg;
  final String? notes;
  final LocationPoint? initialLocation;
  
  const SessionStarted({
    required this.ruckWeightKg,
    this.notes,
    this.plannedDuration,
    this.initialLocation,
  });
  
  @override
  List<Object?> get props => [ruckWeightKg, notes, plannedDuration, initialLocation];
}

class LocationUpdated extends ActiveSessionEvent {
  final LocationPoint locationPoint;
  
  const LocationUpdated(this.locationPoint);
  
  @override
  List<Object?> get props => [locationPoint];
}

class SessionPaused extends ActiveSessionEvent {
  const SessionPaused();
}

class SessionResumed extends ActiveSessionEvent {
  const SessionResumed();
}

class SessionCompleted extends ActiveSessionEvent {
  final List<String>? tags;
  final int? perceivedExertion;
  final double? weightKg;
  final int? plannedDurationMinutes;
  final int? pausedDurationSeconds;
  final String? notes;
  final int? rating;
  
  const SessionCompleted({
    this.notes,
    this.rating,
    this.tags,
    this.perceivedExertion,
    this.weightKg,
    this.plannedDurationMinutes,
    this.pausedDurationSeconds,
  });
  
  @override
  List<Object?> get props => [
    notes,
    rating,
    tags,
    perceivedExertion,
    weightKg,
    plannedDurationMinutes,
    pausedDurationSeconds,
  ];
}

/// Event for live heart-rate samples
class HeartRateUpdated extends ActiveSessionEvent {
  final HeartRateSample sample;
  const HeartRateUpdated(this.sample);

  @override
  List<Object?> get props => [sample];
}

/// Internal ticker (1-second) to update elapsed time & derived metrics
class Tick extends ActiveSessionEvent {
  const Tick();
}

class SessionFailed extends ActiveSessionEvent {
  final String errorMessage;
  
  const SessionFailed({required this.errorMessage});
  
  @override
  List<Object?> get props => [errorMessage];
}

class SessionErrorCleared extends ActiveSessionEvent {
  const SessionErrorCleared();

  @override
  List<Object?> get props => [];
}

class TimerStarted extends ActiveSessionEvent {
  const TimerStarted();

  @override
  List<Object?> get props => [];
}
