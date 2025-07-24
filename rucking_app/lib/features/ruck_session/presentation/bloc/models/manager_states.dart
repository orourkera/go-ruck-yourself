import 'package:equatable/equatable.dart';
import 'package:geolocator/geolocator.dart';
import '../../../domain/models/ruck_photo.dart';
import '../../../domain/models/ruck_session.dart';
import '../../../domain/models/terrain_type.dart';

/// Base class for all manager-specific states
abstract class SessionManagerState extends Equatable {
  const SessionManagerState();
}

/// State for SessionLifecycleManager
class SessionLifecycleState extends SessionManagerState {
  final bool isActive;
  final String? sessionId;
  final DateTime? startTime;
  final Duration duration;
  final Duration totalPausedDuration;
  final DateTime? pausedAt;
  final double ruckWeightKg;
  final double userWeightKg;
  final String? errorMessage;
  final bool isSaving;
  final bool isLoading;
  final RuckSession? currentSession;
  final bool isRecovered;
  final double? totalDistanceKm;
  final double? elevationGain;
  final double? elevationLoss;
  final double? caloriesBurned;

  const SessionLifecycleState({
    this.isActive = false,
    this.sessionId,
    this.startTime,
    this.duration = Duration.zero,
    this.totalPausedDuration = Duration.zero,
    this.pausedAt,
    this.ruckWeightKg = 0.0,
    this.userWeightKg = 70.0,
    this.errorMessage,
    this.isSaving = false,
    this.isLoading = false,
    this.currentSession,
    this.isRecovered = false,
    this.totalDistanceKm,
    this.elevationGain,
    this.elevationLoss,
    this.caloriesBurned,
  });

  SessionLifecycleState copyWith({
    bool? isActive,
    String? sessionId,
    DateTime? startTime,
    Duration? duration,
    Duration? totalPausedDuration,
    DateTime? pausedAt,
    double? ruckWeightKg,
    double? userWeightKg,
    String? errorMessage,
    bool? isSaving,
    bool? isLoading,
    RuckSession? currentSession,
    bool? isRecovered,
    double? totalDistanceKm,
    double? elevationGain,
    double? elevationLoss,
    double? caloriesBurned,
  }) {
    return SessionLifecycleState(
      isActive: isActive ?? this.isActive,
      sessionId: sessionId ?? this.sessionId,
      startTime: startTime ?? this.startTime,
      duration: duration ?? this.duration,
      totalPausedDuration: totalPausedDuration ?? this.totalPausedDuration,
      pausedAt: pausedAt,
      ruckWeightKg: ruckWeightKg ?? this.ruckWeightKg,
      userWeightKg: userWeightKg ?? this.userWeightKg,
      errorMessage: errorMessage,
      isSaving: isSaving ?? this.isSaving,
      isLoading: isLoading ?? this.isLoading,
      currentSession: currentSession ?? this.currentSession,
      isRecovered: isRecovered ?? this.isRecovered,
      totalDistanceKm: totalDistanceKm ?? this.totalDistanceKm,
      elevationGain: elevationGain ?? this.elevationGain,
      elevationLoss: elevationLoss ?? this.elevationLoss,
      caloriesBurned: caloriesBurned ?? this.caloriesBurned,
    );
  }

  @override
  List<Object?> get props => [
        isActive,
        sessionId,
        startTime,
        duration,
        totalPausedDuration,
        pausedAt,
        ruckWeightKg,
        userWeightKg,
        errorMessage,
        isSaving,
        isLoading,
        currentSession,
        isRecovered,
        totalDistanceKm,
        elevationGain,
        elevationLoss,
        caloriesBurned,
      ];
}

/// State for LocationTrackingManager
class LocationTrackingState extends SessionManagerState {
  final List<Position> locations;
  final Position? currentPosition;
  final double totalDistance;
  final double currentPace;
  final double averagePace;
  final double currentSpeed;
  final double altitude;
  final bool isTracking;
  final bool isGpsReady;
  final double elevationGain;
  final double elevationLoss;
  final String? errorMessage;

  const LocationTrackingState({
    this.locations = const [],
    this.currentPosition,
    this.totalDistance = 0.0,
    this.currentPace = 0.0,
    this.averagePace = 0.0,
    this.currentSpeed = 0.0,
    this.altitude = 0.0,
    this.isTracking = false,
    this.isGpsReady = false,
    this.elevationGain = 0.0,
    this.elevationLoss = 0.0,
    this.errorMessage,
  });

  LocationTrackingState copyWith({
    List<Position>? locations,
    Position? currentPosition,
    double? totalDistance,
    double? currentPace,
    double? averagePace,
    double? currentSpeed,
    double? altitude,
    bool? isTracking,
    bool? isGpsReady,
    double? elevationGain,
    double? elevationLoss,
    String? errorMessage,
  }) {
    return LocationTrackingState(
      locations: locations ?? this.locations,
      currentPosition: currentPosition ?? this.currentPosition,
      totalDistance: totalDistance ?? this.totalDistance,
      currentPace: currentPace ?? this.currentPace,
      averagePace: averagePace ?? this.averagePace,
      currentSpeed: currentSpeed ?? this.currentSpeed,
      altitude: altitude ?? this.altitude,
      isTracking: isTracking ?? this.isTracking,
      isGpsReady: isGpsReady ?? this.isGpsReady,
      elevationGain: elevationGain ?? this.elevationGain,
      elevationLoss: elevationLoss ?? this.elevationLoss,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        locations,
        currentPosition,
        totalDistance,
        currentPace,
        averagePace,
        currentSpeed,
        altitude,
        isTracking,
        isGpsReady,
        elevationGain,
        elevationLoss,
        errorMessage,
      ];
}

/// State for HeartRateManager
class HeartRateState extends SessionManagerState {
  final List<int> heartRateSamples;
  final int? currentHeartRate;
  final double averageHeartRate;
  final int maxHeartRate;
  final int minHeartRate;
  final bool isConnected;
  final String? deviceName;
  final String? errorMessage;

  const HeartRateState({
    this.heartRateSamples = const [],
    this.currentHeartRate,
    this.averageHeartRate = 0.0,
    this.maxHeartRate = 0,
    this.minHeartRate = 0,
    this.isConnected = false,
    this.deviceName,
    this.errorMessage,
  });

  HeartRateState copyWith({
    List<int>? heartRateSamples,
    int? currentHeartRate,
    double? averageHeartRate,
    int? maxHeartRate,
    int? minHeartRate,
    bool? isConnected,
    String? deviceName,
    String? errorMessage,
  }) {
    return HeartRateState(
      heartRateSamples: heartRateSamples ?? this.heartRateSamples,
      currentHeartRate: currentHeartRate ?? this.currentHeartRate,
      averageHeartRate: averageHeartRate ?? this.averageHeartRate,
      maxHeartRate: maxHeartRate ?? this.maxHeartRate,
      minHeartRate: minHeartRate ?? this.minHeartRate,
      isConnected: isConnected ?? this.isConnected,
      deviceName: deviceName ?? this.deviceName,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        heartRateSamples,
        currentHeartRate,
        averageHeartRate,
        maxHeartRate,
        minHeartRate,
        isConnected,
        deviceName,
        errorMessage,
      ];
}

/// State for PhotoManager
class PhotoState extends SessionManagerState {
  final List<RuckPhoto> photos;
  final bool isLoading;
  final String? errorMessage;

  const PhotoState({
    this.photos = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  PhotoState copyWith({
    List<RuckPhoto>? photos,
    bool? isLoading,
    String? errorMessage,
  }) {
    return PhotoState(
      photos: photos ?? this.photos,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [photos, isLoading, errorMessage];
}

/// State for UploadManager
class UploadState extends SessionManagerState {
  final bool isUploading;
  final int pendingLocationPoints;
  final int pendingHeartRateSamples;
  final DateTime? lastUploadTime;
  final String? errorMessage;

  const UploadState({
    this.isUploading = false,
    this.pendingLocationPoints = 0,
    this.pendingHeartRateSamples = 0,
    this.lastUploadTime,
    this.errorMessage,
  });

  UploadState copyWith({
    bool? isUploading,
    int? pendingLocationPoints,
    int? pendingHeartRateSamples,
    DateTime? lastUploadTime,
    String? errorMessage,
  }) {
    return UploadState(
      isUploading: isUploading ?? this.isUploading,
      pendingLocationPoints: pendingLocationPoints ?? this.pendingLocationPoints,
      pendingHeartRateSamples: pendingHeartRateSamples ?? this.pendingHeartRateSamples,
      lastUploadTime: lastUploadTime ?? this.lastUploadTime,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        isUploading,
        pendingLocationPoints,
        pendingHeartRateSamples,
        lastUploadTime,
        errorMessage,
      ];
}

/// State for MemoryManager
class MemoryState extends SessionManagerState {
  final bool hasActiveSession;
  final bool isRestoring;
  final DateTime? lastSaveTime;
  final Map<String, dynamic>? restoredData;
  final String? errorMessage;

  const MemoryState({
    this.hasActiveSession = false,
    this.isRestoring = false,
    this.lastSaveTime,
    this.restoredData,
    this.errorMessage,
  });

  MemoryState copyWith({
    bool? hasActiveSession,
    bool? isRestoring,
    DateTime? lastSaveTime,
    Map<String, dynamic>? restoredData,
    String? errorMessage,
  }) {
    return MemoryState(
      hasActiveSession: hasActiveSession ?? this.hasActiveSession,
      isRestoring: isRestoring ?? this.isRestoring,
      lastSaveTime: lastSaveTime ?? this.lastSaveTime,
      restoredData: restoredData ?? this.restoredData,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        hasActiveSession,
        isRestoring,
        lastSaveTime,
        restoredData,
        errorMessage,
      ];
}

/// State for TerrainManager
class TerrainState extends SessionManagerState {
  final TerrainType currentTerrain;
  final Map<TerrainType, double> terrainDistances;
  final bool isAnalyzing;

  const TerrainState({
    this.currentTerrain = TerrainType.road,
    this.terrainDistances = const {},
    this.isAnalyzing = false,
  });

  TerrainState copyWith({
    TerrainType? currentTerrain,
    Map<TerrainType, double>? terrainDistances,
    bool? isAnalyzing,
  }) {
    return TerrainState(
      currentTerrain: currentTerrain ?? this.currentTerrain,
      terrainDistances: terrainDistances ?? this.terrainDistances,
      isAnalyzing: isAnalyzing ?? this.isAnalyzing,
    );
  }

  @override
  List<Object?> get props => [currentTerrain, terrainDistances, isAnalyzing];
}

/// State for SessionPersistenceManager
class SessionPersistenceState extends SessionManagerState {
  final bool hasOfflineData;
  final int offlineSessionCount;
  final DateTime? lastSyncTime;
  final bool isSyncing;

  const SessionPersistenceState({
    this.hasOfflineData = false,
    this.offlineSessionCount = 0,
    this.lastSyncTime,
    this.isSyncing = false,
  });

  SessionPersistenceState copyWith({
    bool? hasOfflineData,
    int? offlineSessionCount,
    DateTime? lastSyncTime,
    bool? isSyncing,
  }) {
    return SessionPersistenceState(
      hasOfflineData: hasOfflineData ?? this.hasOfflineData,
      offlineSessionCount: offlineSessionCount ?? this.offlineSessionCount,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      isSyncing: isSyncing ?? this.isSyncing,
    );
  }

  @override
  List<Object?> get props => [
        hasOfflineData,
        offlineSessionCount,
        lastSyncTime,
        isSyncing,
      ];
}

/// State for diagnostics and performance monitoring
class DiagnosticsState extends SessionManagerState {
  final bool isActive;
  final String? sessionId;
  final DateTime? startTime;
  final DateTime? lastReportTime;
  final double memoryUsageMb;
  final int locationUpdatesCount;
  final int heartRateUpdatesCount;
  final double locationUpdatesPerMinute;
  final double heartRateUpdatesPerMinute;
  final double apiFailureRate;
  final double avgApiLatency;
  final double worstGpsAccuracy;
  final int gpsAccuracyWarnings;
  final int pauseCount;
  final int backgroundTransitions;
  final int foregroundTransitions;
  final String? errorMessage;

  const DiagnosticsState({
    this.isActive = false,
    this.sessionId,
    this.startTime,
    this.lastReportTime,
    this.memoryUsageMb = 0.0,
    this.locationUpdatesCount = 0,
    this.heartRateUpdatesCount = 0,
    this.locationUpdatesPerMinute = 0.0,
    this.heartRateUpdatesPerMinute = 0.0,
    this.apiFailureRate = 0.0,
    this.avgApiLatency = 0.0,
    this.worstGpsAccuracy = 0.0,
    this.gpsAccuracyWarnings = 0,
    this.pauseCount = 0,
    this.backgroundTransitions = 0,
    this.foregroundTransitions = 0,
    this.errorMessage,
  });

  DiagnosticsState copyWith({
    bool? isActive,
    String? sessionId,
    DateTime? startTime,
    DateTime? lastReportTime,
    double? memoryUsageMb,
    int? locationUpdatesCount,
    int? heartRateUpdatesCount,
    double? locationUpdatesPerMinute,
    double? heartRateUpdatesPerMinute,
    double? apiFailureRate,
    double? avgApiLatency,
    double? worstGpsAccuracy,
    int? gpsAccuracyWarnings,
    int? pauseCount,
    int? backgroundTransitions,
    int? foregroundTransitions,
    String? errorMessage,
  }) {
    return DiagnosticsState(
      isActive: isActive ?? this.isActive,
      sessionId: sessionId ?? this.sessionId,
      startTime: startTime ?? this.startTime,
      lastReportTime: lastReportTime ?? this.lastReportTime,
      memoryUsageMb: memoryUsageMb ?? this.memoryUsageMb,
      locationUpdatesCount: locationUpdatesCount ?? this.locationUpdatesCount,
      heartRateUpdatesCount: heartRateUpdatesCount ?? this.heartRateUpdatesCount,
      locationUpdatesPerMinute: locationUpdatesPerMinute ?? this.locationUpdatesPerMinute,
      heartRateUpdatesPerMinute: heartRateUpdatesPerMinute ?? this.heartRateUpdatesPerMinute,
      apiFailureRate: apiFailureRate ?? this.apiFailureRate,
      avgApiLatency: avgApiLatency ?? this.avgApiLatency,
      worstGpsAccuracy: worstGpsAccuracy ?? this.worstGpsAccuracy,
      gpsAccuracyWarnings: gpsAccuracyWarnings ?? this.gpsAccuracyWarnings,
      pauseCount: pauseCount ?? this.pauseCount,
      backgroundTransitions: backgroundTransitions ?? this.backgroundTransitions,
      foregroundTransitions: foregroundTransitions ?? this.foregroundTransitions,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        isActive,
        sessionId,
        startTime,
        lastReportTime,
        memoryUsageMb,
        locationUpdatesCount,
        heartRateUpdatesCount,
        locationUpdatesPerMinute,
        heartRateUpdatesPerMinute,
        apiFailureRate,
        avgApiLatency,
        worstGpsAccuracy,
        gpsAccuracyWarnings,
        pauseCount,
        backgroundTransitions,
        foregroundTransitions,
        errorMessage,
      ];
}

/// Location tracking modes for adaptive behavior
enum LocationTrackingMode {
  highAccuracy,
  balanced,
  powerSave,
  emergency,
}

/// Memory pressure levels
enum MemoryPressureLevel {
  normal,
  low,
  moderate,
  high,
  critical,
}

/// State for memory pressure management
class MemoryPressureState extends SessionManagerState {
  final bool isActive;
  final String? sessionId;
  final double memoryUsageMb;
  final MemoryPressureLevel pressureLevel;
  final DateTime? lastPressureDetected;
  final DateTime? lastCheckTime;
  final LocationTrackingMode? currentLocationMode;
  final DateTime? lastModeChange;
  final bool isAdaptiveUploadActive;
  final Duration? adaptiveUploadInterval;
  final String? errorMessage;

  const MemoryPressureState({
    this.isActive = false,
    this.sessionId,
    this.memoryUsageMb = 0.0,
    this.pressureLevel = MemoryPressureLevel.normal,
    this.lastPressureDetected,
    this.lastCheckTime,
    this.currentLocationMode,
    this.lastModeChange,
    this.isAdaptiveUploadActive = false,
    this.adaptiveUploadInterval,
    this.errorMessage,
  });

  MemoryPressureState copyWith({
    bool? isActive,
    String? sessionId,
    double? memoryUsageMb,
    MemoryPressureLevel? pressureLevel,
    DateTime? lastPressureDetected,
    DateTime? lastCheckTime,
    LocationTrackingMode? currentLocationMode,
    DateTime? lastModeChange,
    bool? isAdaptiveUploadActive,
    Duration? adaptiveUploadInterval,
    String? errorMessage,
  }) {
    return MemoryPressureState(
      isActive: isActive ?? this.isActive,
      sessionId: sessionId ?? this.sessionId,
      memoryUsageMb: memoryUsageMb ?? this.memoryUsageMb,
      pressureLevel: pressureLevel ?? this.pressureLevel,
      lastPressureDetected: lastPressureDetected ?? this.lastPressureDetected,
      lastCheckTime: lastCheckTime ?? this.lastCheckTime,
      currentLocationMode: currentLocationMode ?? this.currentLocationMode,
      lastModeChange: lastModeChange ?? this.lastModeChange,
      isAdaptiveUploadActive: isAdaptiveUploadActive ?? this.isAdaptiveUploadActive,
      adaptiveUploadInterval: adaptiveUploadInterval ?? this.adaptiveUploadInterval,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        isActive,
        sessionId,
        memoryUsageMb,
        pressureLevel,
        lastPressureDetected,
        lastCheckTime,
        currentLocationMode,
        lastModeChange,
        isAdaptiveUploadActive,
        adaptiveUploadInterval,
        errorMessage,
      ];
}
