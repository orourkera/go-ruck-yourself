import 'package:equatable/equatable.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'package:rucking_app/core/models/location_point.dart';
import 'package:rucking_app/features/ruck_session/domain/models/heart_rate_sample.dart';
import 'package:meta/meta.dart';

/// Base class for all session events
@immutable
abstract class ActiveSessionEvent extends Equatable {
  const ActiveSessionEvent();
  
  @override
  List<Object?> get props => [];
}

/// Session lifecycle events
class SessionStartRequested extends ActiveSessionEvent {
  final String? sessionId;
  final double? ruckWeightKg;
  final double? userWeightKg;
  final List<latlong.LatLng>? plannedRoute;
  final double? plannedRouteDistance;
  final int? plannedRouteDuration;
  
  const SessionStartRequested({
    this.sessionId,
    this.ruckWeightKg,
    this.userWeightKg,
    this.plannedRoute,
    this.plannedRouteDistance,
    this.plannedRouteDuration,
  });
  
  @override
  List<Object?> get props => [sessionId, ruckWeightKg, userWeightKg, plannedRoute, plannedRouteDistance, plannedRouteDuration];
}

class SessionStopRequested extends ActiveSessionEvent {
  const SessionStopRequested();
}

class SessionPaused extends ActiveSessionEvent {
  const SessionPaused();
}

class SessionResumed extends ActiveSessionEvent {
  const SessionResumed();
}

class Tick extends ActiveSessionEvent {
  const Tick();
}

class TimerStarted extends ActiveSessionEvent {
  const TimerStarted();
}

class TimerStopped extends ActiveSessionEvent {
  const TimerStopped();
}

class SessionReset extends ActiveSessionEvent {
  const SessionReset();
}

class SessionBatchUploadRequested extends ActiveSessionEvent {
  final String sessionId;
  
  const SessionBatchUploadRequested({required this.sessionId});
  
  @override
  List<Object?> get props => [sessionId];
}

class OfflineSessionSyncRequested extends ActiveSessionEvent {
  const OfflineSessionSyncRequested();
}

class OfflineSessionSyncAttemptRequested extends ActiveSessionEvent {
  final String sessionId;
  
  const OfflineSessionSyncAttemptRequested({required this.sessionId});
  
  @override
  List<Object?> get props => [sessionId];
}

class CompletionPayloadBuildRequested extends ActiveSessionEvent {
  final dynamic currentState;
  final Map<String, dynamic> terrainStats;
  final List<dynamic> route;
  final List<dynamic> heartRateSamples;
  
  const CompletionPayloadBuildRequested({
    required this.currentState,
    required this.terrainStats,
    required this.route,
    required this.heartRateSamples,
  });
  
  @override
  List<Object?> get props => [currentState, terrainStats, route, heartRateSamples];
}

class ConnectivityMonitoringStartRequested extends ActiveSessionEvent {
  final String sessionId;
  
  const ConnectivityMonitoringStartRequested({required this.sessionId});
  
  @override
  List<Object?> get props => [sessionId];
}

class LocationTrackingEnsureActiveRequested extends ActiveSessionEvent {
  final String sessionId;
  
  const LocationTrackingEnsureActiveRequested({required this.sessionId});
  
  @override
  List<Object?> get props => [sessionId];
}

/// Location events
class LocationUpdated extends ActiveSessionEvent {
  final Position position;
  
  const LocationUpdated({required this.position});
  
  @override
  List<Object?> get props => [position];
}

class BatchLocationUpdated extends ActiveSessionEvent {
  final List<LocationPoint> locationPoints;
  
  const BatchLocationUpdated({required this.locationPoints});
  
  @override
  List<Object?> get props => [locationPoints];
}

/// Heart rate events
class HeartRateUpdated extends ActiveSessionEvent {
  final int heartRate;
  final DateTime timestamp;
  
  const HeartRateUpdated({
    required this.heartRate,
    required this.timestamp,
  });
  
  @override
  List<Object?> get props => [heartRate, timestamp];
}

class HeartRateMonitoringStartRequested extends ActiveSessionEvent {
  final String sessionId;
  
  const HeartRateMonitoringStartRequested({required this.sessionId});
  
  @override
  List<Object?> get props => [sessionId];
}

class HeartRateMonitoringStopRequested extends ActiveSessionEvent {
  const HeartRateMonitoringStopRequested();
}

class HeartRateBatchUploadRequested extends ActiveSessionEvent {
  final List<HeartRateSample> samples;
  
  const HeartRateBatchUploadRequested({required this.samples});
  
  @override
  List<Object?> get props => [samples];
}

/// Photo events
class PhotoAdded extends ActiveSessionEvent {
  final String photoPath;
  
  const PhotoAdded({required this.photoPath});
  
  @override
  List<Object?> get props => [photoPath];
}

class PhotoDeleted extends ActiveSessionEvent {
  final String photoId;
  
  const PhotoDeleted({required this.photoId});
  
  @override
  List<Object?> get props => [photoId];
}


/// Memory events
class MemoryAdded extends ActiveSessionEvent {
  final String memory;
  final DateTime timestamp;
  
  const MemoryAdded({
    required this.memory,
    required this.timestamp,
  });
  
  @override
  List<Object?> get props => [memory, timestamp];
}

class MemoryUpdated extends ActiveSessionEvent {
  final String key;
  final dynamic value;
  final bool immediate;
  
  const MemoryUpdated({
    required this.key,
    required this.value,
    this.immediate = false,
  });
  
  @override
  List<Object?> get props => [key, value, immediate];
}

class MemoryPressureDetected extends ActiveSessionEvent {
  final double memoryUsageMb;
  final DateTime timestamp;
  
  const MemoryPressureDetected({
    required this.memoryUsageMb,
    required this.timestamp,
  });
  
  @override
  List<Object?> get props => [memoryUsageMb, timestamp];
}

class RestoreSessionRequested extends ActiveSessionEvent {
  final String? sessionId;
  
  const RestoreSessionRequested({this.sessionId});
  
  @override
  List<Object?> get props => [sessionId];
}

/// Recovery events
class RecoveryRequested extends ActiveSessionEvent {
  final String sessionId;
  
  const RecoveryRequested({required this.sessionId});
  
  @override
  List<Object?> get props => [sessionId];
}
