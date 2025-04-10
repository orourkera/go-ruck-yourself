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
    required String name,
    required String email,
    required String password,
    required bool preferMetric,
    double? weightKg,
    double? heightCm,
    String? dateOfBirth,
  });
  
  /// Log out the current user
  Future<void> logout();
  
  /// Check if user is authenticated
  Future<bool> isAuthenticated();
  
  /// Get the current authenticated user
  Future<User?> getCurrentUser();
  
  /// Update user profile
  Future<User> updateProfile({
    String? name,
    double? weightKg,
    double? heightCm,
    bool? preferMetric,
  });
} 