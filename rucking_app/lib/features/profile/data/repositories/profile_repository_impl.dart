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
    return UserProfile.fromJson(response['user']);
  }

  @override
  Future<UserProfileStats> getProfileStats(String userId) async {
    final response = await apiClient.get('/users/$userId/profile');
    return UserProfileStats.fromJson(response['stats']);
  }

  @override
  Future<List<SocialUser>> getFollowers(String userId, {int page = 1}) async {
    final response = await apiClient.get('/users/$userId/followers?page=$page');
    return (response['followers'] as List).map((e) => SocialUser.fromJson(e)).toList();
  }

  @override
  Future<List<SocialUser>> getFollowing(String userId, {int page = 1}) async {
    final response = await apiClient.get('/users/$userId/following?page=$page');
    return (response['following'] as List).map((e) => SocialUser.fromJson(e)).toList();
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
} 