import 'package:equatable/equatable.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rucking_app/core/models/location_point.dart';
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
  
  const SessionStartRequested({
    this.sessionId,
    this.ruckWeightKg,
    this.userWeightKg,
  });
  
  @override
  List<Object?> get props => [sessionId, ruckWeightKg, userWeightKg];
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
