import 'dart:convert';
import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart'; 
import 'package:logger/logger.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/api/api_exceptions.dart';
import 'package:rucking_app/core/config/app_config.dart';
import 'package:rucking_app/core/models/user.dart';
import 'package:rucking_app/core/services/storage_service.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

/// Interface for authentication operations
abstract class AuthService {
  /// Sign in with email and password
  Future<User> signIn(String email, String password);
  
  /// Register a new user
  Future<User> register({
    required String username, // This is the display name
    required String email,
    required String password,
    bool? preferMetric,
    double? weightKg,
    double? heightCm,
    String? dateOfBirth,
    String? gender,
  });
  
  /// Sign out the current user
  Future<void> signOut();
  
  /// Get the current authenticated user
  Future<User?> getCurrentUser();
  
  /// Check if the user is authenticated
  Future<bool> isAuthenticated();
  
  /// Get the authentication token
  Future<String?> getToken();
  
  /// Refresh the authentication token
  Future<String?> refreshToken();
  
  /// Log the user out
  Future<void> logout();
  
  /// Update the user profile
  Future<User> updateProfile({
    String? username,
    double? weightKg,
    double? heightCm,
    bool? preferMetric,
    bool? allowRuckSharing,
    String? gender,
  });

  /// Delete the current user's account
  /// Requires the user's ID to target the correct backend endpoint.
  Future<void> deleteAccount({required String userId});
}

/// Implementation of AuthService using ApiClient and StorageService
class AuthServiceImpl implements AuthService {
  final ApiClient _apiClient;
  final StorageService _storageService;
  
  AuthServiceImpl(this._apiClient, this._storageService);
  
  @override
  Future<User> signIn(String email, String password) async {
    try {
      final response = await _apiClient.post(
        '/auth/login',
        {
          'email': email,
          'password': password,
        },
      );
      
      final token = response['token'] as String;
      final refreshToken = response['refresh_token'] as String;
      final userData = response['user'] as Map<String, dynamic>;
      final user = User.fromJson(userData);
      
      // Debug logging to confirm token receipt
      print('[AUTH] Login successful. Access token received: ${token.isNotEmpty}');
      print('[AUTH] Refresh token received: ${refreshToken.isNotEmpty}');
      // Store token and user data
      await _storageService.setSecureString(AppConfig.tokenKey, token);
      await _storageService.setSecureString(AppConfig.refreshTokenKey, refreshToken);
      await _storageService.setObject(AppConfig.userProfileKey, user.toJson());
      await _storageService.setString(AppConfig.userIdKey, user.userId);
      // Confirm storage
      print('[AUTH] Tokens and user data stored in secure storage.');
      
      // Set token in API client
      _apiClient.setAuthToken(token);
      
      return user;
    } catch (e) {
      throw _handleAuthError(e);
    }
  }
  
  @override
  Future<User> register({
    required String username, // This is the display name
    required String email,
    required String password,
    bool? preferMetric,
    double? weightKg,
    double? heightCm,
    String? dateOfBirth,
    String? gender,
  }) async {
    try {
      final response = await _apiClient.post(
        '/users/register',
        {
          'username': username, // This is the display name
          'email': email,
          'password': password,
          if (preferMetric != null) 'preferMetric': preferMetric,
          if (weightKg != null) 'weight_kg': weightKg,
          if (heightCm != null) 'height_cm': heightCm,
          if (dateOfBirth != null) 'date_of_birth': dateOfBirth,
          if (gender != null) 'gender': gender,
        },
      );
      
      final token = response['token'] as String?;
      if (token == null || token.isEmpty) {
        throw Exception('Registration failed: No token returned from server.');
      }
      final refreshToken = response['refresh_token'] as String?;
      final userData = response['user'];
      if (userData == null) {
        throw Exception('Registration failed: No user data returned from server.');
      }
      final user = User.fromJson(userData as Map<String, dynamic>);
      
      // Store token and user data
      await _storageService.setSecureString(AppConfig.tokenKey, token);
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await _storageService.setSecureString(AppConfig.refreshTokenKey, refreshToken);
      }
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
    await _storageService.removeSecure(AppConfig.refreshTokenKey);
    await _storageService.remove(AppConfig.userProfileKey);
    await _storageService.remove(AppConfig.userIdKey);
    
    // Confirm token clearing
    print('[AUTH] Tokens and user data cleared from storage during sign out.');
    // Clear token in API client
    _apiClient.clearAuthToken();
  }
  
  @override
  Future<User?> getCurrentUser() async {
    User? userToReturn;
    String? userId = await _storageService.getString(AppConfig.userIdKey);
    
    // If we do not have a stored ID we cannot fetch a profile, just return null (don't log out)
    if (userId == null) {
        return null;
    }

    try {
      // Fetch the latest user profile
      final profileResponse = await _apiClient.get('/users/profile');
      
      final userFromProfile = User.fromJson(profileResponse);
      // Update stored user data (might overwrite email if missing from profile)
      await _storageService.setObject(AppConfig.userProfileKey, userFromProfile.toJson());
      userToReturn = userFromProfile;
      
    } catch (e) {
      if (e is UnauthorizedException) {
        // Attempt a token refresh once before giving up
        try {
          await refreshToken();
          final profileResponse = await _apiClient.get('/users/profile');
          userToReturn = User.fromJson(profileResponse);
          await _storageService.setObject(AppConfig.userProfileKey, userToReturn!.toJson());
        } catch (_) {
          // If still failing, fall back to stored data (do not force sign-out)
        }
      }
      // Fallback to stored user on network error or other issues
      if (userToReturn == null) {
        final storedUserData = await _storageService.getObject(AppConfig.userProfileKey);
        if (storedUserData != null) {
          userToReturn = User.fromJson(storedUserData);
        }
      }
    }
    return userToReturn;
  }
  
  @override
  Future<bool> isAuthenticated() async {
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
        // Token might be expired. Try to refresh it **once** before considering unauthenticated.
        try {
          final newToken = await refreshToken();
          return newToken != null;
        } catch (_) {
          // Ignore and fall through to stored data check below
        }
      }
      
      // For network errors or refresh failures, fall back to cached user data
      final userData = await _storageService.getObject(AppConfig.userProfileKey);
      return userData != null;
    }
  }
  
  @override
  Future<String?> getToken() async {
    return await _storageService.getSecureString(AppConfig.tokenKey);
  }
  
  @override
  Future<String?> refreshToken() async {
    try {
      final storedRefreshToken = await _storageService.getSecureString(AppConfig.refreshTokenKey);
      // Debug logging to check if refresh token exists
      print('[AUTH] Attempting token refresh. Refresh token available: ${storedRefreshToken != null}');
      
      // Log a redacted version of the token for debugging (first few and last few characters only)
      if (storedRefreshToken != null) {
        String redactedToken = storedRefreshToken.length > 10 
            ? '${storedRefreshToken.substring(0, 5)}...${storedRefreshToken.substring(storedRefreshToken.length - 5)}' 
            : '[SHORT TOKEN]';
        print('[AUTH] Refresh token (redacted): $redactedToken');
      }
      
      try {
        // Make the token refresh request
        final response = await _apiClient.post(
          '/auth/refresh',
          {'refresh_token': storedRefreshToken},
        );
        
        if (response == null) {
          print('[AUTH] ERROR: Null response from token refresh');
          await _cleanupInvalidAuthState();
          return null;
        }
        
        final newToken = response['token'] as String;
        final newRefreshToken = response['refresh_token'] as String;

        if (newToken.isEmpty || newRefreshToken.isEmpty) {
          print('[AUTH] ERROR: Received empty tokens from refresh');
          await _cleanupInvalidAuthState();
          throw UnauthorizedException('Received empty tokens from refresh');
        }

        // Store new tokens
        await _storageService.setSecureString(AppConfig.tokenKey, newToken);
        await _storageService.setSecureString(AppConfig.refreshTokenKey, newRefreshToken);
        
        // Set new token in API client
        _apiClient.setAuthToken(newToken);
        
        print('[AUTH] Token refresh successful!');
        return newToken;
      } catch (e) {
        print('[AUTH] Token refresh through API failed: $e');
        
        // All token refresh errors are treated as temporary issues
      // We'll never force a logout due to token problems
      if (e is DioException) {
        if (e.response?.statusCode == 400) {
          // Bad request (expired token) - keep the user logged in
          print('[AUTH] Refresh token issue detected, but maintaining user session');
          await _cleanupInvalidAuthState();
        } else if (e.type == DioExceptionType.connectionError || 
                  e.type == DioExceptionType.connectionTimeout) {
          // Network connectivity issues
          print('[AUTH] Network connectivity issue during token refresh');
        } else {
          // Other API errors
          print('[AUTH] Server error during token refresh: ${e.response?.statusCode}');
        }
      } else {
        // Non-Dio exceptions
        print('[AUTH] Unexpected error during token refresh: $e');
      }
      // Return null instead of throwing - this indicates token refresh failed
      // but we're NOT logging the user out
      return null;
      }
    } catch (e) {
      // Never throw session expiration exceptions
      print('[AUTH] ERROR in refreshToken: $e');
      // Return null instead of throwing - caller should handle this gracefully
      // without forcing user logout
      return null;
    }
  }

  // Helper method to handle invalid tokens without logging out the user
  Future<void> _cleanupInvalidAuthState() async {
    print('[AUTH] Invalid or expired tokens detected, but maintaining user session');
    // Only clear the API client's current token, but DO NOT remove stored tokens
    // This allows auto-recovery when network conditions improve
    _apiClient.clearAuthToken();
    
    // The user profile and other data remains intact
    // Next API call will trigger a new token refresh attempt
    print('[AUTH] User session maintained - will attempt to recover on next API call');
  }
  
  @override
  Future<void> logout() async {
    await signOut();
  }
  
  @override
  Future<User> updateProfile({
    String? username,
    double? weightKg,
    double? heightCm,
    bool? preferMetric,
    bool? allowRuckSharing,
    String? gender,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (username != null) data['username'] = username;
      if (weightKg != null) data['weight_kg'] = weightKg;
      if (heightCm != null) data['height_cm'] = heightCm;
      if (preferMetric != null) data['preferMetric'] = preferMetric;
      if (allowRuckSharing != null) data['allow_ruck_sharing'] = allowRuckSharing;
      if (gender != null) data['gender'] = gender;
      
      // Only send request if there is data to update
      if (data.isEmpty) {
         final currentUser = await getCurrentUser(); // This might hit API again
         if (currentUser != null) return currentUser;
         throw ApiException('No profile data provided for update.');
      }

      final response = await _apiClient.put(
        '/users/profile', // No /api prefix needed here
        data,
      );
      
      // The response from PUT likely contains the updated profile
      final user = User.fromJson(response);
      
      // Update stored user data
      await _storageService.setObject(AppConfig.userProfileKey, user.toJson());
      
      return user;
    } catch (e) {
      throw _handleAuthError(e);
    }
  }
  
  @override
  Future<void> deleteAccount({required String userId}) async {
    try {
      // The ApiClient should already have the token set from previous auth checks/logins.
      // The base URL is handled by ApiClient, we just need the path.
      final String endpoint = '/users/$userId'; 
      AppLogger.info("AuthService: Attempting to delete account via $endpoint");
      
      // Make the DELETE request
      await _apiClient.delete(endpoint);
      
      AppLogger.info("AuthService: Backend account deletion successful for $userId. Signing out locally.");
      
      // If the API call succeeds (doesn't throw), sign out locally
      await signOut();
      
    } on UnauthorizedException catch (e) {
      // If unauthorized, token might be invalid. Sign out anyway.
      AppLogger.warning("AuthService: Unauthorized during delete account for $userId. Signing out. Error: $e");
      await signOut();
      // Rethrow or handle as specific error for the UI/Bloc
      throw e; 
    } catch (e) {
      // Handle other potential API errors or network issues
      AppLogger.error("AuthService: Error during delete account API call for $userId: $e");
      // Rethrow the error so the Bloc/UI layer knows it failed
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