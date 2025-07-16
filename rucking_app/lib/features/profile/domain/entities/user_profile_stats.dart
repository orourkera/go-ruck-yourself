class UserProfileStats {
  final int totalRucks;
  final double totalDistanceKm;
  final int totalDurationSeconds;
  final double totalElevationGainM;
  final double totalCaloriesBurned;
  final int followersCount;
  final int followingCount;
  final int clubsCount;
  final int duelsWon;
  final int duelsLost;
  final int eventsCompleted;

  UserProfileStats({
    required this.totalRucks,
    required this.totalDistanceKm,
    required this.totalDurationSeconds,
    required this.totalElevationGainM,
    required this.totalCaloriesBurned,
    required this.followersCount,
    required this.followingCount,
    required this.clubsCount,
    required this.duelsWon,
    required this.duelsLost,
    required this.eventsCompleted,
  });

  factory UserProfileStats.empty() => UserProfileStats(
    totalRucks: 0,
    totalDistanceKm: 0.0,
    totalDurationSeconds: 0,
    totalElevationGainM: 0.0,
    totalCaloriesBurned: 0.0,
    followersCount: 0,
    followingCount: 0,
    clubsCount: 0,
    duelsWon: 0,
    duelsLost: 0,
    eventsCompleted: 0,
  );

  factory UserProfileStats.fromJson(Map<String, dynamic> json) => UserProfileStats(
    totalRucks: json['totalRucks'] ?? 0,
    totalDistanceKm: (json['totalDistanceKm'] as num?)?.toDouble() ?? 0.0,
    totalDurationSeconds: json['totalDurationSeconds'] ?? 0,
    totalElevationGainM: (json['totalElevationGainM'] as num?)?.toDouble() ?? 0.0,
    totalCaloriesBurned: (json['totalCaloriesBurned'] as num?)?.toDouble() ?? 0.0,
    followersCount: json['followersCount'] ?? 0,
    followingCount: json['followingCount'] ?? 0,
    clubsCount: json['clubsCount'] ?? 0,
    duelsWon: json['duelsWon'] ?? 0,
    duelsLost: json['duelsLost'] ?? 0,
    eventsCompleted: json['eventsCompleted'] ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'totalRucks': totalRucks,
    'totalDistanceKm': totalDistanceKm,
    'totalDurationSeconds': totalDurationSeconds,
    'totalElevationGainM': totalElevationGainM,
    'totalCaloriesBurned': totalCaloriesBurned,
    'followersCount': followersCount,
    'followingCount': followingCount,
    'clubsCount': clubsCount,
    'duelsWon': duelsWon,
    'duelsLost': duelsLost,
    'eventsCompleted': eventsCompleted,
  };
} 