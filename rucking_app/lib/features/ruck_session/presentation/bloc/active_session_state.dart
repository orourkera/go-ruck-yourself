part of 'active_session_bloc.dart';

abstract class ActiveSessionState extends Equatable {
  const ActiveSessionState();
  
  @override
  List<Object?> get props => [];
}

class ActiveSessionInitial extends ActiveSessionState {}

class ActiveSessionLoading extends ActiveSessionState {}

class ActiveSessionRunning extends ActiveSessionState {
  final String sessionId;
  final List<LocationPoint> locationPoints;
  final int elapsedSeconds;
  final double distanceKm;
  final double ruckWeightKg;
  final String? notes;
  final double calories;
  final double elevationGain;
  final double elevationLoss;
  final bool isPaused;
  final double pace;
  
  const ActiveSessionRunning({
    required this.sessionId,
    required this.locationPoints,
    required this.elapsedSeconds,
    required this.distanceKm,
    required this.ruckWeightKg,
    required this.calories,
    required this.elevationGain,
    required this.elevationLoss,
    required this.isPaused,
    required this.pace,
    this.notes,
  });
  
  @override
  List<Object?> get props => [
    sessionId,
    locationPoints,
    elapsedSeconds,
    distanceKm,
    ruckWeightKg,
    notes,
    calories,
    elevationGain,
    elevationLoss,
    isPaused,
    pace,
  ];
  
  ActiveSessionRunning copyWith({
    String? sessionId,
    List<LocationPoint>? locationPoints,
    int? elapsedSeconds,
    double? distanceKm,
    double? ruckWeightKg,
    String? notes,
    double? calories,
    double? elevationGain,
    double? elevationLoss,
    bool? isPaused,
    double? pace,
  }) {
    return ActiveSessionRunning(
      sessionId: sessionId ?? this.sessionId,
      locationPoints: locationPoints ?? this.locationPoints,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      distanceKm: distanceKm ?? this.distanceKm,
      ruckWeightKg: ruckWeightKg ?? this.ruckWeightKg,
      notes: notes ?? this.notes,
      calories: calories ?? this.calories,
      elevationGain: elevationGain ?? this.elevationGain,
      elevationLoss: elevationLoss ?? this.elevationLoss,
      isPaused: isPaused ?? this.isPaused,
      pace: pace ?? this.pace,
    );
  }
}

class ActiveSessionComplete extends ActiveSessionState {
  final RuckSession session;
  
  const ActiveSessionComplete({
    required this.session,
  });
  
  @override
  List<Object?> get props => [session];
}

class ActiveSessionFailure extends ActiveSessionState {
  final String errorMessage;
  
  const ActiveSessionFailure({
    required this.errorMessage,
  });
  
  @override
  List<Object?> get props => [errorMessage];
}
