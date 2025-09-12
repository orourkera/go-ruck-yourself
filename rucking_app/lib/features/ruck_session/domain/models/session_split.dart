/// Model representing a split within a ruck session
class SessionSplit {
  final int splitNumber;
  final double splitDistance; // Always 1.0 (represents 1km or 1mi)
  final int splitDurationSeconds;
  final double totalDistance; // Total distance at this split
  final int totalDurationSeconds; // Total duration at this split
  final double caloriesBurned; // Calories burned during this split
  final double elevationGainM; // Elevation gain in meters during this split
  final DateTime timestamp;

  const SessionSplit({
    required this.splitNumber,
    required this.splitDistance,
    required this.splitDurationSeconds,
    required this.totalDistance,
    required this.totalDurationSeconds,
    this.caloriesBurned = 0.0,
    this.elevationGainM = 0.0,
    required this.timestamp,
  });

  /// Create a SessionSplit from a JSON map
  factory SessionSplit.fromJson(Map<String, dynamic> json) {
    return SessionSplit(
      splitNumber: json['splitNumber'] ?? json['split_number'] ?? 0,
      splitDistance: (json['splitDistance'] ??
              json['split_distance_km'] ??
              json['split_distance'] ??
              1.0)
          .toDouble(),
      splitDurationSeconds:
          json['splitDurationSeconds'] ?? json['split_duration_seconds'] ?? 0,
      totalDistance: (json['totalDistance'] ??
              json['total_distance_km'] ??
              json['total_distance'] ??
              0.0)
          .toDouble(),
      totalDurationSeconds:
          json['totalDurationSeconds'] ?? json['total_duration_seconds'] ?? 0,
      caloriesBurned:
          (json['caloriesBurned'] ?? json['calories_burned'] ?? 0.0).toDouble(),
      elevationGainM:
          (json['elevationGainM'] ?? json['elevation_gain_m'] ?? 0.0)
              .toDouble(),
      timestamp:
          json['timestamp'] != null && json['timestamp'].toString().isNotEmpty
              ? DateTime.parse(json['timestamp'].toString())
              : json['split_timestamp'] != null &&
                      json['split_timestamp'].toString().isNotEmpty
                  ? DateTime.parse(json['split_timestamp'].toString())
                  : DateTime.now(),
    );
  }

  /// Convert the SessionSplit to a JSON map
  Map<String, dynamic> toJson() {
    return {
      'split_number': splitNumber,
      'split_distance': splitDistance,
      'split_duration_seconds': splitDurationSeconds,
      'total_distance': totalDistance,
      'total_duration_seconds': totalDurationSeconds,
      'calories_burned': caloriesBurned,
      'elevation_gain_m': elevationGainM,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  /// Get the split pace in minutes per kilometer
  double get paceMinPerKm {
    if (splitDistance <= 0) return 0;
    final splitDurationMinutes = splitDurationSeconds / 60.0;
    return splitDurationMinutes / splitDistance;
  }

  /// Get the split pace as a formatted string (e.g., "5:30")
  String get formattedPace {
    final pace = paceMinPerKm;
    final minutes = pace.floor();
    final seconds = ((pace - minutes) * 60).round();
    return '${minutes}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Get the split duration as a formatted string (e.g., "5:30")
  String get formattedDuration {
    final duration = Duration(seconds: splitDurationSeconds);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  String toString() {
    return 'SessionSplit(splitNumber: $splitNumber, distance: ${splitDistance}km, duration: ${formattedDuration}, pace: ${formattedPace})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SessionSplit &&
        other.splitNumber == splitNumber &&
        other.splitDistance == splitDistance &&
        other.splitDurationSeconds == splitDurationSeconds &&
        other.totalDistance == totalDistance &&
        other.totalDurationSeconds == totalDurationSeconds &&
        other.caloriesBurned == caloriesBurned &&
        other.elevationGainM == elevationGainM &&
        other.timestamp == timestamp;
  }

  @override
  int get hashCode {
    return Object.hash(
      splitNumber,
      splitDistance,
      splitDurationSeconds,
      totalDistance,
      totalDurationSeconds,
      caloriesBurned,
      elevationGainM,
      timestamp,
    );
  }
}
