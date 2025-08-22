import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// User model representing a user of the app
class User extends Equatable {
  /// User's unique identifier
  final String userId;
  
  /// User's email address
  final String email;
  
  /// User's chosen username
  final String username;
  
  /// User's weight in kilograms
  final double? weightKg;
  
  /// User's height in centimeters
  final double? heightCm;
  
  /// User's date of birth in ISO 8601 format
  final String? dateOfBirth;
  
  /// User's resting heart rate in bpm
  final int? restingHr;
  
  /// User's max heart rate in bpm
  final int? maxHr;
  
  /// Preferred calorie method: 'fusion', 'mechanical', or 'hr'
  final String? calorieMethod;
  
  /// Whether to report active calories only (subtract resting)
  final bool? calorieActiveOnly;
  
  /// User's account creation date
  final String? createdAt;
  
  /// Whether the user prefers metric units
  final bool preferMetric;
  
  /// Whether the user allows their rucks to be shared in the Ruck Buddies feed
  final bool allowRuckSharing;
  
  /// User's gender: 'male', 'female', 'other', or null if unspecified
  final String? gender;
  
  /// User's avatar image URL
  final String? avatarUrl;
  
  /// User's notification preferences
  final bool? notificationClubs;
  final bool? notificationBuddies;
  final bool? notificationEvents;
  final bool? notificationDuels;
  
  /// User stats information
  final UserStats? stats;

  /// Creates a new user instance
  const User({
    required this.userId,
    required this.email,
    required this.username,
    this.weightKg,
    this.heightCm,
    this.dateOfBirth,
    this.restingHr,
    this.maxHr,
    this.calorieMethod,
    this.calorieActiveOnly,
    this.createdAt,
    required this.preferMetric,
    this.allowRuckSharing = true,
    this.gender,
    this.avatarUrl,
    this.notificationClubs,
    this.notificationBuddies,
    this.notificationEvents,
    this.notificationDuels,
    this.stats,
  });
  
  /// Creates a copy of this user with the given fields replaced with new values
  User copyWith({
    String? userId,
    String? email,
    String? username,
    double? weightKg,
    double? heightCm,
    String? dateOfBirth,
    int? restingHr,
    int? maxHr,
    String? calorieMethod,
    bool? calorieActiveOnly,
    String? createdAt,
    bool? preferMetric,
    bool? allowRuckSharing,
    String? gender,
    String? avatarUrl,
    bool? notificationClubs,
    bool? notificationBuddies,
    bool? notificationEvents,
    bool? notificationDuels,
    UserStats? stats,
  }) {
    return User(
      userId: userId ?? this.userId,
      email: email ?? this.email,
      username: username ?? this.username,
      weightKg: weightKg ?? this.weightKg,
      heightCm: heightCm ?? this.heightCm,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      restingHr: restingHr ?? this.restingHr,
      maxHr: maxHr ?? this.maxHr,
      calorieMethod: calorieMethod ?? this.calorieMethod,
      calorieActiveOnly: calorieActiveOnly ?? this.calorieActiveOnly,
      createdAt: createdAt ?? this.createdAt,
      preferMetric: preferMetric ?? this.preferMetric,
      allowRuckSharing: allowRuckSharing ?? this.allowRuckSharing,
      gender: gender ?? this.gender,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      notificationClubs: notificationClubs ?? this.notificationClubs,
      notificationBuddies: notificationBuddies ?? this.notificationBuddies,
      notificationEvents: notificationEvents ?? this.notificationEvents,
      notificationDuels: notificationDuels ?? this.notificationDuels,
      stats: stats ?? this.stats,
    );
  }
  
  /// Factory constructor for creating a User from JSON
  /// Handles data potentially coming from Auth response OR Profile response
  factory User.fromJson(Map<String, dynamic> json) {
    // --- Add Logging ---
    debugPrint('User.fromJson received JSON: $json');
    // --- End Logging ---
    
    String id = "";
    var rawId = json['id'] ?? json['user_id'];
    if (rawId != null) {
      id = rawId.toString();
    }
    
    String email = json['email'] as String? ?? '';
    
    String username = json['username'] as String? ?? '';
    
    // Helper to safely parse numbers (copied from ruck_session)
    num? safeParseNum(dynamic value) {
      if (value == null) return null;
      if (value is num) return value;
      if (value is String) return num.tryParse(value);
      return null;
    }

    final user = User(
      userId: id,
      email: email,
      username: username,
      weightKg: safeParseNum(json['weight_kg'])?.toDouble(),
      heightCm: safeParseNum(json['height_cm'])?.toDouble(),
      dateOfBirth: json['date_of_birth'] as String?,
      restingHr: safeParseNum(json['resting_hr'])?.toInt(),
      maxHr: safeParseNum(json['max_hr'])?.toInt(),
      calorieMethod: json['calorie_method'] as String?,
      calorieActiveOnly: json['calorie_active_only'] as bool?,
      createdAt: json['created_at'] as String?,
      preferMetric: json['prefer_metric'] as bool? ?? false, // Default to imperial/standard for US users
      allowRuckSharing: json['allow_ruck_sharing'] as bool? ?? true,
      gender: json['gender'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      notificationClubs: json['notification_clubs'] as bool?,
      notificationBuddies: json['notification_buddies'] as bool?,
      notificationEvents: json['notification_events'] as bool?,
      notificationDuels: json['notification_duels'] as bool?,
      stats: json['stats'] != null 
          ? UserStats.fromJson(json['stats'] as Map<String, dynamic>) 
          : null,
    );
    
    // --- Add Logging ---
    debugPrint('User.fromJson created User object: ${user.toJson()}');
    // --- End Logging ---
    return user;
  }
  
  /// Convert user to JSON
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      'id': userId,
      'email': email,
      'username': username,
      'preferMetric': preferMetric,
      'allow_ruck_sharing': allowRuckSharing,
    };
    if (weightKg != null) data['weight_kg'] = weightKg;
    if (heightCm != null) data['height_cm'] = heightCm;
    if (dateOfBirth != null) data['date_of_birth'] = dateOfBirth;
    if (restingHr != null) data['resting_hr'] = restingHr;
    if (maxHr != null) data['max_hr'] = maxHr;
    if (calorieMethod != null) data['calorie_method'] = calorieMethod;
    if (calorieActiveOnly != null) data['calorie_active_only'] = calorieActiveOnly;
    if (createdAt != null) data['created_at'] = createdAt;
    if (gender != null) data['gender'] = gender;
    if (avatarUrl != null) data['avatar_url'] = avatarUrl;
    if (notificationClubs != null) data['notification_clubs'] = notificationClubs;
    if (notificationBuddies != null) data['notification_buddies'] = notificationBuddies;
    if (notificationEvents != null) data['notification_events'] = notificationEvents;
    if (notificationDuels != null) data['notification_duels'] = notificationDuels;
    if (stats != null) data['stats'] = stats!.toJson();
    return data;
  }
  
  @override
  List<Object?> get props => [
    userId, email, username, weightKg, heightCm, dateOfBirth, restingHr, maxHr, calorieMethod, calorieActiveOnly, createdAt, preferMetric, allowRuckSharing, gender, avatarUrl, notificationClubs, notificationBuddies, notificationEvents, notificationDuels, stats
  ];
}

/// User statistics model
class UserStats extends Equatable {
  /// Total number of ruck sessions
  final int totalRucks;
  
  /// Total distance in kilometers
  final double totalDistanceKm;
  
  /// Total calories burned
  final int totalCalories;
  
  /// Total power points earned
  final int totalPowerPoints;
  
  /// Statistics for the current month
  final MonthlyStats? thisMonth;
  
  /// Creates a new user stats instance
  const UserStats({
    required this.totalRucks,
    required this.totalDistanceKm,
    required this.totalCalories,
    required this.totalPowerPoints,
    this.thisMonth,
  });
  
  /// Factory constructor for creating UserStats from JSON
  factory UserStats.fromJson(Map<String, dynamic> json) {
    return UserStats(
      totalRucks: json['total_rucks'] != null ? (json['total_rucks'] as num).toInt() : 0,
      totalDistanceKm: json['total_distance_km'] != null ? (json['total_distance_km'] as num).toDouble() : 0.0,
      totalCalories: json['total_calories'] != null ? (json['total_calories'] as num).toInt() : 0,
      totalPowerPoints: json['total_power_points'] != null ? (json['total_power_points'] as num).toInt() : 0,
      thisMonth: json['this_month'] != null 
          ? MonthlyStats.fromJson(json['this_month'] as Map<String, dynamic>) 
          : null,
    );
  }
  
  /// Convert user stats to JSON
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> result = {
      'total_rucks': totalRucks,
      'total_distance_km': totalDistanceKm,
      'total_calories': totalCalories,
      'total_power_points': totalPowerPoints,
    };
    
    if (thisMonth != null) result['this_month'] = thisMonth!.toJson();
    
    return result;
  }
  
  @override
  List<Object?> get props => [totalRucks, totalDistanceKm, totalCalories, totalPowerPoints, thisMonth];
}

/// Monthly statistics model
class MonthlyStats extends Equatable {
  /// Number of ruck sessions this month
  final int rucks;
  
  /// Distance in kilometers this month
  final double distanceKm;
  
  /// Calories burned this month
  final int calories;
  
  /// Creates a new monthly stats instance
  const MonthlyStats({
    required this.rucks,
    required this.distanceKm,
    required this.calories,
  });
  
  /// Factory constructor for creating MonthlyStats from JSON
  factory MonthlyStats.fromJson(Map<String, dynamic> json) {
    return MonthlyStats(
      rucks: json['rucks'] != null ? (json['rucks'] as num).toInt() : 0,
      distanceKm: json['distance_km'] != null ? (json['distance_km'] as num).toDouble() : 0.0,
      calories: json['calories'] != null ? (json['calories'] as num).toInt() : 0,
    );
  }
  
  /// Convert monthly stats to JSON
  Map<String, dynamic> toJson() {
    return {
      'rucks': rucks,
      'distance_km': distanceKm,
      'calories': calories,
    };
  }
  
  @override
  List<Object?> get props => [rucks, distanceKm, calories];
} 