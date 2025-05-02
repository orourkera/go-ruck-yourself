import 'dart:async';
import 'dart:math';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/location_service.dart';
import 'package:rucking_app/core/models/location_point.dart';
import 'package:rucking_app/core/utils/measurement_utils.dart'; // Import MeasurementUtils
import 'package:rucking_app/core/utils/met_calculator.dart'; // Import MetCalculator

// Events
abstract class ActiveSessionEvent extends Equatable {
  const ActiveSessionEvent();
  
  @override
  List<Object?> get props => [];
}

class SessionStarted extends ActiveSessionEvent {
  final String ruckId;
  final double? userWeightKg;
  final double? ruckWeightKg;
  
  const SessionStarted({
    required this.ruckId,
    this.userWeightKg,
    this.ruckWeightKg,
  });
  
  @override
  List<Object?> get props => [ruckId, userWeightKg, ruckWeightKg];
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
  final String? notes;
  final int? rating;
  
  const SessionCompleted({this.notes, this.rating});
  
  @override
  List<Object?> get props => [notes, rating];
}

// States
abstract class ActiveSessionState extends Equatable {
  const ActiveSessionState();
  
  @override
  List<Object?> get props => [];
}

class ActiveSessionInitial extends ActiveSessionState {}

class ActiveSessionInProgress extends ActiveSessionState {
  final String ruckId;
  final List<LocationPoint> locationPoints;
  final Duration elapsed;
  final double distance;
  final double elevationGain;
  final double elevationLoss;
  final double caloriesBurned;
  final double pace;
  final double? userWeightKg;
  final double? ruckWeightKg;
  
  const ActiveSessionInProgress({
    required this.ruckId,
    required this.locationPoints,
    required this.elapsed,
    required this.distance,
    required this.elevationGain,
    required this.elevationLoss,
    required this.caloriesBurned,
    required this.pace,
    this.userWeightKg,
    this.ruckWeightKg,
  });
  
  @override
  List<Object?> get props => [
    ruckId, 
    locationPoints, 
    elapsed, 
    distance, 
    elevationGain, 
    elevationLoss, 
    caloriesBurned, 
    pace,
    userWeightKg,
    ruckWeightKg,
  ];
  
  ActiveSessionInProgress copyWith({
    String? ruckId,
    List<LocationPoint>? locationPoints,
    Duration? elapsed,
    double? distance,
    double? elevationGain,
    double? elevationLoss,
    double? caloriesBurned,
    double? pace,
    double? userWeightKg,
    double? ruckWeightKg,
  }) {
    return ActiveSessionInProgress(
      ruckId: ruckId ?? this.ruckId,
      locationPoints: locationPoints ?? this.locationPoints,
      elapsed: elapsed ?? this.elapsed,
      distance: distance ?? this.distance,
      elevationGain: elevationGain ?? this.elevationGain,
      elevationLoss: elevationLoss ?? this.elevationLoss,
      caloriesBurned: caloriesBurned ?? this.caloriesBurned,
      pace: pace ?? this.pace,
      userWeightKg: userWeightKg ?? this.userWeightKg,
      ruckWeightKg: ruckWeightKg ?? this.ruckWeightKg,
    );
  }
}

class ActiveSessionPaused extends ActiveSessionInProgress {
  const ActiveSessionPaused({
    required super.ruckId,
    required super.locationPoints,
    required super.elapsed,
    required super.distance,
    required super.elevationGain,
    required super.elevationLoss,
    required super.caloriesBurned,
    required super.pace,
    super.userWeightKg,
    super.ruckWeightKg,
  });
}

class ActiveSessionError extends ActiveSessionState {
  final String message;
  
  const ActiveSessionError(this.message);
  
  @override
  List<Object?> get props => [message];
}

class ActiveSessionCompleted extends ActiveSessionState {
  final String ruckId;
  final Duration elapsed;
  final double distance;
  final double elevationGain;
  final double elevationLoss;
  final double caloriesBurned;
  final double? ruckWeightKg;
  final DateTime completedAt;

  const ActiveSessionCompleted({
    required this.ruckId,
    required this.elapsed,
    required this.distance,
    required this.elevationGain,
    required this.elevationLoss,
    required this.caloriesBurned,
    this.ruckWeightKg,
    required this.completedAt,
  });

  @override
  List<Object?> get props => [
        ruckId,
        elapsed,
        distance,
        elevationGain,
        elevationLoss,
        caloriesBurned,
        ruckWeightKg,
        completedAt,
      ];
}

// BLoC
class ActiveSessionBloc extends Bloc<ActiveSessionEvent, ActiveSessionState> {
  final ApiClient _apiClient;
  final LocationService _locationService;
  
  StreamSubscription<LocationPoint>? _locationSubscription;
  Timer? _timer;
  final Stopwatch _stopwatch = Stopwatch();
  bool _isSessionStarted = false;
  
  ActiveSessionBloc({
    required ApiClient apiClient,
    required LocationService locationService,
  }) : 
    _apiClient = apiClient,
    _locationService = locationService,
    super(ActiveSessionInitial()) {
    on<SessionStarted>(_onSessionStarted);
    on<LocationUpdated>(_onLocationUpdated);
    on<SessionPaused>(_onSessionPaused);
    on<SessionResumed>(_onSessionResumed);
    on<SessionCompleted>(_onSessionCompleted);
  }
  
  @override
  Future<void> close() {
    _locationSubscription?.cancel();
    _timer?.cancel();
    _stopwatch.stop();
    return super.close();
  }
  
  Future<void> _onSessionStarted(
    SessionStarted event, 
    Emitter<ActiveSessionState> emit
  ) async {
    try {
      // Start session on backend
      await _apiClient.post(
        '/rucks/${event.ruckId}/start',
        {}
      );
      debugPrint('Session start confirmed by API');
      
      // Session is now confirmed started
      _isSessionStarted = true;
      
      // Start time tracking
      _stopwatch.start();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (state is ActiveSessionInProgress) {
          final currentState = state as ActiveSessionInProgress;
          emit(currentState.copyWith(elapsed: Duration(seconds: _stopwatch.elapsed.inSeconds)));
        }
      });
      // Start location tracking
      _startLocationTracking();
      
      emit(ActiveSessionInProgress(
        ruckId: event.ruckId,
        locationPoints: [],
        elapsed: Duration.zero,
        distance: 0.0,
        elevationGain: 0.0,
        elevationLoss: 0.0,
        caloriesBurned: 0.0,
        pace: 0.0,
        userWeightKg: event.userWeightKg,
        ruckWeightKg: event.ruckWeightKg,
      ));
    } catch (e) {
      debugPrint('Error starting session from API: $e');
      
      // Set a flag to indicate session failed to start properly
      _isSessionStarted = false;
      
      // Continue with local tracking but warn about API issues
      debugPrint('WARNING: Session tracking will continue locally, but API synchronization may fail');
      
      // Still emit the in-progress state to allow tracking
      emit(ActiveSessionInProgress(
        ruckId: event.ruckId,
        locationPoints: [],
        elapsed: Duration.zero,
        distance: 0.0,
        elevationGain: 0.0,
        elevationLoss: 0.0,
        caloriesBurned: 0.0,
        pace: 0.0,
        userWeightKg: event.userWeightKg,
        ruckWeightKg: event.ruckWeightKg,
      ));
      
      // Try to start the stopwatch and timer anyway
      _stopwatch.start();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (state is ActiveSessionInProgress) {
          final currentState = state as ActiveSessionInProgress;
          emit(currentState.copyWith(elapsed: Duration(seconds: _stopwatch.elapsed.inSeconds)));
        }
      });
      
      // Try to start location tracking but it might fail to sync with API
      _startLocationTracking();
    }
  }
  
  Future<void> _onLocationUpdated(
    LocationUpdated event, 
    Emitter<ActiveSessionState> emit
  ) async {
    // Early return if not in a valid session state
    if (state is! ActiveSessionInProgress) {
      debugPrint('Ignoring location update: Not in ActiveSessionInProgress state');
      return;
    }
    
    // Get current state as ActiveSessionInProgress
    final currentState = state as ActiveSessionInProgress;
    
    // Bail out if we don't have a valid session ID
    if (currentState.ruckId.trim().isEmpty) {
      debugPrint('Ignoring location update: No valid ruckId');
      return;
    }
    
    // Handle case where location might be zeros (simulator or initial point)
    if (event.locationPoint.latitude == 0 && 
        event.locationPoint.longitude == 0) {
      debugPrint('Ignoring empty location update (zeros)');
      return;
    }
    
    // Real location update
    final newPoints = List<LocationPoint>.from(currentState.locationPoints)
      ..add(event.locationPoint);
    
    // Calculate distance and elevation changes
    double newDistance = currentState.distance;
    double elevationGain = currentState.elevationGain;
    double elevationLoss = currentState.elevationLoss;
    
    if (newPoints.length > 1) {
      // Get previous point
      final previousPoint = newPoints[newPoints.length - 2];
      
      // Calculate distance between points
      final double distanceInMeters = _calculateDistance(
        previousPoint.latitude, 
        previousPoint.longitude, 
        event.locationPoint.latitude, 
        event.locationPoint.longitude
      );
      
      // Only add distance if it's reasonable (not a GPS jump)
      if (distanceInMeters < 100) { // Skip unrealistic jumps
        newDistance += distanceInMeters / 1000; // Convert to km
        
        // Calculate elevation changes
        final double elevationDiff = event.locationPoint.elevation - previousPoint.elevation;
        if (elevationDiff > 0) {
          elevationGain += elevationDiff;
        } else if (elevationDiff < 0) {
          elevationLoss += elevationDiff.abs();
        }
      }
    }
    
    // Only send API updates if session is confirmed started
    if (_isSessionStarted) {
      try {
        debugPrint('Sending location update for ruckId: ${currentState.ruckId}');
        await _sendLocationUpdateToApi(
          event.locationPoint, 
          currentState.ruckId,
          elevationGain: elevationGain,
          elevationLoss: elevationLoss
        );
      } catch (e) {
        debugPrint('Error sending location update: $e');
      }
    } else {
      debugPrint('Skipping API location update: Session start not yet confirmed with backend');
    }
    
    // Calculate calories based on weight, distance, and elevation
    double caloriesBurned = currentState.caloriesBurned;
    if (currentState.userWeightKg != null && currentState.ruckWeightKg != null) {
      final totalWeight = currentState.userWeightKg! + currentState.ruckWeightKg!;
      // Simple calorie calculation: MET value * weight * time (in hours)
      // MET value for "walking with a weighted backpack" is around 7-8
      caloriesBurned = 8 * totalWeight * (currentState.elapsed.inSeconds / 3600);
    }
    
    // Calculate pace (min/km) if distance > 0
    double pace = 0.0;
    if (newDistance > 0) {
      pace = currentState.elapsed.inMinutes / newDistance;
    }
    
    // Emit updated state
    emit(currentState.copyWith(
      locationPoints: newPoints,
      distance: newDistance,
      elevationGain: elevationGain,
      elevationLoss: elevationLoss,
      caloriesBurned: caloriesBurned,
      pace: pace,
    ));
  }
  
  Future<void> _onSessionPaused(
    SessionPaused event, 
    Emitter<ActiveSessionState> emit
  ) async {
    if (state is ActiveSessionInProgress) {
      final currentState = state as ActiveSessionInProgress;
      
      // Pause time tracking
      _stopwatch.stop();
      
      // Pause location tracking
      _locationSubscription?.pause();
      
      // Notify API
      try {
        await _apiClient.post(
          '/rucks/${currentState.ruckId}/pause',
          {}
        );
        debugPrint('Successfully paused session via API');
      } catch (e) {
        debugPrint('Failed to pause session via API: $e');
        // Continue with local session even if API call fails
      }
      
      emit(ActiveSessionPaused(
        ruckId: currentState.ruckId,
        locationPoints: currentState.locationPoints,
        elapsed: currentState.elapsed,
        distance: currentState.distance,
        elevationGain: currentState.elevationGain,
        elevationLoss: currentState.elevationLoss,
        caloriesBurned: currentState.caloriesBurned,
        pace: currentState.pace,
        userWeightKg: currentState.userWeightKg,
        ruckWeightKg: currentState.ruckWeightKg,
      ));
    }
  }
  
  Future<void> _onSessionResumed(
    SessionResumed event, 
    Emitter<ActiveSessionState> emit
  ) async {
    if (state is ActiveSessionPaused) {
      final currentState = state as ActiveSessionPaused;
      
      // Resume time tracking
      _stopwatch.start();
      
      // Resume location tracking
      _locationSubscription?.resume();
      
      // Notify API
      try {
        await _apiClient.post(
          '/rucks/${currentState.ruckId}/resume',
          {}
        );
        debugPrint('Successfully resumed session via API');
      } catch (e) {
        debugPrint('Failed to resume session via API: $e');
        // Continue with local session even if API call fails
      }
      
      emit(ActiveSessionInProgress(
        ruckId: currentState.ruckId,
        locationPoints: currentState.locationPoints,
        elapsed: currentState.elapsed,
        distance: currentState.distance,
        elevationGain: currentState.elevationGain,
        elevationLoss: currentState.elevationLoss,
        caloriesBurned: currentState.caloriesBurned,
        pace: currentState.pace,
        userWeightKg: currentState.userWeightKg,
        ruckWeightKg: currentState.ruckWeightKg,
      ));
    }
  }
  
  Future<void> _onSessionCompleted(
    SessionCompleted event, 
    Emitter<ActiveSessionState> emit
  ) async {
    if (state is ActiveSessionInProgress || state is ActiveSessionPaused) {
      final currentState = state as ActiveSessionInProgress;
      
      // Stop tracking
      _stopwatch.stop();
      _locationSubscription?.cancel();
      _timer?.cancel();
      
      try {
        // Complete session on backend
        await _apiClient.post(
          '/rucks/${currentState.ruckId}/complete',
          {
            'notes': event.notes,
            'rating': event.rating,
          }
        );
        debugPrint('Successfully completed session via API');
      } catch (e) {
        debugPrint('Failed to complete session via API: $e');
        // Continue anyway to allow user to return to home screen
      }
      
      emit(ActiveSessionCompleted(
        ruckId: currentState.ruckId,
        elapsed: currentState.elapsed,
        distance: currentState.distance,
        elevationGain: currentState.elevationGain,
        elevationLoss: currentState.elevationLoss,
        caloriesBurned: currentState.caloriesBurned,
        ruckWeightKg: currentState.ruckWeightKg,
        completedAt: DateTime.now(),
      ));
    }
  }
  
  void _startLocationTracking() {
    _locationSubscription = _locationService.startLocationTracking().listen(
      _handleLocationUpdate,
      onError: (error) {
        print('Location error: $error');
      }
    );
  }
  
  void _handleLocationUpdate(LocationPoint locationPoint) {
    if (state is! ActiveSessionInProgress) {
      _locationSubscription?.cancel();
      debugPrint('Ignoring location update after session completion');
      return;
    }
   
    // Add a small delay for the first location update to ensure the session is properly started
    // Only add this delay if we haven't yet received a location update
    if (state is ActiveSessionInProgress) {
      final currentState = state as ActiveSessionInProgress;
      if (currentState.locationPoints.isEmpty && !_isSessionStarted) {
        debugPrint('Delaying first location update to ensure session is started properly...');
        Future.delayed(const Duration(seconds: 2), () {
          // Check again after delay if session is started
          if (_isSessionStarted) {
            add(LocationUpdated(locationPoint));
          } else {
            debugPrint('Still waiting for session to start, may need to restart the session');
          }
        });
        return;
      }
    }
   
    add(LocationUpdated(locationPoint));
  }
  
  /// Calculate the distance between two points on Earth using the Haversine formula
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // Radius of the Earth in meters
    
    // Convert latitude and longitude from degrees to radians
    final double latRad1 = lat1 * (pi / 180);
    final double lonRad1 = lon1 * (pi / 180);
    final double latRad2 = lat2 * (pi / 180);
    final double lonRad2 = lon2 * (pi / 180);
    
    // Difference in coordinates
    final double dLat = latRad2 - latRad1;
    final double dLon = lonRad2 - lonRad1;
    
    // Haversine formula
    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(latRad1) * cos(latRad2) *
        sin(dLon / 2) * sin(dLon / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    final double distance = earthRadius * c;
    
    return distance;
  }
  
  Future<void> _sendLocationUpdateToApi(
    LocationPoint point, 
    String ruckId,
    {double? elevationGain, double? elevationLoss}
  ) async {
    // Only send updates if session is confirmed started
    if (!_isSessionStarted) {
      debugPrint('Skipping API location update: Session start not confirmed.');
      return;
    }
    if (ruckId.trim().isEmpty) {
      debugPrint('Warning: Empty ruckId provided, skipping API location update.');
      return;
    }
    // Check if we're in a valid session state before sending updates
    if (state is! ActiveSessionInProgress) {
      debugPrint('Skipping API location update: Session not in progress state.');
      return;
    }
    try {
      await _apiClient.post(
        '/rucks/$ruckId/location',  
        {
          'latitude': point.latitude,
          'longitude': point.longitude,
          'elevation_meters': point.elevation,
          'timestamp': point.timestamp.toIso8601String(),
          'accuracy_meters': point.accuracy,
          if (elevationGain != null) 'elevation_gain_meters': elevationGain,
          if (elevationLoss != null) 'elevation_loss_meters': elevationLoss,
        },
      );
      debugPrint('Successfully sent location update to /rucks/$ruckId/location');
    } catch (e) {
      debugPrint('Failed to send location update: $e');
    }
  }
} 