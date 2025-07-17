import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/features/profile/domain/repositories/profile_repository.dart';
import 'package:rucking_app/features/profile/domain/entities/user_profile.dart';
import 'package:rucking_app/features/profile/domain/entities/user_profile_stats.dart';
import 'package:rucking_app/features/profile/domain/entities/social_user.dart';

class ProfileRepositoryImpl implements ProfileRepository {
  final ApiClient apiClient;
  ProfileRepositoryImpl(this.apiClient);

  @override
  Future<UserProfile> getPublicProfile(String userId) async {
    final response = await apiClient.get('/users/$userId/profile');
    final wrapper = response as Map<String, dynamic>;
    final data = wrapper['data'] ?? wrapper; // API may wrap payload in a 'data' field
    return UserProfile.fromJson(data['user'] as Map<String, dynamic>);
  }

  @override
  Future<UserProfileStats> getProfileStats(String userId) async {
    final response = await apiClient.get('/users/$userId/profile');
    final wrapper = response as Map<String, dynamic>;
    final data = wrapper['data'] ?? wrapper;
    return UserProfileStats.fromJson(data['stats'] as Map<String, dynamic>);
  }

  @override
  Future<List<SocialUser>> getFollowers(String userId, {int page = 1}) async {
    try {
      final response = await apiClient.get('/users/$userId/followers?page=$page');
      print('Followers API response: $response');
      final followers = response['followers'] as List?;
      if (followers == null) {
        print('Followers is null, returning empty list');
        return [];
      }
      print('Followers data: $followers');
      return followers.map((e) {
        print('Processing follower: $e');
        return SocialUser.fromJson(e as Map<String, dynamic>);
      }).toList();
    } catch (e) {
      print('Error in getFollowers: $e');
      rethrow;
    }
  }

  @override
  Future<List<SocialUser>> getFollowing(String userId, {int page = 1}) async {
    try {
      final response = await apiClient.get('/users/$userId/following?page=$page');
      print('Following API response: $response');
      final following = response['following'] as List?;
      if (following == null) {
        print('Following is null, returning empty list');
        return [];
      }
      print('Following data: $following');
      return following.map((e) {
        print('Processing following: $e');
        return SocialUser.fromJson(e as Map<String, dynamic>);
      }).toList();
    } catch (e) {
      print('Error in getFollowing: $e');
      rethrow;
    }
  }

  @override
  Future<bool> followUser(String userId) async {
    final response = await apiClient.post('/users/$userId/follow', {});
    return response['success'] ?? false;
  }

  @override
  Future<bool> unfollowUser(String userId) async {
    final response = await apiClient.delete('/users/$userId/follow');
    return response['success'] ?? false;
  }

  @override
  Future<List<dynamic>> getRecentRucks(String userId) async {
    final response = await apiClient.get('/users/$userId/profile');
    final wrapper = response as Map<String, dynamic>;
    final data = wrapper['data'] ?? wrapper;
    return (data['recentRucks'] as List?) ?? [];
  }

  @override
  Future<List<dynamic>> getUserClubs(String userId) async {
    final response = await apiClient.get('/users/$userId/profile');
    final wrapper = response as Map<String, dynamic>;
    final data = wrapper['data'] ?? wrapper;
    return (data['clubs'] as List?) ?? [];
  }
} 