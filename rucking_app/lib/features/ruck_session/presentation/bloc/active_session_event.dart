part of 'active_session_bloc.dart';

@immutable
abstract class ActiveSessionEvent extends Equatable {
  const ActiveSessionEvent();
  
  @override
  List<Object?> get props => [];
}

/// Enum to describe the origin of a session action (pause, resume, etc.)
enum SessionActionSource {
  ui,        // Action initiated by the user on the phone UI
  watch,     // Action initiated by the user on the watch UI or by the watch system
  system,    // Action initiated by the system (e.g., auto-pause, background process)
  unknown,   // Source is unknown
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
  final SessionActionSource source;
  const SessionPaused({this.source = SessionActionSource.unknown});

  @override
  List<Object?> get props => [source];
}

class SessionResumed extends ActiveSessionEvent {
  final SessionActionSource source;
  const SessionResumed({this.source = SessionActionSource.unknown});

  @override
  List<Object?> get props => [source];
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

class FetchSessionPhotosRequested extends ActiveSessionEvent {
  final String ruckId;

  const FetchSessionPhotosRequested(this.ruckId);

  @override
  List<Object?> get props => [ruckId];
}

class UploadSessionPhotosRequested extends ActiveSessionEvent {
  final String sessionId;
  final List<File> photos;

  const UploadSessionPhotosRequested({
    required this.sessionId,
    required this.photos,
  });

  @override
  List<Object?> get props => [sessionId, photos];
}

class ClearSessionPhotos extends ActiveSessionEvent {
  final String ruckId;

  const ClearSessionPhotos({required this.ruckId});

  @override
  List<Object?> get props => [ruckId];
}

class DeleteSessionPhotoRequested extends ActiveSessionEvent {
  final String sessionId;
  final dynamic photo; 

  DeleteSessionPhotoRequested({
    required this.sessionId,
    required this.photo,
  });

  @override
  List<Object?> get props => [sessionId, photo];
}

// Event to update photos in state without going through the normal clear/fetch cycle
class UpdateStateWithSessionPhotos extends ActiveSessionEvent {
  final String sessionId;
  final List<dynamic> photos;

  UpdateStateWithSessionPhotos({
    required this.sessionId,
    required this.photos,
  });

  @override
  List<Object?> get props => [sessionId, photos];
}

class TakePhotoRequested extends ActiveSessionEvent {
  final String sessionId;

  const TakePhotoRequested({required this.sessionId});

  @override
  List<Object?> get props => [sessionId];
}

class PickPhotoRequested extends ActiveSessionEvent {
  final String sessionId;

  const PickPhotoRequested({required this.sessionId});

  @override
  List<Object?> get props => [sessionId];
}

class LoadSessionForViewing extends ActiveSessionEvent {
  final String sessionId;
  final RuckSession session;

  const LoadSessionForViewing({
    required this.sessionId,
    required this.session,
  });

  @override
  List<Object?> get props => [sessionId, session];
}
