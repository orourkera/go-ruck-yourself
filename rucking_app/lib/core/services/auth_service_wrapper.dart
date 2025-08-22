import 'dart:async';
import 'package:rucking_app/core/config/feature_flags.dart';
import 'package:rucking_app/core/models/user.dart';
import 'package:rucking_app/core/services/auth_service.dart';
import 'package:rucking_app/core/services/simplified_auth_service.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/storage_service.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

/// 🔄 AUTH SERVICE WRAPPER
/// 
/// This wrapper allows you to safely switch between the legacy auth implementation
/// and the new simplified auth implementation using feature flags.
/// 
/// USAGE:
/// 1. Test simplified auth in debug mode first
/// 2. Gradually enable features via feature flags
/// 3. Instant rollback by changing feature flags
/// 4. Eventually remove legacy code when confident
/// 
/// SAFETY FEATURES:
/// - Fallback to legacy auth on any error
/// - Feature flags can be toggled per-feature
/// - Debug-only enablement initially
/// - Comprehensive logging for debugging
class AuthServiceWrapper implements AuthService {
  final AuthServiceImpl _legacyAuth;
  final SimplifiedAuthService _simplifiedAuth;
  
  AuthServiceWrapper(ApiClient apiClient, StorageService storageService)
    : _legacyAuth = AuthServiceImpl(apiClient, storageService),
      _simplifiedAuth = SimplifiedAuthService(apiClient, storageService) {
    
    // Log which auth system is active
    if (AuthFeatureFlags.useSimplifiedAuth) {
      AppLogger.info('🆕 [AUTH_WRAPPER] Simplified auth system ENABLED');
      AppLogger.info('🆕 [AUTH_WRAPPER] Feature flags: ${FeatureFlags.getAuthFeatureStatus()}');
    } else {
      AppLogger.info('🏛️ [AUTH_WRAPPER] Legacy auth system active (simplified auth disabled)');
    }
  }
  
  /// Stream of user changes (only available in simplified auth)
  Stream<User?> get userChanges {
    if (AuthFeatureFlags.useSimplifiedAuth) {
      return _simplifiedAuth.userChanges;
    }
    // Return empty stream for legacy auth
    return Stream<User?>.empty();
  }
  
  @override
  Future<User> signIn(String email, String password) async {
    if (AuthFeatureFlags.useDirectSupabaseSignIn) {
      try {
        AppLogger.info('🆕 [AUTH_WRAPPER] Using simplified sign-in');
        return await _simplifiedAuth.signInSimplified(email, password);
      } catch (e) {
        if (AuthFeatureFlags.enableFallbackToLegacy) {
          AppLogger.warning('🆕 [AUTH_WRAPPER] Simplified sign-in failed, falling back to legacy: $e');
          return await _legacyAuth.signIn(email, password);
        }
        rethrow;
      }
    } else {
      AppLogger.info('🏛️ [AUTH_WRAPPER] Using legacy sign-in');
      return await _legacyAuth.signIn(email, password);
    }
  }
  
  @override
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
    if (AuthFeatureFlags.useDirectSupabaseSignUp) {
      try {
        AppLogger.info('🆕 [AUTH_WRAPPER] Using simplified sign-up');
        return await _simplifiedAuth.signUpSimplified(
          email: email,
          password: password,
          username: username,
          preferMetric: preferMetric,
          weightKg: weightKg,
          heightCm: heightCm,
          dateOfBirth: dateOfBirth,
          gender: gender,
        );
      } catch (e) {
        if (AuthFeatureFlags.enableFallbackToLegacy) {
          AppLogger.warning('🆕 [AUTH_WRAPPER] Simplified sign-up failed, falling back to legacy: $e');
          return await _legacyAuth.register(
            username: username,
            email: email,
            password: password,
            preferMetric: preferMetric,
            weightKg: weightKg,
            heightCm: heightCm,
            dateOfBirth: dateOfBirth,
            gender: gender,
          );
        }
        rethrow;
      }
    } else {
      AppLogger.info('🏛️ [AUTH_WRAPPER] Using legacy sign-up');
      return await _legacyAuth.register(
        username: username,
        email: email,
        password: password,
        preferMetric: preferMetric,
        weightKg: weightKg,
        heightCm: heightCm,
        dateOfBirth: dateOfBirth,
        gender: gender,
      );
    }
  }
  
  @override
  Future<User> googleSignIn() async {
    AppLogger.info('🔍 [AUTH_WRAPPER] Google sign-in requested');
    AppLogger.info('🔍 [AUTH_WRAPPER] useDirectSupabaseSignIn: ${AuthFeatureFlags.useDirectSupabaseSignIn}');
    AppLogger.info('🔍 [AUTH_WRAPPER] useSimplifiedAuth: ${AuthFeatureFlags.useSimplifiedAuth}');
    
    if (AuthFeatureFlags.useDirectSupabaseSignIn) {
      try {
        AppLogger.info('🆕 [AUTH_WRAPPER] Using simplified Google sign-in');
        final user = await _simplifiedAuth.googleSignInSimplified();
        AppLogger.info('🆕 [AUTH_WRAPPER] Simplified Google sign-in succeeded for user: ${user.email}');
        return user;
      } catch (e) {
        AppLogger.error('🆕 [AUTH_WRAPPER] Simplified Google sign-in failed: $e');
        if (AuthFeatureFlags.enableFallbackToLegacy) {
          AppLogger.warning('🆕 [AUTH_WRAPPER] Falling back to legacy auth');
          final user = await _legacyAuth.googleSignIn();
          AppLogger.info('🆕 [AUTH_WRAPPER] Legacy fallback succeeded for user: ${user.email}');
          return user;
        }
        rethrow;
      }
    } else {
      AppLogger.info('🏦 [AUTH_WRAPPER] Using legacy Google sign-in');
      final user = await _legacyAuth.googleSignIn();
      AppLogger.info('🏦 [AUTH_WRAPPER] Legacy Google sign-in succeeded for user: ${user.email}');
      return user;
    }
  }
  
  @override
  Future<void> signOut() async {
    if (AuthFeatureFlags.useSimplifiedAuth) {
      try {
        AppLogger.info('🆕 [AUTH_WRAPPER] Using simplified sign-out');
        await _simplifiedAuth.signOut();
      } catch (e) {
        AppLogger.warning('🆕 [AUTH_WRAPPER] Simplified sign-out failed, trying legacy: $e');
        await _legacyAuth.signOut();
      }
    } else {
      AppLogger.info('🏛️ [AUTH_WRAPPER] Using legacy sign-out');
      await _legacyAuth.signOut();
    }
  }
  
  @override
  Future<User?> getCurrentUser() async {
    if (AuthFeatureFlags.useSimplifiedAuth) {
      try {
        return await _simplifiedAuth.getCurrentUser();
      } catch (e) {
        if (AuthFeatureFlags.enableFallbackToLegacy) {
          AppLogger.warning('🆕 [AUTH_WRAPPER] Simplified getCurrentUser failed, falling back to legacy: $e');
          return await _legacyAuth.getCurrentUser();
        }
        rethrow;
      }
    } else {
      return await _legacyAuth.getCurrentUser();
    }
  }
  
  @override
  Future<bool> isAuthenticated() async {
    if (AuthFeatureFlags.useSimplifiedAuth) {
      // Simplified auth can check synchronously
      return _simplifiedAuth.isAuthenticated;
    } else {
      return await _legacyAuth.isAuthenticated();
    }
  }
  
  @override
  Future<String?> getToken() async {
    if (AuthFeatureFlags.useAutomaticTokenRefresh && AuthFeatureFlags.useSimplifiedAuth) {
      // Simplified auth can get token synchronously (no manual refresh needed)
      return _simplifiedAuth.currentToken;
    } else {
      return await _legacyAuth.getToken();
    }
  }
  
  @override
  Future<String?> refreshToken() async {
    if (AuthFeatureFlags.useAutomaticTokenRefresh) {
      AppLogger.info('🆕 [AUTH_WRAPPER] Automatic token refresh enabled - no manual refresh needed');
      // With automatic token refresh, this is handled by Supabase
      return _simplifiedAuth.currentToken;
    } else {
      AppLogger.info('🏛️ [AUTH_WRAPPER] Using legacy manual token refresh');
      return await _legacyAuth.refreshToken();
    }
  }
  
  // All other methods delegate to legacy auth (these are justified custom features)
  @override
  Future<void> logout() => _legacyAuth.logout();
  
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
    String? dateOfBirth,
    int? restingHr,
    int? maxHr,
    String? calorieMethod,
    bool? calorieActiveOnly,
  }) => _legacyAuth.updateProfile(
    username: username,
    weightKg: weightKg,
    heightCm: heightCm,
    preferMetric: preferMetric,
    allowRuckSharing: allowRuckSharing,
    gender: gender,
    avatarUrl: avatarUrl,
    notificationClubs: notificationClubs,
    notificationBuddies: notificationBuddies,
    notificationEvents: notificationEvents,
    notificationDuels: notificationDuels,
    dateOfBirth: dateOfBirth,
    restingHr: restingHr,
    maxHr: maxHr,
    calorieMethod: calorieMethod,
    calorieActiveOnly: calorieActiveOnly,
  );
  
  @override
  Future<void> deleteAccount({required String userId}) => _legacyAuth.deleteAccount(userId: userId);
  
  @override
  Future<User> appleSignIn() => _legacyAuth.appleSignIn();
  
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
  }) => _legacyAuth.googleRegister(
    email: email,
    displayName: displayName,
    username: username,
    preferMetric: preferMetric,
    weightKg: weightKg,
    heightCm: heightCm,
    dateOfBirth: dateOfBirth,
    gender: gender,
  );
  
  @override
  Future<void> requestPasswordReset({required String email}) => _legacyAuth.requestPasswordReset(email: email);
  
  @override
  Future<void> confirmPasswordReset({
    required String token,
    required String newPassword,
    String? refreshToken,
  }) => _legacyAuth.confirmPasswordReset(
    token: token,
    newPassword: newPassword,
    refreshToken: refreshToken,
  );
  
  /// Dispose resources from both implementations
  void dispose() {
    _simplifiedAuth.dispose();
    // Legacy auth doesn't have dispose method
  }
}
