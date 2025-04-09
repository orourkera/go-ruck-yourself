import 'package:equatable/equatable.dart';

/// User model representing a user of the app
class User extends Equatable {
  /// User's unique identifier
  final String userId;
  
  /// User's email address
  final String email;
  
  /// User's display name
  final String name;
  
  /// User's weight in kilograms
  final double? weightKg;
  
  /// User's height in centimeters
  final double? heightCm;
  
  /// User's date of birth in ISO 8601 format
  final String? dateOfBirth;
  
  /// User's account creation date
  final String? createdAt;
  
  /// User stats information
  final UserStats? stats;
  
  /// Creates a new user instance
  const User({
    required this.userId,
    required this.email,
    required this.name,
    this.weightKg,
    this.heightCm,
    this.dateOfBirth,
    this.createdAt,
    this.stats,
  });
  
  /// Creates a copy of this user with the given fields replaced with new values
  User copyWith({
    String? userId,
    String? email,
    String? name,
    double? weightKg,
    double? heightCm,
    String? dateOfBirth,
    String? createdAt,
    UserStats? stats,
  }) {
    return User(
      userId: userId ?? this.userId,
      email: email ?? this.email,
      name: name ?? this.name,
      weightKg: weightKg ?? this.weightKg,
      heightCm: heightCm ?? this.heightCm,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      createdAt: createdAt ?? this.createdAt,
      stats: stats ?? this.stats,
    );
  }
  
  /// Factory constructor for creating a User from JSON
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      userId: json['user_id'] as String,
      email: json['email'] as String,
      name: json['name'] as String,
      weightKg: json['weight_kg'] != null ? (json['weight_kg'] as num).toDouble() : null,
      heightCm: json['height_cm'] != null ? (json['height_cm'] as num).toDouble() : null,
      dateOfBirth: json['date_of_birth'] as String?,
      createdAt: json['created_at'] as String?,
      stats: json['stats'] != null 
          ? UserStats.fromJson(json['stats'] as Map<String, dynamic>) 
          : null,
    );
  }
  
  /// Convert user to JSON
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> result = {
      'user_id': userId,
      'email': email,
      'name': name,
    };
    
    if (weightKg != null) result['weight_kg'] = weightKg;
    if (heightCm != null) result['height_cm'] = heightCm;
    if (dateOfBirth != null) result['date_of_birth'] = dateOfBirth;
    if (createdAt != null) result['created_at'] = createdAt;
    if (stats != null) result['stats'] = stats!.toJson();
    
    return result;
  }
  
  @override
  List<Object?> get props => [
    userId, email, name, weightKg, heightCm, dateOfBirth, createdAt, stats
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
  
  /// Statistics for the current month
  final MonthlyStats? thisMonth;
  
  /// Creates a new user stats instance
  const UserStats({
    required this.totalRucks,
    required this.totalDistanceKm,
    required this.totalCalories,
    this.thisMonth,
  });
  
  /// Factory constructor for creating UserStats from JSON
  factory UserStats.fromJson(Map<String, dynamic> json) {
    return UserStats(
      totalRucks: json['total_rucks'] as int,
      totalDistanceKm: (json['total_distance_km'] as num).toDouble(),
      totalCalories: json['total_calories'] as int,
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
    };
    
    if (thisMonth != null) result['this_month'] = thisMonth!.toJson();
    
    return result;
  }
  
  @override
  List<Object?> get props => [totalRucks, totalDistanceKm, totalCalories, thisMonth];
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
      rucks: json['rucks'] as int,
      distanceKm: (json['distance_km'] as num).toDouble(),
      calories: json['calories'] as int,
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