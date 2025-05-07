part of 'active_session_bloc.dart';

abstract class ActiveSessionEvent extends Equatable {
  const ActiveSessionEvent();
  
  @override
  List<Object?> get props => [];
}

class SessionStarted extends ActiveSessionEvent {
  final double ruckWeightKg;
  final String? notes;
  
  const SessionStarted({
    required this.ruckWeightKg,
    this.notes,
  });
  
  @override
  List<Object?> get props => [ruckWeightKg, notes];
}

class LocationUpdated extends ActiveSessionEvent {
  final LocationPoint locationPoint;
  
  const LocationUpdated(this.locationPoint);
  
  @override
  List<Object?> get props => [locationPoint];
}

class SessionPaused extends ActiveSessionEvent {}

class SessionResumed extends ActiveSessionEvent {}

class SessionCompleted extends ActiveSessionEvent {
  final String? notes;
  final int? rating;
  
  const SessionCompleted({this.notes, this.rating});
  
  @override
  List<Object?> get props => [notes, rating];
}

/// Event for live heart-rate samples
class HeartRateUpdated extends ActiveSessionEvent {
  final HeartRateSample sample;
  const HeartRateUpdated(this.sample);

  @override
  List<Object?> get props => [sample];
}

class SessionFailed extends ActiveSessionEvent {
  final String errorMessage;
  
  const SessionFailed({required this.errorMessage});
  
  @override
  List<Object?> get props => [errorMessage];
}
