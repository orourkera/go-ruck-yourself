part of active_session_bloc;

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
  final double userWeightKg;
  final String? eventId; // Add event ID for event-linked sessions
  final List<latlong.LatLng>? plannedRoute; // Add planned route for navigation
  final double? plannedRouteDistance; // Route distance in km
  final int? plannedRouteDuration; // Route estimated duration in minutes
  final bool aiCheerleaderEnabled; // AI Cheerleader feature toggle
  final String? aiCheerleaderPersonality; // Selected personality type
  final bool aiCheerleaderExplicitContent; // Explicit language preference
  final String? sessionId; // Optional session identifier for propagation
  
  const SessionStarted({
    required this.ruckWeightKg,
    required this.userWeightKg,
    this.notes,
    this.plannedDuration,
    this.initialLocation,
    this.eventId, // Add eventId parameter
    this.plannedRoute, // Add plannedRoute parameter
    this.plannedRouteDistance, // Add route distance parameter
    this.plannedRouteDuration, // Add route duration parameter
    required this.aiCheerleaderEnabled, // Required AI Cheerleader toggle
    this.aiCheerleaderPersonality, // Optional personality selection
    required this.aiCheerleaderExplicitContent, // Required explicit content preference
    this.sessionId, // Optional sessionId for watch-initiated or recovered sessions
  });
  
  @override
  List<Object?> get props => [ruckWeightKg, notes, plannedDuration, initialLocation, userWeightKg, eventId, plannedRoute, plannedRouteDistance, plannedRouteDuration, aiCheerleaderEnabled, aiCheerleaderPersonality, aiCheerleaderExplicitContent, sessionId];
}

class SessionRecoveryRequested extends ActiveSessionEvent {
  const SessionRecoveryRequested();
  
  @override
  List<Object?> get props => [];
}

/// Event to clear orphaned session data from local storage only
/// Does NOT delete the session from the database - safer than deletion
class ClearOrphanedSessionRequested extends ActiveSessionEvent {
  const ClearOrphanedSessionRequested();
  
  @override
  List<Object?> get props => [];
}

class LocationUpdated extends ActiveSessionEvent {
  final LocationPoint locationPoint;
  
  const LocationUpdated(this.locationPoint);
  
  @override
  List<Object?> get props => [locationPoint];
}

class BatchLocationUpdated extends ActiveSessionEvent {
  final List<LocationPoint> locationPoints;
  
  const BatchLocationUpdated(this.locationPoints);
  
  @override
  List<Object?> get props => [locationPoints];
}

class SessionPaused extends ActiveSessionEvent {
  final SessionActionSource source;
  final String? sessionId; // Optional session identifier for propagation
  const SessionPaused({this.source = SessionActionSource.unknown, this.sessionId});

  @override
  List<Object?> get props => [source, sessionId];
}

class SessionResumed extends ActiveSessionEvent {
  final SessionActionSource source;
  final String? sessionId; // Optional session identifier for propagation
  const SessionResumed({this.source = SessionActionSource.unknown, this.sessionId});

  @override
  List<Object?> get props => [source, sessionId];
}

class SessionCompleted extends ActiveSessionEvent {
  final List<String>? tags;
  final int? perceivedExertion;
  final double? weightKg;
  final int? plannedDurationMinutes;
  final int? pausedDurationSeconds;
  final String? notes;
  final int? rating;
  final String? sessionId; // Optional session identifier for propagation
  
  const SessionCompleted({
    this.notes,
    this.rating,
    this.tags,
    this.perceivedExertion,
    this.weightKg,
    this.plannedDurationMinutes,
    this.pausedDurationSeconds,
    this.sessionId,
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
    sessionId,
  ];
}

/// Event for live heart-rate samples
class HeartRateUpdated extends ActiveSessionEvent {
  final HeartRateSample sample;
  const HeartRateUpdated(this.sample);

  @override
  List<Object?> get props => [sample];
}

/// Event for batch processing of heart-rate samples
class HeartRateBufferProcessed extends ActiveSessionEvent {
  final List<HeartRateSample> samples;
  const HeartRateBufferProcessed(this.samples);

  @override
  List<Object?> get props => [samples];
}

/// Internal ticker (1-second) to update elapsed time & derived metrics
class Tick extends ActiveSessionEvent {
  const Tick();
}

class SessionFailed extends ActiveSessionEvent {
  final String errorMessage;
  final String sessionId;
  final RuckSession? session;
  
  const SessionFailed({
    required this.errorMessage,
    required this.sessionId,
    this.session,
  });
  
  @override
  List<Object?> get props => [errorMessage, sessionId, session];
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

/// Event to reset the session state after saving, returning to initial state
class SessionReset extends ActiveSessionEvent {
  const SessionReset();

  @override
  List<Object?> get props => [];
}

/// Event to clean up session resources (for app lifecycle management)
class SessionCleanupRequested extends ActiveSessionEvent {
  const SessionCleanupRequested();

  @override
  List<Object?> get props => [];
}

/// Event triggered when system memory pressure is detected
class MemoryPressureDetected extends ActiveSessionEvent {
  const MemoryPressureDetected();

  @override
  List<Object?> get props => [];
}

/// Event to trigger batch upload of session data
class SessionBatchUploadRequested extends ActiveSessionEvent {
  final String sessionId;
  
  const SessionBatchUploadRequested({required this.sessionId});
  
  @override
  List<Object?> get props => [sessionId];
}

/// Event to start heart rate monitoring
class HeartRateMonitoringStartRequested extends ActiveSessionEvent {
  final String sessionId;
  
  const HeartRateMonitoringStartRequested({required this.sessionId});
  
  @override
  List<Object?> get props => [sessionId];
}

/// Event to stop heart rate monitoring
class HeartRateMonitoringStopRequested extends ActiveSessionEvent {
  const HeartRateMonitoringStopRequested();
  
  @override
  List<Object?> get props => [];
}

/// Event to trigger batch upload of heart rate data
class HeartRateBatchUploadRequested extends ActiveSessionEvent {
  final List<HeartRateSample> samples;
  
  const HeartRateBatchUploadRequested({required this.samples});
  
  @override
  List<Object?> get props => [samples];
}

/// Event to trigger offline session sync
class OfflineSessionSyncRequested extends ActiveSessionEvent {
  const OfflineSessionSyncRequested();
  
  @override
  List<Object?> get props => [];
}

/// Event to trigger completion payload building
class CompletionPayloadBuildRequested extends ActiveSessionEvent {
  final ActiveSessionRunning currentState;
  final Map<String, dynamic> terrainStats;
  final List<LocationPoint> route;
  final List<HeartRateSample> heartRateSamples;
  
  const CompletionPayloadBuildRequested({
    required this.currentState,
    required this.terrainStats,
    required this.route,
    required this.heartRateSamples,
  });
  
  @override
  List<Object?> get props => [currentState, terrainStats, route, heartRateSamples];
}

/// Event to start connectivity monitoring
class ConnectivityMonitoringStartRequested extends ActiveSessionEvent {
  final String sessionId;
  
  const ConnectivityMonitoringStartRequested({required this.sessionId});
  
  @override
  List<Object?> get props => [sessionId];
}

/// Event to ensure location tracking is active
class LocationTrackingEnsureActiveRequested extends ActiveSessionEvent {
  final String sessionId;
  
  const LocationTrackingEnsureActiveRequested({required this.sessionId});
  
  @override
  List<Object?> get props => [sessionId];
}

/// Event to attempt offline session sync
class OfflineSessionSyncAttemptRequested extends ActiveSessionEvent {
  final String sessionId;
  
  const OfflineSessionSyncAttemptRequested({required this.sessionId});
  
  @override
  List<Object?> get props => [sessionId];
}

/// Internal event to trigger state aggregation
class StateAggregationRequested extends ActiveSessionEvent {
  const StateAggregationRequested();
  
  @override
  List<Object?> get props => [];
}

/// Event to check for crashed sessions on app startup
class CheckForCrashedSession extends ActiveSessionEvent {
  const CheckForCrashedSession();
  
  @override
  List<Object?> get props => [];
}

class SessionRecovered extends ActiveSessionEvent {
  @override
  List<Object> get props => [];
}

/// Event to manually trigger AI Cheerleader speech on demand
class AICheerleaderManualTriggerRequested extends ActiveSessionEvent {
  const AICheerleaderManualTriggerRequested();
  
  @override
  List<Object?> get props => [];
}
