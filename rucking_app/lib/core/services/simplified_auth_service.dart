import 'dart:async';
import 'dart:io';
import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart';
import 'package:rucking_app/core/config/feature_flags.dart';
import 'package:rucking_app/core/models/user.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/storage_service.dart';
import 'package:rucking_app/core/config/app_config.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/api/api_exceptions.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User, AuthException;
import 'package:gotrue/gotrue.dart' as supabase;
import 'package:google_sign_in/google_sign_in.dart';

/// 🆕 SIMPLIFIED AUTH SERVICE
/// 
/// This is the new, simplified auth implementation that uses Supabase directly
/// instead of the complex custom backend auth flow. It's feature-flagged so we
/// can easily revert to the legacy implementation if needed.
/// 
/// KEY SIMPLIFICATIONS:
/// - Uses Supabase auth directly (no custom backend auth endpoints)
/// - Automatic token refresh (no manual token management)
/// - Auth state listener (reactive UI updates)
/// - Reduced from 950 lines to ~200 lines
/// - Keeps justified custom features (profiles, avatars, mailjet)
class SimplifiedAuthService {
  final ApiClient _apiClient;
  final StorageService _storageService;
  final SupabaseClient _supabase = Supabase.instance.client;
  
  // Auth state stream for reactive UI updates
  StreamSubscription<AuthState>? _authSubscription;
  final StreamController<User?> _userController = StreamController<User?>.broadcast();
  
  // In-memory profile cache and request deduplication
  User? _cachedUser;
  DateTime? _lastProfileFetchAt;
  final Duration _profileCacheDuration = const Duration(seconds: 30);
  Future<User>? _inflightProfileRequest;

  SimplifiedAuthService(this._apiClient, this._storageService) {
    if (AuthFeatureFlags.useSupabaseAuthListener) {
      _setupAuthListener();
    }
  }
  
  /// Stream of current user changes (reactive)
  Stream<User?> get userChanges => _userController.stream;
  
  /// Get current user from Supabase
  supabase.User? get currentSupabaseUser => _supabase.auth.currentUser;
  
  /// Get current session from Supabase
  Session? get currentSession => _supabase.auth.currentSession;
  
  /// Check if user is authenticated
  bool get isAuthenticated => currentSession != null;
  
  /// Get current access token
  String? get currentToken => currentSession?.accessToken;
  
  /// 🚩 FEATURE-FLAGGED: Simplified Sign In
  Future<User> signInSimplified(String email, String password) async {
    if (!AuthFeatureFlags.useDirectSupabaseSignIn) {
      throw UnsupportedError('Simplified sign-in is disabled by feature flag');
    }
    
    try {
      AppLogger.info('[SIMPLIFIED_AUTH] 🔐 Attempting direct Supabase sign-in');
      
      // Use Supabase auth directly - much simpler!
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      
      if (response.user == null || response.session == null) {
        throw AuthException('Sign-in failed: No user or session returned', 'SIGNIN_FAILED');
      }
      
      final supabaseUser = response.user!;
      final session = response.session!;
      
      AppLogger.info('[SIMPLIFIED_AUTH] 🔐 Supabase sign-in successful for: ${supabaseUser.email}');
      
      // Set token for API calls to your backend (for profile management)
      _apiClient.setAuthToken(session.accessToken);
      
      // Fetch user profile from your backend (still needed for extended profile data)
      final user = await _fetchUserProfile();
      
      AppLogger.info('[SIMPLIFIED_AUTH] 🔐 Sign-in complete for user: ${user.userId}');
      _userController.add(user);
      
      return user;
      
    } catch (e) {
      AppLogger.error('[SIMPLIFIED_AUTH] 🔐 Sign-in failed: $e');
      if (e is AuthException) {
        throw e;
      }
      throw AuthException('Sign-in failed: ${e.toString()}', 'SIGNIN_ERROR');
    }
  }
  
  /// 🚩 FEATURE-FLAGGED: Simplified Sign Up
  Future<User> signUpSimplified({
    required String email,
    required String password,
    required String username,
    bool? preferMetric,
    double? weightKg,
    double? heightCm,
    String? dateOfBirth,
    String? gender,
  }) async {
    if (!AuthFeatureFlags.useDirectSupabaseSignUp) {
      throw UnsupportedError('Simplified sign-up is disabled by feature flag');
    }
    
    try {
      AppLogger.info('[SIMPLIFIED_AUTH] 📝 Attempting direct Supabase sign-up');
      
      // Use Supabase auth directly
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
      );
      
      if (response.user == null || response.session == null) {
        throw AuthException('Sign-up failed: No user or session returned', 'SIGNUP_FAILED');
      }
      
      final supabaseUser = response.user!;
      final session = response.session!;
      
      AppLogger.info('[SIMPLIFIED_AUTH] 📝 Supabase sign-up successful for: ${supabaseUser.email}');
      
      // Set token for API calls
      _apiClient.setAuthToken(session.accessToken);
      
      // Create extended user profile in your backend (still needed - this is justified custom logic)
      final user = await _createUserProfile(
        supabaseUserId: supabaseUser.id,
        email: email,
        username: username,
        preferMetric: preferMetric,
        weightKg: weightKg,
        heightCm: heightCm,
        dateOfBirth: dateOfBirth,
        gender: gender,
      );
      
      AppLogger.info('[SIMPLIFIED_AUTH] 📝 Sign-up complete for user: ${user.userId}');
      _userController.add(user);
      
      return user;
      
    } catch (e) {
      AppLogger.error('[SIMPLIFIED_AUTH] 📝 Sign-up failed: $e');
      if (e is AuthException) {
        throw e;
      }
      throw AuthException('Sign-up failed: ${e.toString()}', 'SIGNUP_ERROR');
    }
  }
  
  /// 🚩 FEATURE-FLAGGED: Simplified Google Sign In (Native)
  Future<User> googleSignInSimplified() async {
    if (!AuthFeatureFlags.useDirectSupabaseSignIn) {
      throw UnsupportedError('Simplified Google sign-in is disabled by feature flag');
    }
    
    try {
      AppLogger.info('[SIMPLIFIED_AUTH] 🔍 Attempting native Google OAuth');
      AppLogger.info('[SIMPLIFIED_AUTH] 🔍 Current session before OAuth: ${_supabase.auth.currentSession != null}');
      
      // Check if user is already authenticated with Google
      final currentSession = _supabase.auth.currentSession;
      if (currentSession != null && 
          currentSession.user.appMetadata['provider'] == 'google') {
        AppLogger.info('[SIMPLIFIED_AUTH] ✅ User already authenticated with Google, fetching profile');
        _apiClient.setAuthToken(currentSession.accessToken);
        return await _fetchUserProfile();
      }
      
      AppLogger.info('[SIMPLIFIED_AUTH] 🔍 Starting native Google OAuth flow');
      
      // Use native Google Sign-In (similar to Apple approach)
      final GoogleSignIn googleSignIn = GoogleSignIn(
        scopes: ['email', 'profile'],
      );
      
      // Sign in with Google
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        throw AuthException('Google Sign-In was cancelled', 'GOOGLE_SIGNIN_CANCELLED');
      }
      
      // Get authentication details from Google
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      
      if (idToken == null) {
        throw AuthException('No ID token received from Google', 'GOOGLE_NO_TOKEN');
      }
      
      AppLogger.info('[SIMPLIFIED_AUTH] 🔍 Got Google ID token, signing in with Supabase');
      
      // Sign in with Supabase using the Google ID token
      final response = await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
      );
      
      if (response.user == null || response.session == null) {
        throw AuthException('Google sign-in succeeded but no Supabase session created', 'GOOGLE_NO_SESSION');
      }
      
      final supabaseUser = response.user!;
      final session = response.session!;
      
      AppLogger.info('[SIMPLIFIED_AUTH] ✅ Google OAuth successful for user: ${supabaseUser.email}');
      
      // Set token for API calls to your backend
      _apiClient.setAuthToken(session.accessToken);
      
      // Try to get existing profile, create if not found
      try {
        final user = await _fetchUserProfile();
        _userController.add(user);
        return user;
      } catch (e) {
        AppLogger.info('[SIMPLIFIED_AUTH] 🔍 Creating new Google user profile');
        // Create new profile for Google OAuth user
        final user = await _createGoogleUserProfile(supabaseUser);
        _userController.add(user);
        return user;
      }
      
    } catch (e) {
      AppLogger.error('[SIMPLIFIED_AUTH] 🔍 Google sign-in failed: $e');
      
      // Handle specific Google Sign-In errors
      if (e.toString().contains('SIGN_IN_CANCELLED') || e.toString().contains('cancelled')) {
        throw AuthException('Google Sign-In was cancelled', 'GOOGLE_SIGNIN_CANCELLED');
      }
      
      if (e is AuthException) {
        throw e;
      }
      
      throw AuthException('Google Sign-In failed: ${e.toString()}', 'GOOGLE_SIGNIN_ERROR');
    }
  }
  
  /// Sign out user
  Future<void> signOut() async {
    try {
      AppLogger.info('[SIMPLIFIED_AUTH] 🚪 Signing out user');
      
      await _supabase.auth.signOut();
      _apiClient.clearAuthToken();
      _clearProfileCache();
      _userController.add(null);
      
      AppLogger.info('[SIMPLIFIED_AUTH] 🚪 Sign-out complete');
      
    } catch (e) {
      AppLogger.error('[SIMPLIFIED_AUTH] 🚺 Sign-out failed: $e');
      // Don't throw - always succeed in logging out locally
    }
  }
  
  /// Get current user profile
  Future<User?> getCurrentUser({bool forceRefresh = false}) async {
    if (!isAuthenticated) {
      _clearProfileCache();
      return null;
    }

    // Serve from cache if valid and not forced
    if (!forceRefresh && _isCacheValid()) {
      if (AuthFeatureFlags.enableDebugLogging) {
        AppLogger.debug('[SIMPLIFIED_AUTH] Using cached user profile');
      }
      return _cachedUser;
    }

    // Deduplicate in-flight request
    if (_inflightProfileRequest != null) {
      try {
        final user = await _inflightProfileRequest!;
        return user;
      } catch (e) {
        AppLogger.warning('[SIMPLIFIED_AUTH] In-flight profile request failed: $e');
        // Fall through to try fetching again
      }
    }

    try {
      _inflightProfileRequest = _fetchUserProfile();
      final user = await _inflightProfileRequest!;
      return user;
    } catch (e) {
      AppLogger.warning('[SIMPLIFIED_AUTH] Failed to fetch user profile: $e');
      return _cachedUser; // Return stale cache if available
    } finally {
      _inflightProfileRequest = null;
    }
  }
  
  /// 🚩 Setup auth state listener (feature-flagged)
  void _setupAuthListener() {
    if (!AuthFeatureFlags.useSupabaseAuthListener) return;
    
    AppLogger.info('[SIMPLIFIED_AUTH] 🎧 Setting up auth state listener');
    
    _authSubscription = _supabase.auth.onAuthStateChange.listen((data) async {
      final event = data.event;
      final session = data.session;
      
      if (AuthFeatureFlags.enableDebugLogging) {
        AppLogger.info('[SIMPLIFIED_AUTH] 🎧 Auth state change: $event');
      }
      
      switch (event) {
        case AuthChangeEvent.signedIn:
          if (session != null) {
            _apiClient.setAuthToken(session.accessToken);
            try {
              final user = await _fetchUserProfile();
              _userController.add(user);
            } catch (e) {
              AppLogger.warning('[SIMPLIFIED_AUTH] Failed to fetch profile on sign-in: $e');
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
            if (AuthFeatureFlags.enableDebugLogging) {
              AppLogger.info('[SIMPLIFIED_AUTH] 🔄 Token refreshed automatically');
            }
          }
          break;
          
        default:
          break;
      }
    });
  }
  
  /// Fetch user profile from backend (still needed for extended profile data)
  Future<User> _fetchUserProfile() async {
    final response = await _apiClient.get('/users/profile');
    final user = User.fromJson(response);
    _cachedUser = user;
    _lastProfileFetchAt = DateTime.now();
    return user;
  }

  // Profile cache helpers
  bool _isCacheValid() {
    if (_cachedUser == null || _lastProfileFetchAt == null) return false;
    return DateTime.now().difference(_lastProfileFetchAt!) < _profileCacheDuration;
  }

  void _clearProfileCache() {
    _cachedUser = null;
    _lastProfileFetchAt = null;
    _inflightProfileRequest = null;
  }
  
  /// Create user profile in backend (still needed - justified custom logic)
  Future<User> _createUserProfile({
    required String supabaseUserId,
    required String email,
    required String username,
    bool? preferMetric,
    double? weightKg,
    double? heightCm,
    String? dateOfBirth,
    String? gender,
  }) async {
    final profileData = {
      'email': email,
      'username': username,
      'prefer_metric': preferMetric ?? true,
      if (weightKg != null) 'weight_kg': weightKg,
      if (heightCm != null) 'height_cm': heightCm,
      if (dateOfBirth != null) 'date_of_birth': dateOfBirth,
      if (gender != null) 'gender': gender,
    };
    
    final response = await _apiClient.post('/users/profile', profileData);
    return User.fromJson(response);
  }
  
  /// Create profile for Google OAuth user
  Future<User> _createGoogleUserProfile(supabase.User supabaseUser) async {
    final username = supabaseUser.userMetadata?['full_name'] ?? 
                    supabaseUser.email?.split('@')[0] ?? 
                    'User';
                    
    return await _createUserProfile(
      supabaseUserId: supabaseUser.id,
      email: supabaseUser.email!,
      username: username,
      preferMetric: true,
    );
  }
  
  /// Dispose resources
  void dispose() {
    _authSubscription?.cancel();
    _userController.close();
  }
}
