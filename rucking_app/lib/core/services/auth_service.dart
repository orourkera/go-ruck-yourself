import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart'; 
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:logger/logger.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/api/api_exceptions.dart';
import 'package:rucking_app/core/config/app_config.dart';
import 'package:rucking_app/core/models/user.dart';
import 'package:rucking_app/core/services/storage_service.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase, OAuthProvider, AuthResponse, AuthState, AuthChangeEvent;
import 'package:supabase_flutter/supabase_flutter.dart' as supabase show User;
import 'package:url_launcher/url_launcher.dart';
import 'package:jwt_decode/jwt_decode.dart';

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
    String? avatarUrl,
    bool? notificationClubs,
    bool? notificationBuddies,
    bool? notificationEvents,
    bool? notificationDuels,
    bool? notificationFirstRuck,
    String? dateOfBirth,
    int? restingHr,
    int? maxHr,
    String? calorieMethod,
    bool? calorieActiveOnly,
  });

  /// Delete the current user's account
  /// Requires the user's ID to target the correct backend endpoint.
  Future<void> deleteAccount({required String userId});

  /// Sign in with Google
  Future<User> googleSignIn();
  
  /// Sign in with Apple
  Future<User> appleSignIn();
  
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
  
  /// Request password reset for email
  Future<void> requestPasswordReset({required String email});
  
  /// Confirm password reset with token and new password
  Future<void> confirmPasswordReset({
    required String token,
    required String newPassword,
    String? refreshToken,
  });
}

/// Implementation of AuthService using ApiClient and StorageService
class AuthServiceImpl implements AuthService {
  final ApiClient _apiClient;
  final StorageService _storageService;
  late final GoogleSignIn _googleSignIn;
  
  // Track consecutive refresh failures to detect deleted users
  static int _consecutiveRefreshFailures = 0;
  static const int _maxRefreshFailures = 5; // Increased from 3 to 5 to be less aggressive

  // Profile request cache to avoid rapid successive calls
  static Future<User>? _profileRequestCache;
  static DateTime? _lastProfileRequest;
  static const Duration _profileCacheDuration = Duration(seconds: 30); // Increased from 5 to 30 seconds

  AuthServiceImpl(this._apiClient, this._storageService) {
    _googleSignIn = GoogleSignIn(
      scopes: ['email', 'profile'],
      clientId: Platform.isIOS ? '966278977337-l132nm2pas6ifl0kc3oh9977icfja6au.apps.googleusercontent.com' : null, // iOS client ID only, Android uses google-services.json
    );
    
    // Set up the API client to use our refresh token method (with circuit breaker)
    _apiClient.setTokenRefreshCallback(() async {
      final newToken = await refreshToken();
      if (newToken == null) {
        throw Exception('Token refresh failed');
      }
    });
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

      // Store tokens securely
      await _storageService.setSecureString(AppConfig.tokenKey, token);
      await _storageService.setSecureString(AppConfig.refreshTokenKey, refreshToken);

      // Set auth token for subsequent API calls
      _apiClient.setAuthToken(token);

      // Get full user profile after successful authentication
      final user = await getCurrentUser();
      if (user == null) {
        throw ApiException('Authentication succeeded but could not get user data');
      }

      // Reset refresh failure counter on successful login
      _consecutiveRefreshFailures = 0;

      return user;
    } catch (e) {
      AppLogger.error('Login failed', exception: e);
      throw _handleAuthError(e);
    }
  }

  @override
  Future<User> googleSignIn() async {
    try {
      AppLogger.info('Attempting native Google Sign-In');
      
      // Sign in with Google using native approach
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        throw AuthException('Google Sign-In was cancelled', 'GOOGLE_SIGNIN_CANCELLED');
      }

      // Get authentication details from Google
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final accessToken = googleAuth.accessToken;
      final idToken = googleAuth.idToken;

      if (accessToken == null) {
        throw AuthException('No Access Token found', 'GOOGLE_AUTH_NO_ACCESS_TOKEN');
      }
      if (idToken == null) {
        throw AuthException('No ID Token found', 'GOOGLE_AUTH_NO_ID_TOKEN');
      }

      AppLogger.info('Google tokens obtained, authenticating with Supabase');

      // Authenticate with Supabase using Google tokens
      final response = await Supabase.instance.client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
        nonce: null, // Use null for Google (nonce is for Apple primarily)
      );

      final supabaseUser = response.user;
      final session = response.session;
      
      if (supabaseUser == null || session == null) {
        throw AuthException('Supabase authentication failed', 'SUPABASE_AUTH_FAILED');
      }

      AppLogger.info('Google authentication successful, user: ${supabaseUser.email}');
      
      // Store tokens FIRST before making any API calls to prevent token expiration issues
      await _storageService.setSecureString(AppConfig.tokenKey, session.accessToken);
      await _storageService.setSecureString(AppConfig.refreshTokenKey, session.refreshToken!);
      
      // Set auth token for API calls AFTER storing
      _apiClient.setAuthToken(session.accessToken);
      
      // Reset refresh failure counter on successful login
      _consecutiveRefreshFailures = 0;
      
      // Add small delay to ensure token is properly set in all systems
      await Future.delayed(const Duration(milliseconds: 100));
      
      try {
        // Try to get existing user profile from your backend
        AppLogger.info('Fetching user profile after Google authentication');
        final user = await _fetchUserProfileWithRetry();
        
        AppLogger.info('Google Sign-In successful for existing user: ${user.email}');
        return user;
      } catch (e) {
        AppLogger.info('User profile not found, creating new profile for Google user: ${supabaseUser.email}');
        
        // User doesn't exist in your backend, create new profile
        final newUserData = {
          'email': supabaseUser.email!,
          'username': supabaseUser.userMetadata?['full_name'] ?? supabaseUser.email!.split('@')[0],
          'is_metric': true, // Default to metric
        };
        
        try {
          final createResponse = await _apiClient.post('/users/profile', newUserData);
          final newUser = User.fromJson(createResponse);
          
          AppLogger.info('Google Sign-In successful for new user: ${newUser.email}');
          return newUser;
        } catch (createError) {
          AppLogger.error('Failed to create user profile after Google login', exception: createError);
          // Profile creation failed - this is a critical error that should not be silently handled
          throw AuthException(
            'Failed to create user profile after Google authentication: ${createError.toString()}',
            'PROFILE_CREATION_FAILED'
          );
        }
      }
    } catch (e) {
      AppLogger.error('Google sign-in failed', exception: e);
      if (e is AuthException) {
        throw e;
      }
      throw AuthException('Google Sign-In failed: ${e.toString()}', 'GOOGLE_SIGNIN_ERROR');
    }
  }
  
  @override
  Future<User> appleSignIn() async {
    try {
      AppLogger.info('Attempting Apple Sign-In');
      
      // Check if Apple Sign-In is available
      if (!await SignInWithApple.isAvailable()) {
        throw AuthException(
          'Apple Sign-In is not available on this device',
          'APPLE_SIGNIN_NOT_AVAILABLE'
        );
      }
      
      // Request Apple ID credential
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      
      if (credential.identityToken == null) {
        throw AuthException('No Identity Token found', 'APPLE_AUTH_NO_ID_TOKEN');
      }
      
      AppLogger.info('Apple credential obtained, authenticating with Supabase');
      
      // Authenticate with Supabase using Apple tokens
      final response = await Supabase.instance.client.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: credential.identityToken!,
        accessToken: credential.authorizationCode,
      );
      
      final supabaseUser = response.user;
      final session = response.session;
      
      if (supabaseUser == null || session == null) {
        throw AuthException('Supabase authentication failed', 'SUPABASE_AUTH_FAILED');
      }
      
      AppLogger.info('Apple authentication successful, user: ${supabaseUser.email}');
      
      // Store tokens FIRST before making any API calls
      await _storageService.setSecureString(AppConfig.tokenKey, session.accessToken);
      await _storageService.setSecureString(AppConfig.refreshTokenKey, session.refreshToken!);
      
      // Set auth token for API calls AFTER storing
      _apiClient.setAuthToken(session.accessToken);
      
      // Reset refresh failure counter on successful login
      _consecutiveRefreshFailures = 0;
      
      // Add small delay to ensure token is properly set
      await Future.delayed(const Duration(milliseconds: 100));
      
      try {
        // Try to get existing user profile from your backend
        AppLogger.info('Fetching user profile after Apple authentication');
        final user = await _fetchUserProfileWithRetry();
        
        AppLogger.info('Apple Sign-In successful for existing user: ${user.email}');
        return user;
      } catch (e) {
        AppLogger.info('User profile not found, creating new profile for Apple user: ${supabaseUser.email}');
        
        // Extract user data from Apple credential
        String displayName = '';
        if (credential.givenName != null || credential.familyName != null) {
          displayName = '${credential.givenName ?? ''} ${credential.familyName ?? ''}'.trim();
        }
        
        // If no name provided, use email prefix
        if (displayName.isEmpty) {
          displayName = supabaseUser.email?.split('@')[0] ?? 'User';
        }
        
        final newUserData = {
          'email': supabaseUser.email!,
          'username': displayName,
          'is_metric': true, // Default to metric
        };
        
        try {
          final createResponse = await _apiClient.post('/users/profile', newUserData);
          final newUser = User.fromJson(createResponse);
          
          AppLogger.info('Apple Sign-In successful for new user: ${newUser.email}');
          return newUser;
        } catch (createError) {
          AppLogger.error('Failed to create user profile after Apple login', exception: createError);
          throw AuthException(
            'Failed to create user profile after Apple authentication: ${createError.toString()}',
            'PROFILE_CREATION_FAILED'
          );
        }
      }
    } catch (e) {
      AppLogger.error('Apple sign-in failed', exception: e);
      
      // Handle specific Apple Sign-In errors
      if (e is SignInWithAppleAuthorizationException) {
        if (e.code == AuthorizationErrorCode.canceled) {
          throw AuthException('Apple Sign-In was cancelled', 'APPLE_SIGNIN_CANCELLED');
        }
        throw AuthException('Apple Sign-In failed: ${e.message}', 'APPLE_SIGNIN_ERROR');
      }
      
      if (e is AuthException) {
        throw e;
      }
      
      throw AuthException('Apple Sign-In failed: ${e.toString()}', 'APPLE_SIGNIN_ERROR');
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
      final user = await _fetchUserProfileWithRetry();
      userToReturn = user;
      
    } catch (e) {
      if (e is UnauthorizedException) {
        // Attempt a token refresh once before giving up
        try {
          await refreshToken();
          final user = await _fetchUserProfileWithRetry();
          userToReturn = user;
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
      final response = await _fetchUserProfileWithRetry();
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
      AppLogger.info('[AUTH] Attempting token refresh...');
      
      // One-time cleanup for v3.3.6 - clear potentially invalid tokens
      final prefs = await SharedPreferences.getInstance();
      final hasRunTokenCleanup = prefs.getBool('token_cleanup_v3_3_6') ?? false;
      if (!hasRunTokenCleanup) {
        AppLogger.info('[AUTH] Running one-time token cleanup for v3.3.6');
        await _storageService.removeSecure(AppConfig.tokenKey);
        await _storageService.removeSecure(AppConfig.refreshTokenKey);
        await prefs.setBool('token_cleanup_v3_3_6', true);
        AppLogger.info('[AUTH] Token cleanup completed - user will need to re-authenticate');
        await _handleRefreshFailure();
        return null;
      }
      
      final refreshToken = await _storageService.getSecureString(AppConfig.refreshTokenKey);
      if (refreshToken == null || refreshToken.isEmpty) {
        AppLogger.warning('[AUTH] No refresh token available');
        await _handleRefreshFailure();
        return null;
      }

      AppLogger.debug('[AUTH] Making refresh request with token: ${refreshToken.substring(0, 10)}...');

      final response = await _apiClient.post('/auth/refresh', {
        'refresh_token': refreshToken,
      });

      // Safely extract tokens with null checks
      final newToken = response['token'] as String?;
      final newRefreshToken = response['refresh_token'] as String?;
      
      if (newToken == null || newRefreshToken == null || newToken.isEmpty || newRefreshToken.isEmpty) {
        AppLogger.error('[AUTH] Invalid refresh response - missing or empty tokens');
        AppLogger.error('[AUTH] Response data: $response');
        await _handleRefreshFailure();
        return null;
      }

      await _storageService.setSecureString(AppConfig.tokenKey, newToken);
      await _storageService.setSecureString(AppConfig.refreshTokenKey, newRefreshToken);

      _apiClient.setAuthToken(newToken);
      
      // Test the new token immediately by making a profile request
      try {
        await _fetchUserProfileWithRetry();
        // If profile request succeeds, reset failure counter
        _consecutiveRefreshFailures = 0;
        AppLogger.info('[AUTH] Token refresh successful and verified');
        return newToken;
      } catch (testError) {
        // New token was rejected - this counts as a refresh failure
        AppLogger.warning('[AUTH] Refreshed token was immediately rejected: $testError');
        await _handleRefreshFailure();
        return null;
      }

    } catch (e) {
      AppLogger.error('Error in refreshToken', exception: e);
      
      // Handle specific error cases
      if (e.toString().contains('401') || e.toString().contains('Unauthorized')) {
        AppLogger.error('[AUTH] Refresh token is invalid or expired - clearing stored tokens');
        // Clear invalid tokens to prevent infinite retry loops
        await _storageService.removeSecure(AppConfig.tokenKey);
        await _storageService.removeSecure(AppConfig.refreshTokenKey);
      }
      
      await _handleRefreshFailure();
      return null;
    }
  }
  
  /// Fetches user profile with caching and retry logic to handle rate limiting
  Future<User> _fetchUserProfileWithRetry({bool forceRefresh = false}) async {
    // Check if we can use cached request
    if (!forceRefresh && 
        _profileRequestCache != null && 
        _lastProfileRequest != null &&
        DateTime.now().difference(_lastProfileRequest!) < _profileCacheDuration) {
      AppLogger.info('Using cached profile request');
      return await _profileRequestCache!;
    }

    // Clear old cache
    _profileRequestCache = null;
    _lastProfileRequest = DateTime.now();

    // Create new cached request with retry logic
    _profileRequestCache = _performProfileRequestWithRetry();
    
    return await _profileRequestCache!;
  }

  /// Performs the actual profile request with exponential backoff retry
  Future<User> _performProfileRequestWithRetry() async {
    const maxRetries = 3;
    const baseDelay = Duration(seconds: 1);
    
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        AppLogger.info('Fetching user profile (attempt ${attempt + 1}/$maxRetries)');
        final response = await _apiClient.get('/users/profile');
        final user = User.fromJson(response);
        
        // Store the fetched profile data
        await _storageService.setObject(AppConfig.userProfileKey, user.toJson());
        await _storageService.setString(AppConfig.userIdKey, user.userId);
        
        AppLogger.info('Profile fetch and storage successful');
        return user;
        
      } catch (e) {
        final isRateLimited = e is DioException && e.response?.statusCode == 429;
        final isLastAttempt = attempt == maxRetries - 1;
        
        if (isRateLimited && !isLastAttempt) {
          // Exponential backoff for rate limiting
          final delaySeconds = baseDelay.inSeconds * (attempt + 1) * 2;
          final delay = Duration(seconds: delaySeconds);
          
          AppLogger.warning('Rate limited (429), retrying in ${delay.inSeconds}s (attempt ${attempt + 1}/$maxRetries)');
          await Future.delayed(delay);
          continue;
        }
        
        // Clear cache on error
        _profileRequestCache = null;
        _lastProfileRequest = null;
        
        AppLogger.error('Profile fetch failed after ${attempt + 1} attempts', exception: e);
        throw e;
      }
    }
    
    throw ApiException('Profile fetch failed after $maxRetries attempts');
  }

  /// Handle refresh failure and logout if too many consecutive failures
  Future<void> _handleRefreshFailure() async {
    if (_consecutiveRefreshFailures >= _maxRefreshFailures) {
      AppLogger.warning('[AUTH] Too many consecutive refresh failures ($_consecutiveRefreshFailures). User may be deleted. Forcing logout.');
      
      // Clear all stored authentication data
      await _storageService.removeSecure(AppConfig.tokenKey);
      await _storageService.removeSecure(AppConfig.refreshTokenKey);
      await _storageService.remove(AppConfig.userProfileKey);
      
      // Clear API client token
      _apiClient.clearAuthToken();
      
      // Reset counter after cleanup
      _consecutiveRefreshFailures = 0;
      
      AppLogger.info('[AUTH] User logged out due to authentication failures. App should redirect to login.');
    }
  }
  
  /// Helper method to handle invalid tokens without logging out the user
  Future<void> _cleanupInvalidAuthState() async {
    AppLogger.warning('[AUTH] Invalid or expired tokens detected, but maintaining user session');
    // Only clear the API client's current token, but DO NOT remove stored tokens
    // This allows auto-recovery when network conditions improve
    _apiClient.clearAuthToken();
    
    // The user profile and other data remains intact
    // Next API call will trigger a new token refresh attempt
    AppLogger.info('[AUTH] User session maintained - will attempt to recover on next API call');
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
    String? avatarUrl,
    bool? notificationClubs,
    bool? notificationBuddies,
    bool? notificationEvents,
    bool? notificationDuels,
    bool? notificationFirstRuck,
    String? dateOfBirth,
    int? restingHr,
    int? maxHr,
    String? calorieMethod,
    bool? calorieActiveOnly,
  }) async {
    AppLogger.info('[AUTH] 🔧 Starting profile update request');
    AppLogger.info('[AUTH] 🔧 Update fields: preferMetric=$preferMetric, username=$username, weightKg=$weightKg');
    
    try {
      final data = <String, dynamic>{};
      if (username != null) data['username'] = username;
      if (weightKg != null) data['weight_kg'] = weightKg;
      if (heightCm != null) data['height_cm'] = heightCm;
      if (preferMetric != null) data['preferMetric'] = preferMetric;
      if (allowRuckSharing != null) data['allow_ruck_sharing'] = allowRuckSharing;
      if (gender != null) data['gender'] = gender;
      if (avatarUrl != null) data['avatar_url'] = avatarUrl;
      if (notificationClubs != null) data['notification_clubs'] = notificationClubs;
      if (notificationBuddies != null) data['notification_buddies'] = notificationBuddies;
      if (notificationEvents != null) data['notification_events'] = notificationEvents;
      if (notificationDuels != null) data['notification_duels'] = notificationDuels;
      if (notificationFirstRuck != null) data['notification_first_ruck'] = notificationFirstRuck;
      if (dateOfBirth != null) data['date_of_birth'] = dateOfBirth;
      if (restingHr != null) data['resting_hr'] = restingHr;
      if (maxHr != null) data['max_hr'] = maxHr;
      if (calorieMethod != null) data['calorie_method'] = calorieMethod;
      if (calorieActiveOnly != null) data['calorie_active_only'] = calorieActiveOnly;
      
      // Only send request if there is data to update
      if (data.isEmpty) {
         AppLogger.warning('[AUTH] 🔧 No profile data to update, fetching current user');
         final currentUser = await getCurrentUser(); // This might hit API again
         if (currentUser != null) return currentUser;
         throw ApiException('No profile data provided for update.');
      }

      // Check authentication status before making the request
      final isAuth = await isAuthenticated();
      AppLogger.info('[AUTH] 🔧 Authentication status before profile update: $isAuth');
      
      // Check current token validity
      final currentToken = await _storageService.getSecureString(AppConfig.tokenKey);
      if (currentToken != null) {
        try {
          final isExpired = Jwt.isExpired(currentToken);
          AppLogger.info('[AUTH] 🔧 Current token expired: $isExpired');
        } catch (e) {
          AppLogger.warning('[AUTH] 🔧 Could not check token expiration: $e');
        }
      } else {
        AppLogger.warning('[AUTH] 🔧 No token found in storage');
      }

      AppLogger.info('[AUTH] 🔧 Making PUT request to /users/profile');
      
      // Retry mechanism to handle token refresh race conditions
      dynamic response;
      int maxRetries = 2;
      for (int attempt = 1; attempt <= maxRetries; attempt++) {
        try {
          AppLogger.info('[AUTH] 🔧 Attempt $attempt/$maxRetries');
          response = await _apiClient.put(
            '/users/profile', // No /api prefix needed here
            data,
          );
          break; // Success, exit retry loop
        } catch (e) {
          AppLogger.warning('[AUTH] 🔧 Attempt $attempt failed: $e');
          
          if (attempt == maxRetries) {
            // Last attempt failed, rethrow the error
            rethrow;
          }
          
          // If it's an auth error and we have more attempts, wait briefly and retry
          if (e.toString().contains('UnauthorizedException') || e.toString().contains('Not authenticated')) {
            AppLogger.info('[AUTH] 🔧 Auth error detected, waiting before retry...');
            await Future.delayed(Duration(milliseconds: 500 * attempt)); // 500ms, then 1s
            
            // Force a token refresh before retrying
            try {
              final refreshedToken = await refreshToken();
              if (refreshedToken != null) {
                AppLogger.info('[AUTH] 🔧 Token refreshed before retry');
              } else {
                AppLogger.warning('[AUTH] 🔧 Token refresh failed before retry');
              }
            } catch (refreshError) {
              AppLogger.warning('[AUTH] 🔧 Token refresh error before retry: $refreshError');
            }
          } else {
            // Non-auth error, don't retry
            rethrow;
          }
        }
      }
      
      AppLogger.info('[AUTH] 🔧 Profile update successful, parsing response');
      // The response from PUT likely contains the updated profile
      final user = User.fromJson(response);
      
      // Update stored user data
      await _storageService.setObject(AppConfig.userProfileKey, user.toJson());
      
      AppLogger.info('[AUTH] 🔧 Profile update completed successfully');
      return user;
    } catch (e) {
      AppLogger.error('[AUTH] 🔧 Profile update failed with error: $e');
      if (e.toString().contains('UnauthorizedException') || e.toString().contains('Not authenticated')) {
        AppLogger.error('[AUTH] 🔧 AUTHENTICATION ERROR DETECTED - this is the bug we\'re tracking!');
        // Log additional debugging info
        final hasToken = await _storageService.getSecureString(AppConfig.tokenKey) != null;
        final hasRefreshToken = await _storageService.getSecureString(AppConfig.refreshTokenKey) != null;
        AppLogger.error('[AUTH] 🔧 Has token: $hasToken, Has refresh token: $hasRefreshToken');
      }
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

  @override
  Future<void> requestPasswordReset({required String email}) async {
    try {
      final response = await _apiClient.post(
        '/auth/password-reset',
        {
          'email': email,
        },
      );
      if (response == null) {
        throw Exception('Password reset request failed: No response from server.');
      }
      AppLogger.info('Password reset request successful for email: $email');
    } catch (e) {
      AppLogger.error('Password reset request failed', exception: e);
      throw _handleAuthError(e);
    }
  }

  @override
  Future<void> confirmPasswordReset({
    required String token,
    required String newPassword,
    String? refreshToken,
  }) async {
    try {
      final payload = {
        'token': token,
        'new_password': newPassword,
      };
      
      // Add refresh token if available
      if (refreshToken != null) {
        payload['refresh_token'] = refreshToken;
      }
      
      final response = await _apiClient.post(
        '/auth/password-reset-confirm',
        payload,
      );
      if (response == null) {
        throw Exception('Password reset confirmation failed: No response from server.');
      }
      AppLogger.info('Password reset confirmation successful');
    } catch (e) {
      AppLogger.error('Password reset confirmation failed', exception: e);
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