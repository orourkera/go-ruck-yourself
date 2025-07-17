import 'package:rucking_app/features/profile/domain/entities/user_profile.dart';
import 'package:rucking_app/features/profile/domain/entities/user_profile_stats.dart';
import 'package:rucking_app/features/profile/domain/entities/social_user.dart';

/// Abstraction layer for retrieving and modifying public profile data.
///
/// NOTE: This file was created to resolve missing import errors during
/// compilation.  Concrete implementations (e.g. networking / caching) should
/// live under `data/repositories/` and implement this interface.
abstract class ProfileRepository {
  /// Fetch a user's public profile (regardless of whether the requester is
  /// following them). Must respect the user's privacy settings.
  Future<UserProfile> getPublicProfile(String userId);

  /// Returns aggregate statistics for the given user (distance, elevation,
  /// rucks completed, etc.). May return `null` if the profile is private.
  Future<UserProfileStats?> getProfileStats(String userId);

  /// Returns a paginated list of users who follow the given user.
  ///
  /// [page] starts at 1; page size is implementation-defined (typically 20).
  Future<List<SocialUser>> getFollowers(String userId, {int page = 1});

  /// Returns a paginated list of users that the given user is following.
  Future<List<SocialUser>> getFollowing(String userId, {int page = 1});

  /// Current user follows the target user. Returns `true` if the request
  /// succeeded on the backend.
  Future<bool> followUser(String userId);

  /// Current user unfollows the target user. Returns `true` if the request
  /// succeeded on the backend.
  Future<bool> unfollowUser(String userId);

  /// Returns a list of recent ruck sessions for the given user.
  Future<List<dynamic>> getRecentRucks(String userId);

  /// Returns a list of clubs that the given user belongs to.
  Future<List<dynamic>> getUserClubs(String userId);
}
