part of active_session_bloc;

abstract class ActiveSessionState extends Equatable {
  const ActiveSessionState();
  
  @override
  List<Object?> get props => [];
}

class ActiveSessionInitial extends ActiveSessionState {
  final RuckSession? viewedSession; // The session being viewed, if any
  final List<RuckPhoto> photos;
  final PhotoLoadingStatus photosStatus;
  final bool isPhotosLoading;
  final String? photoLoadingError;

  const ActiveSessionInitial({
    this.viewedSession,
    this.photos = const [],
    this.photosStatus = PhotoLoadingStatus.initial,
    this.isPhotosLoading = false,
    this.photoLoadingError,
  });

  @override
  List<Object?> get props => [viewedSession, photos, photosStatus, isPhotosLoading, photoLoadingError];

  ActiveSessionInitial copyWith({
    RuckSession? viewedSession,
    bool clearViewedSession = false, // Allows explicitly setting viewedSession to null
    List<RuckPhoto>? photos,
    PhotoLoadingStatus? photosStatus,
    bool? isPhotosLoading,
    String? photoLoadingError,
    bool clearPhotoLoadingError = false,
  }) {
    return ActiveSessionInitial(
      viewedSession: clearViewedSession ? null : (viewedSession ?? this.viewedSession),
      photos: photos ?? this.photos,
      photosStatus: photosStatus ?? this.photosStatus,
      isPhotosLoading: isPhotosLoading ?? this.isPhotosLoading,
      photoLoadingError: clearPhotoLoadingError ? null : (photoLoadingError ?? this.photoLoadingError),
    );
  }
}

class ActiveSessionLoading extends ActiveSessionState {
  const ActiveSessionLoading();
  
  @override
  List<Object?> get props => [];
}

class ActiveSessionRunning extends ActiveSessionState {
  final List<String>? tags;
  final int? perceivedExertion;
  final double userWeightKg;
  final int? plannedDurationMinutes;
  final int? pausedDurationSeconds;
  final int? plannedDuration; // in seconds
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
  final double? pace;
  final int? latestHeartRate;
  final int? minHeartRate;
  final int? maxHeartRate;
  final String? validationMessage;
  final DateTime originalSessionStartTimeUtc; // Tracks when the session originally started
  final Duration totalPausedDuration;      // Accumulates total time paused
  final DateTime? currentPauseStartTimeUtc; // Tracks when the current pause began
  final List<HeartRateSample> heartRateSamples;
  final bool isGpsReady; // Flag to indicate if GPS has acquired the first point
  final List<RuckPhoto> photos;
  final bool isPhotosLoading;
  final String? photosError;
  final String? errorMessage;
  
  // Photo upload fields
  final bool isUploading;
  final String? uploadError;
  final bool uploadSuccess;
  
  // Photo deletion fields
  final bool isDeleting;
  final String? deleteError;
  
  // Split tracking
  final List<dynamic> splits;
  
  // Terrain tracking
  final List<TerrainSegment> terrainSegments;

  static const _unset = Object();

  bool get isLongEnough => elapsedSeconds >= 60;

  const ActiveSessionRunning({
    required this.sessionId,
    this.tags,
    this.perceivedExertion,
    required this.userWeightKg,
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
    this.photos = const [],
    this.isPhotosLoading = false,
    this.photosError,
    this.errorMessage,
    // Photo upload fields
    this.isUploading = false,
    this.uploadError,
    this.uploadSuccess = false,
    // Photo deletion fields
    this.isDeleting = false,
    this.deleteError,
    this.splits = const [],
    this.terrainSegments = const [], // Add default value
    this.currentPauseStartTimeUtc,
    this.notes,
    this.latestHeartRate,
    this.minHeartRate,
    this.maxHeartRate,
    this.validationMessage,
    this.isGpsReady = false, // Default to false
  });
  
  @override
  List<Object?> get props => [
    sessionId,
    tags,
    perceivedExertion,
    userWeightKg,
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
    minHeartRate,
    maxHeartRate,
    validationMessage,
    plannedDuration,
    originalSessionStartTimeUtc,
    totalPausedDuration,
    currentPauseStartTimeUtc,
    heartRateSamples,
    isGpsReady, // Add to props
    photos,
    isPhotosLoading,
    photosError,
    errorMessage,
    // Photo upload fields
    isUploading,
    uploadError,
    uploadSuccess,
    // Photo deletion fields
    isDeleting,
    deleteError,
    // Split tracking
    splits,
    terrainSegments, // Add to props
  ];
  
  ActiveSessionRunning copyWith({
    String? sessionId,
    List<String>? tags,
    int? perceivedExertion,
    double? userWeightKg,
    int? plannedDurationMinutes,
    int? pausedDurationSeconds,
    List<LocationPoint>? locationPoints,
    int? elapsedSeconds,
    double? distanceKm,
    double? ruckWeightKg,
    String? notes,
    double? calories,
    double? elevationGain,
    double? elevationLoss,
    bool? isPaused,
    Object? pace = _unset,
    int? latestHeartRate,
    int? minHeartRate,
    int? maxHeartRate,
    List<HeartRateSample>? heartRateSamples,
    List<RuckPhoto>? photos,
    bool? isPhotosLoading,
    String? photosError,
    bool clearPhotosError = false,
    String? errorMessage,
    bool clearErrorMessage = false,
    // Photo upload fields
    bool? isUploading,
    String? uploadError,
    bool clearUploadError = false,
    bool? uploadSuccess,
    // Photo deletion fields
    bool? isDeleting,
    String? deleteError,
    bool clearDeleteError = false,
    List<dynamic>? splits,
    List<TerrainSegment>? terrainSegments, // Add to copyWith parameters
    String? validationMessage,
    bool clearValidationMessage = false,
    DateTime? originalSessionStartTimeUtc,
    Duration? totalPausedDuration,
    DateTime? currentPauseStartTimeUtc,
    bool clearCurrentPauseStartTimeUtc = false,
    bool? isGpsReady, // Add to copyWith parameters
  }) {
    return ActiveSessionRunning(
      sessionId: sessionId ?? this.sessionId,
      tags: tags ?? this.tags,
      perceivedExertion: perceivedExertion ?? this.perceivedExertion,
      userWeightKg: userWeightKg ?? this.userWeightKg,
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
      minHeartRate: minHeartRate ?? this.minHeartRate,
      maxHeartRate: maxHeartRate ?? this.maxHeartRate,
      heartRateSamples: heartRateSamples ?? this.heartRateSamples,
      photos: photos ?? this.photos,
      isPhotosLoading: isPhotosLoading ?? this.isPhotosLoading,
      photosError: clearPhotosError ? null : photosError ?? this.photosError,
      errorMessage: clearErrorMessage ? null : errorMessage ?? this.errorMessage,
      // Photo upload fields
      isUploading: isUploading ?? this.isUploading,
      uploadError: clearUploadError ? null : uploadError ?? this.uploadError,
      uploadSuccess: uploadSuccess ?? this.uploadSuccess,
      // Photo deletion fields
      isDeleting: isDeleting ?? this.isDeleting,
      deleteError: clearDeleteError ? null : (deleteError ?? this.deleteError),
      splits: splits ?? this.splits,
      terrainSegments: terrainSegments ?? this.terrainSegments, // Use in copyWith
      validationMessage: clearValidationMessage ? null : (validationMessage ?? this.validationMessage),
      plannedDuration: plannedDuration ?? this.plannedDuration,
      originalSessionStartTimeUtc: originalSessionStartTimeUtc ?? this.originalSessionStartTimeUtc,
      totalPausedDuration: totalPausedDuration ?? this.totalPausedDuration,
      currentPauseStartTimeUtc: clearCurrentPauseStartTimeUtc ? null : currentPauseStartTimeUtc ?? this.currentPauseStartTimeUtc,
      isGpsReady: isGpsReady ?? this.isGpsReady, // Use in copyWith
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

class ActiveSessionCompleted extends ActiveSessionState {
  final String sessionId;
  final double finalDistanceKm;
  final int finalDurationSeconds;
  final int finalCalories;
  final double elevationGain;
  final double elevationLoss;
  final double? averagePace;
  final List<LocationPoint> route;
  final List<HeartRateSample> heartRateSamples;
  final int? averageHeartRate;
  final int? minHeartRate;
  final int? maxHeartRate;
  final List<dynamic> sessionPhotos;
  final List<dynamic> splits;
  final DateTime completedAt;
  final bool isOffline;
  
  const ActiveSessionCompleted({
    required this.sessionId,
    required this.finalDistanceKm,
    required this.finalDurationSeconds,
    required this.finalCalories,
    required this.elevationGain,
    required this.elevationLoss,
    this.averagePace,
    required this.route,
    required this.heartRateSamples,
    this.averageHeartRate,
    this.minHeartRate,
    this.maxHeartRate,
    required this.sessionPhotos,
    required this.splits,
    required this.completedAt,
    this.isOffline = false,
  });
  
  @override
  List<Object?> get props => [
    sessionId,
    finalDistanceKm,
    finalDurationSeconds,
    finalCalories,
    elevationGain,
    elevationLoss,
    averagePace,
    route,
    heartRateSamples,
    averageHeartRate,
    minHeartRate,
    maxHeartRate,
    sessionPhotos,
    splits,
    completedAt,
    isOffline,
  ];
}

class SessionSummaryGenerated extends ActiveSessionState {
  final RuckSession session;
  final List<RuckPhoto> photos;
  final bool isPhotosLoading;
  final String? photosError;
  final String? errorMessage;
  
  const SessionSummaryGenerated({
    required this.session,
    this.photos = const [],
    this.isPhotosLoading = false,
    this.photosError,
    this.errorMessage,
  });
  
  @override
  List<Object?> get props => [session, photos, isPhotosLoading, photosError, errorMessage];
  
  SessionSummaryGenerated copyWith({
    RuckSession? session,
    List<RuckPhoto>? photos,
    bool? isPhotosLoading,
    String? photosError,
    bool clearPhotosError = false,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return SessionSummaryGenerated(
      session: session ?? this.session,
      photos: photos ?? this.photos,
      isPhotosLoading: isPhotosLoading ?? this.isPhotosLoading,
      photosError: clearPhotosError ? null : (photosError ?? this.photosError),
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
    );
  }
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

// States for targeted photo loading for a specific session ID
class SessionPhotosLoadingForId extends ActiveSessionState {
  final String sessionId;

  const SessionPhotosLoadingForId({required this.sessionId});

  @override
  List<Object?> get props => [sessionId];
}

class SessionPhotosLoadedForId extends ActiveSessionState {
  final String sessionId;
  final List<RuckPhoto> photos;

  const SessionPhotosLoadedForId({required this.sessionId, required this.photos});

  @override
  List<Object?> get props => [sessionId, photos];
}

class SessionPhotosErrorForId extends ActiveSessionState {
  final String sessionId;
  final String errorMessage;

  const SessionPhotosErrorForId({required this.sessionId, required this.errorMessage});

  @override
  List<Object?> get props => [sessionId, errorMessage];
}
