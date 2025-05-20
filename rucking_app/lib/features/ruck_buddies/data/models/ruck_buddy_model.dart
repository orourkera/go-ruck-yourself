import 'package:rucking_app/features/ruck_buddies/domain/entities/ruck_buddy.dart';
import 'package:rucking_app/features/ruck_buddies/domain/entities/user_info.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_photo.dart';
import 'dart:convert';

class RuckBuddyModel extends RuckBuddy {
  const RuckBuddyModel({
    required String id,
    required String userId,
    required double ruckWeightKg,
    required int durationSeconds,
    required double distanceKm,
    required int caloriesBurned,
    required double elevationGainM,
    required double elevationLossM,
    DateTime? startedAt,
    DateTime? completedAt,
    required DateTime createdAt,
    int? avgHeartRate,
    required UserInfo user,
    List<dynamic>? locationPoints,
    List<RuckPhoto>? photos,
    int likeCount = 0,
    int commentCount = 0,
    bool isLikedByCurrentUser = false,
  }) : super(
    id: id,
    userId: userId,
    ruckWeightKg: ruckWeightKg,
    durationSeconds: durationSeconds,
    distanceKm: distanceKm,
    caloriesBurned: caloriesBurned,
    elevationGainM: elevationGainM,
    elevationLossM: elevationLossM,
    startedAt: startedAt,
    completedAt: completedAt,
    createdAt: createdAt,
    avgHeartRate: avgHeartRate,
    user: user,
    locationPoints: locationPoints,
    photos: photos,
    likeCount: likeCount,
    commentCount: commentCount,
    isLikedByCurrentUser: isLikedByCurrentUser,
  );

  factory RuckBuddyModel.fromJson(Map<String, dynamic> json) {
    // Add debug logging to understand response structure
    print('Parsing RuckBuddy JSON: ${json.keys.join(', ')}');
    
    // Handle date parsing with better error handling
    DateTime? startedAtDate;
    try {
      if (json['started_at'] != null) {
        startedAtDate = DateTime.parse(json['started_at']);
      }
    } catch (e) {
      print('Error parsing started_at date: $e');
    }
    
    DateTime? completedAtDate;
    try {
      if (json['completed_at'] != null) {
        completedAtDate = DateTime.parse(json['completed_at']);
      }
    } catch (e) {
      print('Error parsing completed_at date: $e');
    }
    
    DateTime createdAtDate;
    try {
      if (json['created_at'] != null) {
        createdAtDate = DateTime.parse(json['created_at']);
      } else if (json['started_at'] != null) {
        createdAtDate = DateTime.parse(json['started_at']);
      } else {
        createdAtDate = DateTime.now();
      }
    } catch (e) {
      print('Error parsing created_at date: $e');
      createdAtDate = DateTime.now();
    }
    
    // The API might return user data directly or nested
    Map<String, dynamic> userData = {};
    if (json.containsKey('users')) {
      userData = json['users'] ?? {};
    } else if (json.containsKey('user')) {
      userData = json['user'] ?? {};
    } else if (json.containsKey('user_id')) {
      // If only user_id exists but no user object
      userData = {
        'id': json['user_id'],
        'username': 'Rucker', // Default
        'avatar_url': null,
      };
    }

    // Handle location points - could be in different formats depending on API
    List<dynamic>? locationPoints;
    if (json['location_points'] != null) {
      locationPoints = json['location_points'] as List<dynamic>;
    } else if (json['route'] != null) {
      locationPoints = json['route'] as List<dynamic>;
    }

    // Parse photos if available - with enhanced handling for more formats
    List<RuckPhoto>? photos;
    if (json['photos'] != null) {
      try {
        print('Photo data type: ${json['photos'].runtimeType}');
        print('Photo data: ${json['photos']}');
        
        if (json['photos'] is List) {
          photos = (json['photos'] as List)
              .where((item) => item != null)
              .map((photoJson) => RuckPhoto.fromJson(photoJson))
              .toList();
          print('Parsed ${photos.length} photos from list');
        } else if (json['photos'] is String) {
          // Sometimes the backend might return JSON serialized string
          try {
            final List<dynamic> photosList = jsonDecode(json['photos'] as String);
            photos = photosList
                .where((item) => item != null)
                .map((photoJson) => RuckPhoto.fromJson(photoJson))
                .toList();
            print('Parsed ${photos.length} photos from JSON string');
          } catch (jsonErr) {
            print('Error decoding photos JSON string: $jsonErr');
            // Try treating this as a comma-separated string of URLs
            if ((json['photos'] as String).contains(',') || (json['photos'] as String).contains('http')) {
              final List<String> urls = (json['photos'] as String).split(',');
              photos = urls.where((url) => url.trim().isNotEmpty).map((url) {
                return RuckPhoto(
                  id: 'generated-${DateTime.now().millisecondsSinceEpoch}-${urls.indexOf(url)}',
                  ruckId: json['id']?.toString() ?? '',
                  userId: json['user_id']?.toString() ?? '',
                  filename: url.split('/').last,
                  url: url.trim(),
                  thumbnailUrl: url.trim(),
                  createdAt: DateTime.now(),
                );
              }).toList();
              print('Created ${photos.length} photos from comma-separated URLs');
            }
          }
        } else if (json['photos'] is Map) {
          // Handle case where it might be a single photo as a Map
          photos = [RuckPhoto.fromJson(json['photos'])];
          print('Parsed a single photo from Map');
        }
      } catch (e) {
        print('Error parsing photos: $e');
        photos = null;
      }
    }

    try {
      return RuckBuddyModel(
        // Use null-aware operators and safe conversions for all fields
        id: json['id']?.toString() ?? '',
        userId: json['user_id']?.toString() ?? '',
        ruckWeightKg: _parseToDouble(json['ruck_weight_kg'] ?? json['weight_kg'] ?? 0),
        durationSeconds: _parseToInt(json['duration_seconds'] ?? json['duration'] ?? 0),
        distanceKm: _parseToDouble(json['distance_km'] ?? json['distance'] ?? 0),
        caloriesBurned: _parseToInt(json['calories_burned'] ?? json['calories'] ?? 0),
        elevationGainM: _parseToDouble(json['elevation_gain_m'] ?? json['elevation_gain'] ?? 0),
        elevationLossM: _parseToDouble(json['elevation_loss_m'] ?? json['elevation_loss'] ?? 0),
        startedAt: startedAtDate,
        completedAt: completedAtDate,
        createdAt: createdAtDate,
        avgHeartRate: _parseToInt(json['avg_heart_rate'] ?? json['heart_rate_avg']),
        user: UserInfo.fromJson({
          'id': userData['id'] ?? json['user_id'] ?? '',
          'username': userData['username'] ?? 'Rucker',
          'avatar_url': userData['avatar_url'] ?? null,
          'gender': userData['gender'] ?? 'male',
        }),
        locationPoints: locationPoints,
        photos: photos,
        likeCount: _parseToInt(json['like_count']),
        commentCount: _parseToInt(json['comment_count']), 
        isLikedByCurrentUser: json['is_liked_by_current_user'] == true,
      );
    } catch (e) {
      print('Error creating RuckBuddyModel: $e');
      // Return a placeholder model rather than failing
      return RuckBuddyModel(
        id: json['id']?.toString() ?? 'error',
        userId: json['user_id']?.toString() ?? 'error',
        ruckWeightKg: 0,
        durationSeconds: 0,
        distanceKm: 0,
        caloriesBurned: 0,
        elevationGainM: 0,
        elevationLossM: 0,
        createdAt: DateTime.now(),
        user: UserInfo(
          id: 'error',
          username: 'Error Loading',
          photoUrl: null,
          gender: 'male',
        ),
      );
    }
  }

  static double _parseToDouble(dynamic value) {
    if (value is int) return value.toDouble();
    if (value is double) return value;
    return 0;
  }

  static int _parseToInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    return 0;
  }
}
