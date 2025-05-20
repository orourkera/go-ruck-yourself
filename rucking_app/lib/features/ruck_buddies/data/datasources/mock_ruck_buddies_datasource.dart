import 'dart:math';

import 'package:rucking_app/core/error/exceptions.dart';
import 'package:rucking_app/features/ruck_buddies/data/datasources/ruck_buddies_remote_datasource.dart';
import 'package:rucking_app/features/ruck_buddies/data/models/ruck_buddy_model.dart';
import 'package:rucking_app/features/ruck_buddies/domain/entities/user_info.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_photo.dart';

/// A mock implementation for testing and development
class MockRuckBuddiesDataSource implements RuckBuddiesRemoteDataSource {
  final _random = Random();
  
  // Demo user data
  final List<UserInfo> _users = [
    const UserInfo(id: '1', username: 'RuckStar', photoUrl: null, gender: 'male'),
    const UserInfo(id: '2', username: 'MountainClimber', photoUrl: null, gender: 'male'),
    const UserInfo(id: '3', username: 'TrailBlazer', photoUrl: null, gender: 'female'),
    const UserInfo(id: '4', username: 'RuckWarrior', photoUrl: null, gender: 'male'),
    const UserInfo(id: '5', username: 'FitRucker', photoUrl: null, gender: 'female'),
  ];

  // Sample route coordinates (circular route)
  final List<Map<String, double>> _sampleRoute = List.generate(
    25,
    (i) => {
      'lat': 40.421 + (0.002 * sin(i * (pi / 12.5))),
      'lng': -3.678 + (0.002 * cos(i * (pi / 12.5))),
    },
  );

  // Sample photo URLs
  final List<String> _photoUrls = [
    'https://images.unsplash.com/photo-1551632811-561732d1e306',
    'https://images.unsplash.com/photo-1470071459604-3b5ec3a7fe05',
    'https://images.unsplash.com/photo-1441974231531-c6227db76b6e',
    'https://images.unsplash.com/photo-1469474968028-56623f02e42e',
    'https://images.unsplash.com/photo-1668010456854-31a83b2b9d70',
    'https://images.unsplash.com/photo-1667824734965-6edf5f172bae',
  ];
  
  @override
  Future<List<RuckBuddyModel>> getRuckBuddies({
    required int limit, 
    required int offset, 
    required String filter,
    double? latitude,
    double? longitude
  }) async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 800));
    
    // Fake an empty result if offset is too high (for pagination testing)
    if (offset > 30) {
      return [];
    }
    
    try {
      // Generate mock data
      final List<RuckBuddyModel> results = List.generate(
        limit,
        (index) {
          final int itemIndex = offset + index;
          final DateTime now = DateTime.now();
          final user = _users[itemIndex % _users.length];
          
          // Determine if this ruck has photos (around 60% chance)
          final bool hasPhotos = _random.nextDouble() < 0.6;
          final int photoCount = hasPhotos ? _random.nextInt(3) + 1 : 0;
          final List<RuckPhoto> photos = hasPhotos 
              ? List.generate(
                  photoCount,
                  (i) => RuckPhoto(
                    id: 'photo_${itemIndex}_$i',
                    ruckId: 'ruck_$itemIndex',
                    userId: user.id,
                    filename: 'ruck_photo_${itemIndex}_$i.jpg',
                    url: _photoUrls[(_random.nextInt(_photoUrls.length))],
                    thumbnailUrl: _photoUrls[(_random.nextInt(_photoUrls.length))],
                    createdAt: DateTime.now().subtract(Duration(hours: _random.nextInt(24))),
                  ),
                )
              : [];
          
          // Apply sort rules to make the data interesting
          double distanceKm = 0.0;
          int durationSeconds = 0;
          int caloriesBurned = 0;
          double elevationGainM = 0.0;
          
          switch (filter) {
            case 'distance_desc':
              // Furthest first
              distanceKm = 5.0 + (25.0 - 0.5 * itemIndex);
              durationSeconds = (60 * 60 * distanceKm * (0.8 + _random.nextDouble() * 0.4) / 5.0).round();
              break;
            case 'duration_desc':
              // Longest first
              durationSeconds = 3600 * 2 - (60 * itemIndex);
              distanceKm = 5.0 + (durationSeconds / 3600.0) * 5 * (0.8 + _random.nextDouble() * 0.4);
              break;
            case 'calories_desc':
              // Most calories first
              caloriesBurned = 800 - (20 * itemIndex);
              distanceKm = 3.0 + (_random.nextDouble() * 7.0);
              durationSeconds = (60 * 60 * distanceKm * (0.8 + _random.nextDouble() * 0.4) / 5.0).round();
              break;
            case 'elevation_gain_desc':
              // Most elevation first
              elevationGainM = 300.0 - (8.0 * itemIndex);
              distanceKm = 3.0 + (_random.nextDouble() * 7.0);
              durationSeconds = (60 * 60 * distanceKm * (0.8 + _random.nextDouble() * 0.4) / 5.0).round();
              break;
            case 'proximity_asc':
            default:
              // Default to random realistic values
              distanceKm = 3.0 + (_random.nextDouble() * 10.0);
              durationSeconds = (60 * 60 * distanceKm * (0.8 + _random.nextDouble() * 0.4) / 5.0).round();
          }
          
          // Ensure realistic values regardless of sort
          caloriesBurned ??= ((distanceKm * 100) * (0.8 + _random.nextDouble() * 0.4)).round();
          elevationGainM ??= (50.0 + _random.nextDouble() * 200.0);
          
          // Create a unique route variation for each ruck
          final routeVariant = _sampleRoute.map((point) {
            return {
              'lat': point['lat']! + (itemIndex * 0.001),
              'lng': point['lng']! + (itemIndex * 0.001),
            };
          }).toList();
          
          // Generate some fake social interaction metrics
          final likeCount = _random.nextInt(15);
          final commentCount = _random.nextInt(7);
          final isLikedByCurrentUser = _random.nextBool();
          
          return RuckBuddyModel(
            id: 'ruck_$itemIndex',
            userId: user.id,
            ruckWeightKg: _getRandomWeight(),
            durationSeconds: durationSeconds,
            distanceKm: distanceKm,
            caloriesBurned: caloriesBurned,
            elevationGainM: elevationGainM,
            elevationLossM: elevationGainM * 0.9,
            startedAt: now.subtract(Duration(days: _random.nextInt(14))),
            completedAt: now.subtract(Duration(days: _random.nextInt(14), hours: _random.nextInt(4))),
            createdAt: now.subtract(Duration(days: _random.nextInt(14), hours: _random.nextInt(24))),
            avgHeartRate: 130 + _random.nextInt(30),
            user: user,
            locationPoints: routeVariant,
            photos: photos,
            likeCount: likeCount,
            commentCount: commentCount,
            isLikedByCurrentUser: isLikedByCurrentUser,
          );
        }
      );
      
      return results;
    } catch (e) {
      throw ServerException(
        message: 'Failed to load mock ruck buddies data: ${e.toString()}',
      );
    }
  }
  
  /// Returns a realistic ruck weight (common values like 10kg, 20lbs, etc.)
  double _getRandomWeight() {
    // Common weight values in kg
    final List<double> commonWeightsKg = [10.0, 15.0, 20.0, 25.0, 30.0, 35.0];
    return commonWeightsKg[_random.nextInt(commonWeightsKg.length)];
  }
}
