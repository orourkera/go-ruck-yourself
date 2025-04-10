import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/api/api_exceptions.dart';
import 'package:rucking_app/core/config/app_config.dart';
import 'package:rucking_app/core/models/user.dart';
import 'package:rucking_app/core/services/storage_service.dart';
import 'package:flutter/foundation.dart';

/// Interface for authentication operations
abstract class AuthService {
  /// Sign in with email and password
  Future<User> signIn(String email, String password);
  
  /// Register a new user
  Future<User> register({
    required String name,
    required String email,
    required String password,
    double? weightKg,
    double? heightCm,
    String? dateOfBirth,
  });
  
  /// Sign out the current user
  Future<void> signOut();
  
  /// Get the current authenticated user
  Future<User?> getCurrentUser();
  
  /// Check if the user is authenticated
  Future<bool> isAuthenticated();
  
  /// Get the authentication token
  Future<String?> getToken();
  
  /// Update the user profile
  Future<User> updateProfile({
    String? name,
    double? weightKg,
    double? heightCm,
  });
}

/// Implementation of AuthService using ApiClient and StorageService
class AuthServiceImpl implements AuthService {
  final ApiClient _apiClient;
  final StorageService _storageService;
  
  AuthServiceImpl(this._apiClient, this._storageService);
  
  @override
  Future<User> signIn(String email, String password) async {
    debugPrint('AuthService: Attempting signIn for $email');
    try {
      final response = await _apiClient.post(
        '/auth/login',
        {
          'email': email,
          'password': password,
        },
      );
      
      debugPrint('AuthService: Received signIn response: $response');
      
      final token = response['token'] as String;
      final userData = response['user'] as Map<String, dynamic>;
      final user = User.fromJson(userData);
      
      // Store token and user data
      await _storageService.setSecureString(AppConfig.tokenKey, token);
      await _storageService.setObject(AppConfig.userProfileKey, user.toJson());
      await _storageService.setString(AppConfig.userIdKey, user.userId);
      
      // Set token in API client
      _apiClient.setAuthToken(token);
      
      return user;
    } catch (e) {
      throw _handleAuthError(e);
    }
  }
  
  @override
  Future<User> register({
    required String name,
    required String email,
    required String password,
    double? weightKg,
    double? heightCm,
    String? dateOfBirth,
  }) async {
    debugPrint('AuthService: Attempting register for $email');
    try {
      final response = await _apiClient.post(
        '/users/register',
        {
          'name': name,
          'email': email,
          'password': password,
          if (weightKg != null) 'weight_kg': weightKg,
          if (heightCm != null) 'height_cm': heightCm,
          if (dateOfBirth != null) 'date_of_birth': dateOfBirth,
        },
      );
      
      // Process the response directly
      final token = response['token'] as String;
      final userData = response['user'] as Map<String, dynamic>;
      final user = User.fromJson(userData);
      
      // Store token and user data
      await _storageService.setSecureString(AppConfig.tokenKey, token);
      await _storageService.setObject(AppConfig.userProfileKey, user.toJson());
      await _storageService.setString(AppConfig.userIdKey, user.userId);
      
      // Set token in API client
      _apiClient.setAuthToken(token);
      
      return user;
    } catch (e) {
      throw _handleAuthError(e);
    }
  }
  
  @override
  Future<void> signOut() async {
    // Clear token and user data
    await _storageService.removeSecure(AppConfig.tokenKey);
    await _storageService.remove(AppConfig.userProfileKey);
    await _storageService.remove(AppConfig.userIdKey);
    
    // Clear token in API client
    _apiClient.clearAuthToken();
  }
  
  @override
  Future<User?> getCurrentUser() async {
    debugPrint('AuthService: Attempting getCurrentUser');
    try {
      // Check if we have a stored user first (can be stale)
      final storedUserData = await _storageService.getObject(AppConfig.userProfileKey);
      User? storedUser = storedUserData != null ? User.fromJson(storedUserData) : null;
      debugPrint('AuthService: Found stored user data?: ${storedUser != null}');
      
      // Get fresh user data from API
      debugPrint('AuthService: Calling GET /users/profile');
      final response = await _apiClient.get('/users/profile');
      
      // --- Add Logging --- 
      debugPrint('AuthService: Received profile response: $response');
      if (response is! Map<String, dynamic>) {
          debugPrint('AuthService: Error - Profile response is not a Map!');
          // Return stored user or null if fetch failed badly
          return storedUser; 
      }
      // --- End Logging ---
      
      final user = User.fromJson(response);
      debugPrint('AuthService: Parsed fresh User from profile: ${user.toJson()}');
      
      // Update stored user data
      await _storageService.setObject(AppConfig.userProfileKey, user.toJson());
      
      return user;
    } catch (e) {
      debugPrint('AuthService: getCurrentUser error: $e'); // Log error
      if (e is UnauthorizedException) {
        await signOut();
        return null;
      }
      
      // If there's a network error, return the stored user if available
      final storedUserData = await _storageService.getObject(AppConfig.userProfileKey);
      if (storedUserData != null) {
        debugPrint('AuthService: Returning stored user due to network error');
        return User.fromJson(storedUserData);
      }
      
      return null;
    }
  }
  
  @override
  Future<bool> isAuthenticated() async {
    debugPrint('AuthService: Checking isAuthenticated');
    // First check if we have a token stored
    final token = await _storageService.getSecureString(AppConfig.tokenKey);
    if (token == null) {
      return false; // No token means not authenticated
    }
    
    // Set the token for API requests
    _apiClient.setAuthToken(token);
    
    try {
      // Try to get the user profile
      final response = await _apiClient.get('/users/profile');
      return response != null;
    } catch (e) {
      if (e is UnauthorizedException) {
        // Token is invalid or expired
        await signOut();
        return false;
      }
      
      // For network errors, check if we have a stored user
      final userData = await _storageService.getObject(AppConfig.userProfileKey);
      return userData != null;
    }
  }
  
  @override
  Future<String?> getToken() async {
    return await _storageService.getSecureString(AppConfig.tokenKey);
  }
  
  @override
  Future<User> updateProfile({
    String? name,
    double? weightKg,
    double? heightCm,
  }) async {
    debugPrint('AuthService: Attempting updateProfile');
    try {
      final data = <String, dynamic>{};
      if (name != null) data['name'] = name;
      if (weightKg != null) data['weight_kg'] = weightKg;
      if (heightCm != null) data['height_cm'] = heightCm;
      
      final response = await _apiClient.put(
        '/users/profile',
        data,
      );
      
      final user = User.fromJson(response);
      
      // Update stored user data
      await _storageService.setObject(AppConfig.userProfileKey, user.toJson());
      
      return user;
    } catch (e) {
      throw _handleAuthError(e);
    }
  }
  
  /// Convert generic exceptions to auth-specific exceptions
  Exception _handleAuthError(dynamic error) {
    if (error is ApiException) {
      return error;
    }
    
    return ApiException('Authentication error: $error');
  }
} 