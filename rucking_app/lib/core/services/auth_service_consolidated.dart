import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:rucking_app/core/models/user.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/storage_service.dart';
import 'package:rucking_app/core/config/app_config.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/api/api_exceptions.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    hide User, AuthException;
import 'package:gotrue/gotrue.dart' as supabase;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:jwt_decode/jwt_decode.dart';

/// Consolidated Authentication Service
///
/// This is the single, unified authentication implementation that:
/// - Uses Supabase for authentication (tokens, sessions)
/// - Maintains custom user profiles in backend
/// - Handles Google/Apple OAuth
/// - Provides automatic token refresh
/// - Implements proper error handling and retry logic
class AuthService {
  final ApiClient _apiClient;
  final StorageService _storageService;
  final SupabaseClient _supabase = Supabase.instance.client;
  late final GoogleSignIn _googleSignIn;

  // Auth state stream for reactive UI updates
  StreamSubscription<AuthState>? _authSubscription;
  final StreamController<User?> _userController = StreamController<User?>.broadcast();

  // Profile cache and request deduplication
  User? _cachedUser;
  DateTime? _lastProfileFetchAt;
  final Duration _profileCacheDuration = const Duration(seconds: 30);
  Future<User>? _inflightProfileRequest;

  // Track consecutive refresh failures
  static int _consecutiveRefreshFailures = 0;
  static const int _maxRefreshFailures = 5;

  AuthService(this._apiClient, this._storageService) {
    _googleSignIn = GoogleSignIn(
      scopes: ['email', 'profile'],
      clientId: Platform.isIOS
          ? '966278977337-l132nm2pas6ifl0kc3oh9977icfja6au.apps.googleusercontent.com'
          : null,
    );

    _setupAuthListener();

    // Set up the API client to use our refresh token method
    _apiClient.setTokenRefreshCallback(() async {
      final session = await _refreshSession();
      if (session == null) {
        throw Exception('Token refresh failed');
      }
    });
  }

  /// Stream of current user changes (reactive)
  Stream<User?> get userChanges => _userController.stream;

  /// Get current user from Supabase
  supabase.User? get currentSupabaseUser => _supabase.auth.currentUser;

  /// Get current session from Supabase
  Session? get currentSession => _supabase.auth.currentSession;

  /// Check if user is authenticated
  Future<bool> isAuthenticated() async {
    final session = currentSession;
    if (session == null) return false;

    // Check if token is expired
    try {
      if (Jwt.isExpired(session.accessToken)) {
        // Try to refresh
        final newSession = await _refreshSession();
        return newSession != null;
      }
      return true;
    } catch (e) {
      AppLogger.warning('Failed to check token expiry: $e');
      return false;
    }
  }

  /// Get current access token
  Future<String?> getToken() async {
    final session = currentSession;
    if (session == null) return null;

    // Check if token needs refresh
    try {
      if (Jwt.isExpired(session.accessToken)) {
        final newSession = await _refreshSession();
        return newSession?.accessToken;
      }
    } catch (e) {
      AppLogger.warning('Failed to check/refresh token: $e');
    }

    return session.accessToken;
  }

  /// Sign in with email and password
  Future<User> signIn(String email, String password) async {
    try {
      AppLogger.info('Attempting sign-in for: $email');

      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user == null || response.session == null) {
        throw AuthException('Sign-in failed: Invalid credentials', 'SIGNIN_FAILED');
      }

      final session = response.session!;
      _apiClient.setAuthToken(session.accessToken);

      // Reset refresh failure counter on successful login
      _consecutiveRefreshFailures = 0;

      // Fetch user profile
      final user = await _fetchUserProfile();
      _userController.add(user);

      AppLogger.info('Sign-in successful for user: ${user.userId}');
      return user;
    } catch (e) {
      AppLogger.error('Sign-in failed: $e');
      throw _handleAuthError(e);
    }
  }

  /// Register a new user
  Future<User> register({
    required String username,
    required String email,
    required String password,
    bool? preferMetric,
    double? weightKg,
    double? heightCm,
    String? dateOfBirth,
    String? gender,
  }) async {
    try {
      AppLogger.info('Attempting registration for: $email');

      // Register with Supabase
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
      );

      if (response.user == null || response.session == null) {
        throw AuthException('Registration failed', 'SIGNUP_FAILED');
      }

      final session = response.session!;
      _apiClient.setAuthToken(session.accessToken);

      // Create user profile in backend
      final profileData = {
        'email': email,
        'username': username,
        'prefer_metric': preferMetric ?? true,
        if (weightKg != null) 'weight_kg': weightKg,
        if (heightCm != null) 'height_cm': heightCm,
        if (dateOfBirth != null) 'date_of_birth': dateOfBirth,
        if (gender != null) 'gender': gender,
      };

      final profileResponse = await _apiClient.post('/users/profile', profileData);
      final user = User.fromJson(profileResponse);

      _userController.add(user);
      AppLogger.info('Registration successful for user: ${user.userId}');
      return user;
    } catch (e) {
      AppLogger.error('Registration failed: $e');
      throw _handleAuthError(e);
    }
  }

  /// Sign in with Google
  Future<User> googleSignIn() async {
    try {
      AppLogger.info('Attempting Google Sign-In');

      // Sign in with Google
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        throw AuthException('Google Sign-In was cancelled', 'GOOGLE_SIGNIN_CANCELLED');
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;

      if (idToken == null) {
        throw AuthException('No ID token received from Google', 'GOOGLE_NO_TOKEN');
      }

      // Sign in with Supabase using Google ID token
      final response = await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: googleAuth.accessToken,
      );

      if (response.user == null || response.session == null) {
        throw AuthException('Google sign-in failed', 'GOOGLE_SIGNIN_FAILED');
      }

      final session = response.session!;
      _apiClient.setAuthToken(session.accessToken);

      // Try to get existing profile or create new one
      try {
        final user = await _fetchUserProfile();
        _userController.add(user);
        return user;
      } catch (e) {
        // Create new profile for Google user
        final supabaseUser = response.user!;
        final username = supabaseUser.userMetadata?['full_name'] ??
                        supabaseUser.email?.split('@')[0] ?? 'User';

        final profileData = {
          'email': supabaseUser.email!,
          'username': username,
          'prefer_metric': true,
        };

        final profileResponse = await _apiClient.post('/users/profile', profileData);
        final user = User.fromJson(profileResponse);
        _userController.add(user);
        return user;
      }
    } catch (e) {
      AppLogger.error('Google sign-in failed: $e');
      throw _handleAuthError(e);
    }
  }

  /// Sign in with Apple
  Future<User> appleSignIn() async {
    try {
      AppLogger.info('Attempting Apple Sign-In');

      if (!await SignInWithApple.isAvailable()) {
        throw AuthException('Apple Sign-In is not available', 'APPLE_SIGNIN_NOT_AVAILABLE');
      }

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      if (credential.identityToken == null) {
        throw AuthException('No Identity Token found', 'APPLE_NO_TOKEN');
      }

      // Sign in with Supabase using Apple ID token
      final response = await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: credential.identityToken!,
        accessToken: credential.authorizationCode,
      );

      if (response.user == null || response.session == null) {
        throw AuthException('Apple sign-in failed', 'APPLE_SIGNIN_FAILED');
      }

      final session = response.session!;
      _apiClient.setAuthToken(session.accessToken);

      // Try to get existing profile or create new one
      try {
        final user = await _fetchUserProfile();
        _userController.add(user);
        return user;
      } catch (e) {
        // Create new profile for Apple user
        final supabaseUser = response.user!;
        String displayName = '';
        if (credential.givenName != null || credential.familyName != null) {
          displayName = '${credential.givenName ?? ''} ${credential.familyName ?? ''}'.trim();
        }
        if (displayName.isEmpty) {
          displayName = supabaseUser.email?.split('@')[0] ?? 'User';
        }

        final profileData = {
          'email': supabaseUser.email!,
          'username': displayName,
          'prefer_metric': true,
        };

        final profileResponse = await _apiClient.post('/users/profile', profileData);
        final user = User.fromJson(profileResponse);
        _userController.add(user);
        return user;
      }
    } catch (e) {
      AppLogger.error('Apple sign-in failed: $e');

      if (e is SignInWithAppleAuthorizationException) {
        if (e.code == AuthorizationErrorCode.canceled) {
          throw AuthException('Apple Sign-In was cancelled', 'APPLE_SIGNIN_CANCELLED');
        }
        throw AuthException('Apple Sign-In failed: ${e.message}', 'APPLE_SIGNIN_ERROR');
      }

      throw _handleAuthError(e);
    }
  }

  /// Sign out the current user
  Future<void> signOut() async {
    try {
      AppLogger.info('Signing out user');
      await _supabase.auth.signOut();
      _apiClient.clearAuthToken();
      _clearProfileCache();
      _userController.add(null);
      AppLogger.info('Sign-out complete');
    } catch (e) {
      AppLogger.error('Sign-out failed: $e');
      // Always succeed in logging out locally
      _apiClient.clearAuthToken();
      _clearProfileCache();
      _userController.add(null);
    }
  }

  /// Alias for signOut
  Future<void> logout() async => signOut();

  /// Get the current authenticated user
  Future<User?> getCurrentUser({bool forceRefresh = false}) async {
    if (!await isAuthenticated()) {
      _clearProfileCache();
      return null;
    }

    // Serve from cache if valid
    if (!forceRefresh && _isCacheValid()) {
      return _cachedUser;
    }

    // Deduplicate in-flight requests
    if (_inflightProfileRequest != null) {
      try {
        return await _inflightProfileRequest!;
      } catch (e) {
        AppLogger.warning('In-flight profile request failed: $e');
      }
    }

    try {
      _inflightProfileRequest = _fetchUserProfile();
      final user = await _inflightProfileRequest!;
      return user;
    } catch (e) {
      AppLogger.warning('Failed to fetch user profile: $e');
      return _cachedUser; // Return stale cache if available
    } finally {
      _inflightProfileRequest = null;
    }
  }

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
    bool? stravaAutoExport,
  }) async {
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
      if (stravaAutoExport != null) data['strava_auto_export'] = stravaAutoExport;

      if (data.isEmpty) {
        final currentUser = await getCurrentUser();
        if (currentUser != null) return currentUser;
        throw ApiException('No profile data provided for update');
      }

      AppLogger.info('Updating user profile with ${data.keys.length} fields');

      final response = await _apiClient.put('/users/profile', data);
      final user = User.fromJson(response);

      // Update cache
      _cachedUser = user;
      _lastProfileFetchAt = DateTime.now();
      _userController.add(user);

      AppLogger.info('Profile update successful');
      return user;
    } catch (e) {
      AppLogger.error('Profile update failed: $e');
      throw _handleAuthError(e);
    }
  }

  /// Delete the current user's account
  Future<void> deleteAccount({required String userId}) async {
    try {
      AppLogger.info('Deleting account for user: $userId');
      await _apiClient.delete('/users/$userId');
      await signOut();
      AppLogger.info('Account deletion successful');
    } catch (e) {
      AppLogger.error('Account deletion failed: $e');
      await signOut(); // Sign out anyway
      throw _handleAuthError(e);
    }
  }

  /// Request password reset
  Future<void> requestPasswordReset({required String email}) async {
    try {
      await _apiClient.post('/auth/password-reset', {'email': email});
      AppLogger.info('Password reset requested for: $email');
    } catch (e) {
      AppLogger.error('Password reset request failed: $e');
      throw _handleAuthError(e);
    }
  }

  /// Confirm password reset
  Future<void> confirmPasswordReset({
    required String token,
    required String newPassword,
    String? refreshToken,
  }) async {
    try {
      final payload = {
        'token': token,
        'new_password': newPassword,
        if (refreshToken != null) 'refresh_token': refreshToken,
      };

      await _apiClient.post('/auth/password-reset-confirm', payload);
      AppLogger.info('Password reset confirmed');
    } catch (e) {
      AppLogger.error('Password reset confirmation failed: $e');
      throw _handleAuthError(e);
    }
  }

  /// Refresh the authentication token
  Future<String?> refreshToken() async {
    final session = await _refreshSession();
    return session?.accessToken;
  }

  // Private helper methods

  Future<Session?> _refreshSession() async {
    try {
      AppLogger.info('Attempting token refresh');
      final response = await _supabase.auth.refreshSession();

      if (response.session != null) {
        _apiClient.setAuthToken(response.session!.accessToken);
        _consecutiveRefreshFailures = 0;
        AppLogger.info('Token refresh successful');
        return response.session;
      }

      _handleRefreshFailure();
      return null;
    } catch (e) {
      AppLogger.error('Token refresh failed: $e');
      _handleRefreshFailure();
      return null;
    }
  }

  void _setupAuthListener() {
    AppLogger.info('Setting up auth state listener');

    _authSubscription = _supabase.auth.onAuthStateChange.listen((data) async {
      final event = data.event;
      final session = data.session;

      AppLogger.info('Auth state change: $event');

      switch (event) {
        case AuthChangeEvent.signedIn:
          if (session != null) {
            _apiClient.setAuthToken(session.accessToken);
            try {
              final user = await _fetchUserProfile();
              _userController.add(user);
            } catch (e) {
              AppLogger.warning('Failed to fetch profile on sign-in: $e');
            }
          }
          break;

        case AuthChangeEvent.signedOut:
          _apiClient.clearAuthToken();
          _clearProfileCache();
          _userController.add(null);
          break;

        case AuthChangeEvent.tokenRefreshed:
          if (session != null) {
            _apiClient.setAuthToken(session.accessToken);
            AppLogger.info('Token refreshed automatically');
          }
          break;

        default:
          break;
      }
    });
  }

  Future<User> _fetchUserProfile() async {
    const maxRetries = 3;
    const baseDelay = Duration(seconds: 1);

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        AppLogger.info('Fetching user profile (attempt ${attempt + 1}/$maxRetries)');
        final response = await _apiClient.get('/users/profile');
        final user = User.fromJson(response);

        // Update cache
        _cachedUser = user;
        _lastProfileFetchAt = DateTime.now();

        AppLogger.info('Profile fetch successful');
        return user;
      } catch (e) {
        final isLastAttempt = attempt == maxRetries - 1;

        if (!isLastAttempt && e.toString().contains('429')) {
          // Rate limited - exponential backoff
          final delay = Duration(seconds: baseDelay.inSeconds * (attempt + 1) * 2);
          AppLogger.warning('Rate limited, retrying in ${delay.inSeconds}s');
          await Future.delayed(delay);
          continue;
        }

        if (isLastAttempt) {
          throw e;
        }
      }
    }

    throw ApiException('Profile fetch failed after $maxRetries attempts');
  }

  bool _isCacheValid() {
    if (_cachedUser == null || _lastProfileFetchAt == null) return false;
    return DateTime.now().difference(_lastProfileFetchAt!) < _profileCacheDuration;
  }

  void _clearProfileCache() {
    _cachedUser = null;
    _lastProfileFetchAt = null;
    _inflightProfileRequest = null;
  }

  void _handleRefreshFailure() {
    _consecutiveRefreshFailures++;

    if (_consecutiveRefreshFailures >= _maxRefreshFailures) {
      AppLogger.warning('Too many refresh failures, forcing logout');
      _clearProfileCache();
      _apiClient.clearAuthToken();
      _consecutiveRefreshFailures = 0;
      _userController.add(null);
    }
  }

  Exception _handleAuthError(dynamic error) {
    if (error is AuthException) {
      return error;
    }
    if (error is ApiException) {
      return error;
    }
    return ApiException('Authentication error: $error');
  }

  void dispose() {
    _authSubscription?.cancel();
    _userController.close();
  }
}