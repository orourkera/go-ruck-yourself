import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/location_service.dart';
import 'package:rucking_app/core/models/location_point.dart';
import 'package:rucking_app/core/utils/measurement_utils.dart'; // Import MeasurementUtils
import 'package:rucking_app/core/utils/met_calculator.dart'; // Import MetCalculator
import 'package:rucking_app/features/ruck_session/domain/services/session_validation_service.dart'; // Import SessionValidationService

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

class SessionPaused extends ActiveSessionEvent {}

class SessionResumed extends ActiveSessionEvent {}

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
  
  const ActiveSessionCompleted({
    required this.ruckId,
    required this.elapsed,
    required this.distance,
    required this.elevationGain,
    required this.elevationLoss,
    required this.caloriesBurned,
  });
  
  @override
  List<Object?> get props => [
    ruckId, 
    elapsed, 
    distance, 
    elevationGain, 
    elevationLoss, 
    caloriesBurned
  ];
}

// BLoC
class ActiveSessionBloc extends Bloc<ActiveSessionEvent, ActiveSessionState> {
  final ApiClient _apiClient;
  final LocationService _locationService;
  
  StreamSubscription<LocationPoint>? _locationSubscription;
  Timer? _timer;
  final Stopwatch _stopwatch = Stopwatch();
  
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
      // Notify API that session has started
      await _apiClient.post('/rucks/${event.ruckId}/start', {});
      
      // Start tracking time
      _stopwatch.start();
      _timer = Timer.periodic(
        const Duration(seconds: 1), 
        (_) => add(LocationUpdated(
          LocationPoint(
            latitude: 0, 
            longitude: 0, 
            elevation: 0, 
            timestamp: DateTime.now(),
            accuracy: 0,
          )
        ))
      );
      
      // Start location tracking
      try {
        final hasPermission = await _locationService.hasLocationPermission();
        if (!hasPermission) {
          await _locationService.requestLocationPermission();
        }
      } catch (e) {
        print('Failed to check location permission: $e');
        emit(const ActiveSessionError('Failed to check location permission'));
        return;
      }
      
      _startLocationTracking();
      
      // TODO: Pass these values from ActiveSessionScreen when starting the session
      double? userWeightKg = event.userWeightKg;
      double? ruckWeightKg = event.ruckWeightKg;
      // If you have a way to pass these values, set them here
      // For now, fallback to null (handled elsewhere)

      // Initial state
      emit(ActiveSessionInProgress(
        ruckId: event.ruckId,
        locationPoints: [],
        elapsed: Duration.zero,
        distance: 0,
        elevationGain: 0,
        elevationLoss: 0,
        caloriesBurned: 0,
        pace: 0,
        userWeightKg: userWeightKg,
        ruckWeightKg: ruckWeightKg,
      ));
    } catch (e) {
      emit(ActiveSessionError('Failed to start session: $e'));
    }
  }
  
  Future<void> _onLocationUpdated(
    LocationUpdated event, 
    Emitter<ActiveSessionState> emit
  ) async {
    if (state is ActiveSessionInProgress) {
      final currentState = state as ActiveSessionInProgress;
      
      if (event.locationPoint.latitude == 0 && 
          event.locationPoint.longitude == 0) {
        // This is just a timer tick, update elapsed time
        emit(currentState.copyWith(
          elapsed: _stopwatch.elapsed,
        ));
        return;
      }
      
      // Real location update
      final newPoints = List<LocationPoint>.from(currentState.locationPoints)
        ..add(event.locationPoint);
      
      // Calculate updated stats using MeasurementUtils
      final newDistance = MeasurementUtils.totalDistance(newPoints);
      final newElevationGain = MeasurementUtils.totalElevationGain(newPoints);
      final newElevationLoss = MeasurementUtils.totalElevationLoss(newPoints);
      final newPace = newDistance > 0
          ? (_stopwatch.elapsed.inSeconds / 60) / newDistance
          : 0.0;

      // --- MET-based calorie calculation using actual weights ---
      // Try to get actual user and ruck weights from currentState if available
      double userWeightKg = currentState.userWeightKg ?? 75.0; // fallback
      double ruckWeightKg = currentState.ruckWeightKg ?? 0.0; // fallback

      final double totalWeightKg = userWeightKg + ruckWeightKg;
      final double durationMinutes = _stopwatch.elapsed.inSeconds / 60.0;
      final double distanceMeters = newDistance * 1000;
      final double grade = (distanceMeters > 0)
          ? newElevationGain / distanceMeters * 100
          : 0.0;
      final double speedKmh = (_stopwatch.elapsed.inHours > 0)
          ? newDistance / _stopwatch.elapsed.inHours
          : 0.0;
      final double speedMph = MetCalculator.kmhToMph(speedKmh);
      final double ruckWeightLbs = ruckWeightKg * 2.20462;
      final double met = MetCalculator.calculateRuckingMetByGrade(
        speedMph: speedMph,
        grade: grade,
        ruckWeightLbs: ruckWeightLbs,
      );
      final double newCalories = MetCalculator.calculateCaloriesBurned(
        weightKg: totalWeightKg,
        durationMinutes: durationMinutes,
        metValue: met,
      );

      emit(currentState.copyWith(
        locationPoints: newPoints,
        elapsed: _stopwatch.elapsed,
        distance: newDistance,
        elevationGain: newElevationGain,
        elevationLoss: newElevationLoss,
        caloriesBurned: newCalories,
        pace: newPace,
      ));
      
      // Send update to API periodically, now with elevation gain/loss
      _sendLocationUpdateToApi(
        event.locationPoint, 
        currentState.ruckId,
        elevationGain: newElevationGain,
        elevationLoss: newElevationLoss,
      );
    }
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
        await _apiClient.post('/rucks/${currentState.ruckId}/pause', {});
      } catch (e) {
        print('Failed to pause session: $e');
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
        await _apiClient.post('/rucks/${currentState.ruckId}/resume', {});
      } catch (e) {
        print('Failed to resume session: $e');
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
        // Validate session meets minimum thresholds before completing
        final distanceMeters = currentState.distance * 1000; // Convert km to meters
        final sessionDuration = currentState.elapsed;
        
        // Check if session meets minimum criteria
        if (distanceMeters < SessionValidationService.minSessionDistanceMeters || 
            sessionDuration < SessionValidationService.minSessionDuration) {
          debugPrint('Session too short to save in BLoC: distance ${currentState.distance} km, duration ${sessionDuration.inMinutes} minutes');
          
          // Try to delete the session as it's too short
          try {
            await _apiClient.delete('/rucks/${currentState.ruckId}');
            debugPrint('Successfully deleted short session ${currentState.ruckId} from BLoC');
          } catch (e) {
            debugPrint('Error deleting short session in BLoC: $e');
          }
          
          // Emit error state with appropriate message
          emit(ActiveSessionError('Session too short: minimum ${SessionValidationService.minSessionDistanceMeters}m and ${SessionValidationService.minSessionDuration.inMinutes} minutes required.'));
          return;
        }
        
        // Complete session on backend
        await _apiClient.post('/rucks/${currentState.ruckId}/complete', {
          'notes': event.notes,
          'rating': event.rating,
        });
        
        emit(ActiveSessionCompleted(
          ruckId: currentState.ruckId,
          elapsed: currentState.elapsed,
          distance: currentState.distance,
          elevationGain: currentState.elevationGain,
          elevationLoss: currentState.elevationLoss,
          caloriesBurned: currentState.caloriesBurned,
        ));
      } catch (e) {
        emit(ActiveSessionError('Failed to complete session: $e'));
      }
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
    add(LocationUpdated(locationPoint));
  }
  
  Future<void> _sendLocationUpdateToApi(
    LocationPoint point, 
    String ruckId,
    {double? elevationGain, double? elevationLoss}
  ) async {
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
    } catch (e) {
      print('Failed to send location update: $e');
    }
  }
} 