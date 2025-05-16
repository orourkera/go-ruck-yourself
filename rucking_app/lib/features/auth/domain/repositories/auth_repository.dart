import 'package:rucking_app/core/models/user.dart';

/// Interface for authentication repository
abstract class AuthRepository {
  /// Login with email and password
  Future<User> login({
    required String email,
    required String password,
  });
  
  /// Register a new user
  Future<User> register({
    required String username, // This is the display name
    required String email,
    required String password,
    required bool preferMetric,
    double? weightKg,
    double? heightCm,
    String? dateOfBirth,
    String? gender,
  });
  
  /// Log out the current user
  Future<void> logout();
  
  /// Check if user is authenticated
  Future<bool> isAuthenticated();
  
  /// Get the current authenticated user
  Future<User?> getCurrentUser();
  
  /// Refresh the authentication token
  Future<String?> refreshToken();
  
  /// Update user profile
  Future<User> updateProfile({
    String? username,
    double? weightKg,
    double? heightCm,
    bool? preferMetric,
    bool? allowRuckSharing,
    String? gender,
  });

  /// Delete the current user's account
  Future<void> deleteAccount({required String userId});
}