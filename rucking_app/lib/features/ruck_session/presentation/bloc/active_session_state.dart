part of 'active_session_bloc.dart';

abstract class ActiveSessionState extends Equatable {
  const ActiveSessionState();
  
  @override
  List<Object?> get props => [];
}

class ActiveSessionInitial extends ActiveSessionState {}

class ActiveSessionLoading extends ActiveSessionState {}

class ActiveSessionRunning extends ActiveSessionState {
  final List<String>? tags;
  final int? perceivedExertion;
  final double? weightKg;
  final int? plannedDurationMinutes;
  final int? pausedDurationSeconds;
  final int? plannedDuration; // in seconds
  final String sessionId;
  final List<LocationPoint> locationPoints;
  final int elapsedSeconds;
  final double distanceKm;
  final double ruckWeightKg;
  final String? notes;
  final int calories;
  final double elevationGain;
  final double elevationLoss;
  final bool isPaused;
  final double? pace;
  final int? latestHeartRate;
  final String? validationMessage;
  final DateTime originalSessionStartTimeUtc; // Tracks when the session originally started
  final Duration totalPausedDuration;      // Accumulates total time paused
  final DateTime? currentPauseStartTimeUtc; // Tracks when the current pause began
  final List<HeartRateSample> heartRateSamples;

  static const _unset = Object();

  bool get isLongEnough => elapsedSeconds >= 60;

  const ActiveSessionRunning({
    required this.sessionId,
    this.tags,
    this.perceivedExertion,
    this.weightKg,
    this.plannedDurationMinutes,
    this.pausedDurationSeconds,
    this.plannedDuration,
    required this.locationPoints,
    required this.elapsedSeconds,
    required this.distanceKm,
    required this.ruckWeightKg,
    required this.calories,
    required this.elevationGain,
    required this.elevationLoss,
    required this.isPaused,
    required this.pace,
    required this.originalSessionStartTimeUtc,
    required this.totalPausedDuration,
    required this.heartRateSamples,
    this.currentPauseStartTimeUtc,
    this.notes,
    this.latestHeartRate,
    this.validationMessage,
  });
  
  @override
  List<Object?> get props => [
    sessionId,
    tags,
    perceivedExertion,
    weightKg,
    plannedDurationMinutes,
    pausedDurationSeconds,
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
    latestHeartRate,
    validationMessage,
    plannedDuration,
    originalSessionStartTimeUtc,
    totalPausedDuration,
    currentPauseStartTimeUtc,
    heartRateSamples,
  ];
  
  ActiveSessionRunning copyWith({
    String? sessionId,
    List<String>? tags,
    int? perceivedExertion,
    double? weightKg,
    int? plannedDurationMinutes,
    int? pausedDurationSeconds,
    List<LocationPoint>? locationPoints,
    int? elapsedSeconds,
    double? distanceKm,
    double? ruckWeightKg,
    String? notes,
    int? calories,
    double? elevationGain,
    double? elevationLoss,
    bool? isPaused,
    Object? pace = _unset,
    int? latestHeartRate,
    List<HeartRateSample>? heartRateSamples,
    String? validationMessage,
    bool clearValidationMessage = false,
    DateTime? originalSessionStartTimeUtc,
    Duration? totalPausedDuration,
    DateTime? currentPauseStartTimeUtc,
    bool clearCurrentPauseStartTimeUtc = false,
  }) {
    return ActiveSessionRunning(
      sessionId: sessionId ?? this.sessionId,
      tags: tags ?? this.tags,
      perceivedExertion: perceivedExertion ?? this.perceivedExertion,
      weightKg: weightKg ?? this.weightKg,
      plannedDurationMinutes: plannedDurationMinutes ?? this.plannedDurationMinutes,
      pausedDurationSeconds: pausedDurationSeconds ?? this.pausedDurationSeconds,
      locationPoints: locationPoints ?? this.locationPoints,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      distanceKm: distanceKm ?? this.distanceKm,
      ruckWeightKg: ruckWeightKg ?? this.ruckWeightKg,
      notes: notes ?? this.notes,
      calories: calories ?? this.calories,
      elevationGain: elevationGain ?? this.elevationGain,
      elevationLoss: elevationLoss ?? this.elevationLoss,
      isPaused: isPaused ?? this.isPaused,
      pace: identical(pace, _unset) ? this.pace : pace as double?,
      latestHeartRate: latestHeartRate ?? this.latestHeartRate,
      heartRateSamples: heartRateSamples ?? this.heartRateSamples,
      validationMessage: clearValidationMessage ? null : validationMessage ?? this.validationMessage,
      plannedDuration: plannedDuration ?? this.plannedDuration,
      originalSessionStartTimeUtc: originalSessionStartTimeUtc ?? this.originalSessionStartTimeUtc,
      totalPausedDuration: totalPausedDuration ?? this.totalPausedDuration,
      currentPauseStartTimeUtc: clearCurrentPauseStartTimeUtc ? null : currentPauseStartTimeUtc ?? this.currentPauseStartTimeUtc,
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
  final ActiveSessionRunning? sessionDetails;

  const ActiveSessionFailure({
    required this.errorMessage,
    this.sessionDetails,
  });

  @override
  List<Object?> get props => [errorMessage, sessionDetails];
}
