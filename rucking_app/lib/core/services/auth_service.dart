import 'dart:async';
import 'dart:convert';
import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart'; 
import 'package:google_sign_in/google_sign_in.dart';
import 'package:logger/logger.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/api/api_exceptions.dart';
import 'package:rucking_app/core/config/app_config.dart';
import 'package:rucking_app/core/models/user.dart';
import 'package:rucking_app/core/services/storage_service.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase, OAuthProvider, AuthResponse, AuthState, AuthChangeEvent;
import 'package:supabase_flutter/supabase_flutter.dart' as supabase show User;

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

  /// Sign in with Google
  Future<User> googleSignIn();
  
  /// Complete Google user registration with profile creation
  Future<User> googleRegister({
    required String email,
    required String displayName,
    required String username,
    required bool preferMetric,
    double? weightKg,
    double? heightCm,
    String? dateOfBirth,
    String? gender,
  });
}

/// Implementation of AuthService using ApiClient and StorageService
class AuthServiceImpl implements AuthService {
  final ApiClient _apiClient;
  final StorageService _storageService;
  late final GoogleSignIn _googleSignIn;

  AuthServiceImpl(this._apiClient, this._storageService) {
    // Initialize Google Sign-In with web client ID
    // This will fallback to web OAuth flow on Android if no Android client is configured
    _googleSignIn = GoogleSignIn(
      scopes: ['email', 'profile'],
    );
  }
  
  @override
  Future<User> signIn(String email, String password) async {
    try {
      AppLogger.info('Attempting login for email: $email');
      
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
      
      // Store token and user data
      AppLogger.info('[AUTH] Storing authentication tokens and user data');
      await _storageService.setSecureString(AppConfig.tokenKey, token);
      await _storageService.setSecureString(AppConfig.refreshTokenKey, refreshToken);
      await _storageService.setObject(AppConfig.userProfileKey, user.toJson());
      await _storageService.setString(AppConfig.userIdKey, user.userId);
      
      // Verify storage worked (Android debugging)
      final storedToken = await _storageService.getSecureString(AppConfig.tokenKey);
      final storedUser = await _storageService.getObject(AppConfig.userProfileKey);
      AppLogger.info('[AUTH] Storage verification - token stored: ${storedToken != null}, user stored: ${storedUser != null}');
      
      // Set token in API client
      _apiClient.setAuthToken(token);
      
      AppLogger.info('Login successful for user: ${user.userId}');
      return user;
    } catch (e) {
      AppLogger.error('Login failed', exception: e);
      throw _handleAuthError(e);
    }
  }

  @override
  Future<User> googleSignIn() async {
    try {
      AppLogger.info('Attempting Google Sign-In');
      
      // Use Google Sign-In to get tokens
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        throw AuthException('Google Sign-In was cancelled', 'GOOGLE_SIGNIN_CANCELLED');
      }
      
      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;
      
      if (idToken == null) {
        throw AuthException('Failed to get Google ID token', 'GOOGLE_TOKEN_ERROR');
      }
      
      AppLogger.info('Google tokens obtained, authenticating with Supabase');
      
      // Authenticate with Supabase using Google tokens
      final response = await Supabase.instance.client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
      
      if (response.user == null) {
        throw AuthException('Supabase authentication failed', 'SUPABASE_AUTH_FAILED');
      }
      
      final supabaseUser = response.user!;
      final session = response.session!;
      AppLogger.info('Supabase Google authentication successful');
      
      // Set the token first so API calls work
      _apiClient.setAuthToken(session.accessToken);
      
      // Check if user profile exists in our user table
      try {
        final profileResponse = await _apiClient.get('/users/profile');
        
        // If we get here, profile exists, convert to our User model
        final user = User.fromJson(profileResponse);
        
        // Store tokens and user data
        await _storageService.setSecureString(AppConfig.tokenKey, session.accessToken);
        await _storageService.setSecureString(AppConfig.refreshTokenKey, session.refreshToken ?? '');
        await _storageService.setObject(AppConfig.userProfileKey, user.toJson());
        await _storageService.setString(AppConfig.userIdKey, user.userId);
        
        AppLogger.info('Existing Google user signed in successfully');
        return user;
        
      } catch (profileError) {
        // Profile doesn't exist, user needs registration
        AppLogger.info('Google user needs to complete registration');
        
        // Extract user info from Supabase auth
        final email = supabaseUser.email ?? '';
        final displayName = supabaseUser.userMetadata?['full_name'] as String? ?? 
                           supabaseUser.userMetadata?['name'] as String? ?? 
                           email.split('@')[0];
        
        throw GoogleUserNeedsRegistrationException(
          'Google user needs to complete registration',
          email: email,
          displayName: displayName,
        );
      }
      
    } catch (e) {
      AppLogger.error('Google sign-in failed', exception: e);
      
      // Re-throw specific exceptions
      if (e is GoogleUserNeedsRegistrationException || e is AuthException) {
        rethrow;
      }
      
      // Generic error handling
      throw AuthException('Google sign-in failed: $e', 'GOOGLE_SIGN_IN_FAILED');
    }
  }
  
  @override
  Future<User> googleRegister({
    required String email,
    required String displayName,
    required String username,
    required bool preferMetric,
    double? weightKg,
    double? heightCm,
    String? dateOfBirth,
    String? gender,
  }) async {
    try {
      // Get current session (should already be authenticated from OAuth flow)
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) {
        throw AuthException('No active Google session found', 'GOOGLE_SESSION_MISSING');
      }

      final supabaseUser = session.user;
      
      // Set the token first so API calls work
      _apiClient.setAuthToken(session.accessToken);
      
      // Create user profile in our backend
      final response = await _apiClient.post('/auth/google-register', {
        'email': email,
        'display_name': displayName,
        'username': username,
        'prefer_metric': preferMetric,
        'weight_kg': weightKg,
        'height_cm': heightCm,
        'date_of_birth': dateOfBirth,
        'gender': gender,
      });
      
      final userData = response['user'] as Map<String, dynamic>;
      final user = User.fromJson(userData);
      
      // Store tokens and user data
      await _storageService.setSecureString(AppConfig.tokenKey, session.accessToken);
      await _storageService.setSecureString(AppConfig.refreshTokenKey, session.refreshToken ?? '');
      await _storageService.setObject(AppConfig.userProfileKey, user.toJson());
      await _storageService.setString(AppConfig.userIdKey, user.userId);
      
      AppLogger.info('Google user registration completed successfully');
      return user;
      
    } catch (e) {
      AppLogger.error('Google registration failed', exception: e);
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
      
      AppLogger.info('Registration successful for user: ${user.userId}');
      return user;
    } catch (e) {
      AppLogger.error('Registration failed', exception: e);
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
    
    // Clear token in API client
    _apiClient.clearAuthToken();
  }
  
  @override
  Future<User?> getCurrentUser() async {
    User? userToReturn;
    
    try {
      // Try to fetch the latest user profile first - if this succeeds, the user is authenticated
      final profileResponse = await _apiClient.get('/users/profile');
      
      final userFromProfile = User.fromJson(profileResponse);
      // Update stored user data 
      await _storageService.setObject(AppConfig.userProfileKey, userFromProfile.toJson());
      // Also store the user ID to avoid this issue in the future
      await _storageService.setString(AppConfig.userIdKey, userFromProfile.userId);
      userToReturn = userFromProfile;
      
    } catch (e) {
      if (e is UnauthorizedException) {
        // Attempt a token refresh once before giving up
        try {
          await refreshToken();
          final profileResponse = await _apiClient.get('/users/profile');
          userToReturn = User.fromJson(profileResponse);
          await _storageService.setObject(AppConfig.userProfileKey, userToReturn!.toJson());
          await _storageService.setString(AppConfig.userIdKey, userToReturn!.userId);
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
    AppLogger.info('[AUTH] Checking authentication - token exists: ${token != null}');
    if (token == null) {
      AppLogger.warning('[AUTH] No token found in secure storage');
      return false; // No token means not authenticated
    }
    
    // Set the token for API requests
    _apiClient.setAuthToken(token);
    AppLogger.info('[AUTH] Token set in API client, attempting profile fetch');
    
    try {
      // Try to get the user profile
      final response = await _apiClient.get('/users/profile');
      AppLogger.info('[AUTH] Profile fetch successful - user is authenticated');
      return response != null;
    } catch (e) {
      AppLogger.warning('[AUTH] Profile fetch failed: $e');
      if (e is UnauthorizedException) {
        // Token might be expired. Try to refresh it **once** before considering unauthenticated.
        AppLogger.info('[AUTH] Token unauthorized, attempting refresh');
        try {
          final newToken = await refreshToken();
          final refreshSuccessful = newToken != null;
          AppLogger.info('[AUTH] Token refresh result: ${refreshSuccessful ? 'success' : 'failed'}');
          return refreshSuccessful;
        } catch (refreshError) {
          AppLogger.warning('[AUTH] Token refresh failed: $refreshError');
          // Ignore and fall through to stored data check below
        }
      }
      
      // For network errors or refresh failures, fall back to cached user data
      AppLogger.info('[AUTH] Falling back to cached user data check');
      final userData = await _storageService.getObject(AppConfig.userProfileKey);
      final hasCachedData = userData != null;
      AppLogger.info('[AUTH] Cached user data exists: $hasCachedData');
      return hasCachedData;
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
      
      try {
        // Make the token refresh request
        final response = await _apiClient.post(
          '/auth/refresh',
          {'refresh_token': storedRefreshToken},
        );
        
        if (response == null) {
          AppLogger.error('Token refresh failed: Null response from server');
          await _cleanupInvalidAuthState();
          return null;
        }
        
        final newToken = response['token'] as String;
        final newRefreshToken = response['refresh_token'] as String;

        if (newToken.isEmpty || newRefreshToken.isEmpty) {
          AppLogger.error('Token refresh failed: Received empty tokens from server');
          await _cleanupInvalidAuthState();
          throw UnauthorizedException('Received empty tokens from refresh');
        }

        // Store new tokens
        await _storageService.setSecureString(AppConfig.tokenKey, newToken);
        await _storageService.setSecureString(AppConfig.refreshTokenKey, newRefreshToken);
        
        // Set new token in API client
        _apiClient.setAuthToken(newToken);
        
        AppLogger.info('Token refresh successful');
        return newToken;
      } catch (e) {
        AppLogger.error('Token refresh failed', exception: e);
        
        // All token refresh errors are treated as temporary issues
      // We'll never force a logout due to token problems
      if (e is DioException) {
        if (e.response?.statusCode == 400) {
          // Bad request (expired token) - keep the user logged in
          AppLogger.warning('Refresh token issue detected, but maintaining user session');
          await _cleanupInvalidAuthState();
        } else if (e.type == DioExceptionType.connectionError || 
                  e.type == DioExceptionType.connectionTimeout) {
          // Network connectivity issues
          AppLogger.warning('Network connectivity issue during token refresh');
        } else {
          // Other API errors
          AppLogger.error('Server error during token refresh: ${e.response?.statusCode}');
        }
      } else {
        // Non-Dio exceptions
        AppLogger.error('Unexpected error during token refresh: $e');
      }
      // Return null instead of throwing - this indicates token refresh failed
      // but we're NOT logging the user out
      return null;
      }
    } catch (e) {
      // Never throw session expiration exceptions
      AppLogger.error('Error in refreshToken', exception: e);
      // Return null instead of throwing - caller should handle this gracefully
      // without forcing user logout
      return null;
    }
  }

  // Helper method to handle invalid tokens without logging out the user
  Future<void> _cleanupInvalidAuthState() async {
    AppLogger.warning('Invalid or expired tokens detected, but maintaining user session');
    // Only clear the API client's current token, but DO NOT remove stored tokens
    // This allows auto-recovery when network conditions improve
    _apiClient.clearAuthToken();
    
    // The user profile and other data remains intact
    // Next API call will trigger a new token refresh attempt
    AppLogger.info('User session maintained - will attempt to recover on next API call');
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
      AppLogger.error('Profile update failed', exception: e);
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