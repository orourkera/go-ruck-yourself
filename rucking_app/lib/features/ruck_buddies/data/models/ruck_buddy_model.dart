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
    bool firstRuck = false,
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
          firstRuck: firstRuck,
        );

  factory RuckBuddyModel.fromJson(Map<String, dynamic> json) {
    DateTime? startedAt;
    try {
      if (json['started_at'] != null) {
        startedAt = DateTime.parse(json['started_at'] as String);
      }
    } catch (e) {
      print('Error parsing started_at date: $e');
    }

    DateTime? completedAt;
    try {
      if (json['completed_at'] != null) {
        completedAt = DateTime.parse(json['completed_at'] as String);
      }
    } catch (e) {
      print('Error parsing completed_at date: $e');
    }

    DateTime? createdAt;
    try {
      if (json['created_at'] != null) {
        createdAt = DateTime.parse(json['created_at'] as String);
      }
    } catch (e) {
      print('Error parsing created_at date: $e');
    }

    List<RuckPhoto> photos = [];
    try {
      if (json['photos'] != null) {
        final photosData = json['photos'];

        if (photosData is List) {
          final photoList = photosData as List;
          if (photoList.isNotEmpty) {
            if (photoList.first is Map) {
              photos = photoList
                  .map((item) =>
                      RuckPhoto.fromJson(item as Map<String, dynamic>))
                  .toList();
            } else if (photoList.first is String) {
              photos = photoList
                  .map((url) => RuckPhoto(
                        id: 'generated-${DateTime.now().millisecondsSinceEpoch}-${photoList.indexOf(url)}',
                        ruckId: json['id']?.toString() ?? '',
                        userId: json['user_id']?.toString() ?? '',
                        filename: url.split('/').last,
                        url: url as String,
                        thumbnailUrl: url as String,
                        createdAt: DateTime.now(),
                      ))
                  .toList();
            } else {
              for (final item in photoList) {
                try {
                  if (item is Map) {
                    photos
                        .add(RuckPhoto.fromJson(item as Map<String, dynamic>));
                  } else if (item is String) {
                    photos.add(RuckPhoto(
                      id: 'generated-${DateTime.now().millisecondsSinceEpoch}-${photoList.indexOf(item)}',
                      ruckId: json['id']?.toString() ?? '',
                      userId: json['user_id']?.toString() ?? '',
                      filename: item.split('/').last,
                      url: item as String,
                      thumbnailUrl: item as String,
                      createdAt: DateTime.now(),
                    ));
                  }
                } catch (itemErr) {
                  print('Error parsing individual photo item: $itemErr');
                }
              }
            }
          }
        } else if (photosData is String) {
          try {
            final decodedPhotos = jsonDecode(photosData);
            if (decodedPhotos is List) {
              photos = decodedPhotos
                  .map((item) =>
                      RuckPhoto.fromJson(item as Map<String, dynamic>))
                  .toList();
            }
          } catch (jsonErr) {
            print('Error decoding photos JSON string: $jsonErr');
            if (photosData.contains(',')) {
              final urlList = photosData
                  .split(',')
                  .map((url) => url.trim())
                  .where((url) => url.isNotEmpty)
                  .toList();
              photos = urlList
                  .map((url) => RuckPhoto(
                        id: 'generated-${DateTime.now().millisecondsSinceEpoch}-${urlList.indexOf(url)}',
                        ruckId: json['id']?.toString() ?? '',
                        userId: json['user_id']?.toString() ?? '',
                        filename: url.split('/').last,
                        url: url as String,
                        thumbnailUrl: url as String,
                        createdAt: DateTime.now(),
                      ))
                  .toList();
            }
          }
        } else if (photosData is Map) {
          photos = [RuckPhoto.fromJson(photosData as Map<String, dynamic>)];
        }
      }
    } catch (e, stackTrace) {
      print('Error parsing photos: $e');
      print('Stack trace: $stackTrace');
    }

    try {
      print(
          ' [WEIGHT_DEBUG] Raw ruck_weight_kg from API: ${json['ruck_weight_kg']}');
      final parsedWeight = _parseToDouble(json['ruck_weight_kg'] ?? 0.0);
      print(' [WEIGHT_DEBUG] Parsed ruckWeightKg: $parsedWeight');
      return RuckBuddyModel(
        id: json['id']?.toString() ?? '',
        userId: json['user_id']?.toString() ?? '',
        ruckWeightKg: parsedWeight,
        durationSeconds:
            _parseToInt(json['duration_seconds'] ?? json['duration'] ?? 0),
        distanceKm:
            _parseToDouble(json['distance_km'] ?? json['distance'] ?? 0),
        caloriesBurned:
            _parseToInt(json['calories_burned'] ?? json['calories'] ?? 0),
        elevationGainM: _parseToDouble(
            json['elevation_gain_m'] ?? json['elevation_gain'] ?? 0),
        elevationLossM: _parseToDouble(
            json['elevation_loss_m'] ?? json['elevation_loss'] ?? 0),
        startedAt: startedAt,
        completedAt: completedAt,
        createdAt: createdAt ?? DateTime.now(),
        avgHeartRate:
            _parseToInt(json['avg_heart_rate'] ?? json['heart_rate_avg']),
        user: UserInfo.fromJson({
          'id': json['user']?['id'] ?? json['user_id'],
          'username': json['user']?['username'] ?? json['username'],
          'avatar_url': json['user']?['avatar_url'] ?? json['avatar_url'],
          'gender': json['user']?['gender'] ?? 'male',
        }),
        locationPoints: json['location_points'] != null
            ? List<dynamic>.from(json['location_points'] as List)
            : [],
        photos: photos,
        likeCount: _parseToInt(json['like_count']),
        commentCount: _parseToInt(json['comment_count']),
        isLikedByCurrentUser: json['is_liked_by_current_user'] == true,
        firstRuck: (json['first_ruck'] == true) || (json['firstRuck'] == true),
      );
    } catch (e) {
      print('Error creating RuckBuddyModel: $e');
      rethrow;
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
