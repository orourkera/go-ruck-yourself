import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// User model representing a user of the app
class User extends Equatable {
  /// User's unique identifier
  final String userId;
  
  /// User's email address
  final String email;
  
  /// User's name
  final String name;
  
  /// User's display name
  final String displayName;
  
  /// User's weight in kilograms
  final double? weightKg;
  
  /// User's height in centimeters
  final double? heightCm;
  
  /// User's date of birth in ISO 8601 format
  final String? dateOfBirth;
  
  /// User's account creation date
  final String? createdAt;
  
  /// Whether the user prefers metric units
  final bool preferMetric;
  
  /// User stats information
  final UserStats? stats;
  
  /// Creates a new user instance
  const User({
    required this.userId,
    required this.email,
    this.name = '',
    this.displayName = '',
    this.weightKg,
    this.heightCm,
    this.dateOfBirth,
    this.createdAt,
    this.preferMetric = true,
    this.stats,
  });
  
  /// Creates a copy of this user with the given fields replaced with new values
  User copyWith({
    String? userId,
    String? email,
    String? name,
    String? displayName,
    double? weightKg,
    double? heightCm,
    String? dateOfBirth,
    String? createdAt,
    bool? preferMetric,
    UserStats? stats,
  }) {
    return User(
      userId: userId ?? this.userId,
      email: email ?? this.email,
      name: name ?? this.name,
      displayName: displayName ?? this.displayName,
      weightKg: weightKg ?? this.weightKg,
      heightCm: heightCm ?? this.heightCm,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      createdAt: createdAt ?? this.createdAt,
      preferMetric: preferMetric ?? this.preferMetric,
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
    
    // Name: Prioritize 'name' field, fallback to splitting email
    String name = json['name'] as String? ?? '';
    if (name.isEmpty && email.contains('@')) {
        name = email.split('@')[0]; // Basic fallback
    }
    
    // DisplayName: Prioritize 'displayName', fallback to 'name', fallback to basic name
    String displayName = json['displayName'] as String? ?? json['display_name'] as String? ?? name;
    if (displayName.isEmpty) {
         displayName = name; // Ensure it's not empty if name wasn't
    }
    
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
      name: name,
      displayName: displayName,
      // Profile fields might be missing initially
      weightKg: safeParseNum(json['weight_kg'])?.toDouble(),
      heightCm: safeParseNum(json['height_cm'])?.toDouble(),
      dateOfBirth: json['date_of_birth'] as String?,
      createdAt: json['created_at'] as String?,
      preferMetric: json['preferMetric'] as bool? ?? json['"preferMetric"'] as bool? ?? true, // Handle quoted key, default true
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
      'name': name,
      'displayName': displayName,
      'preferMetric': preferMetric,
    };
    if (weightKg != null) data['weight_kg'] = weightKg;
    if (heightCm != null) data['height_cm'] = heightCm;
    if (dateOfBirth != null) data['date_of_birth'] = dateOfBirth;
    if (createdAt != null) data['created_at'] = createdAt;
    if (stats != null) data['stats'] = stats!.toJson();
    return data;
  }
  
  @override
  List<Object?> get props => [
    userId, email, name, displayName, weightKg, heightCm, dateOfBirth, createdAt, preferMetric, stats
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
      totalRucks: json['total_rucks'] != null ? (json['total_rucks'] as num).toInt() : 0,
      totalDistanceKm: json['total_distance_km'] != null ? (json['total_distance_km'] as num).toDouble() : 0.0,
      totalCalories: json['total_calories'] != null ? (json['total_calories'] as num).toInt() : 0,
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