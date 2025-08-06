import 'package:flutter/foundation.dart';
import 'package:rucking_app/core/services/remote_config_service.dart';

/// 🌐 REMOTE CONTROLLED Feature Flags via Firebase Remote Config
/// 
/// This system provides:
/// ✅ Instant remote toggle capability (no app deployment needed)
/// ✅ Gradual rollout support (percentage-based activation)
/// ✅ A/B testing capabilities
/// ✅ Emergency kill switches
/// ✅ Fallback to safe defaults if remote config fails
class FeatureFlags {
  static RemoteConfigService get _remoteConfig => RemoteConfigService.instance;
  
  // ============================================================================
  // 🔐 SIMPLIFIED AUTH SYSTEM (Single Master Toggle)
  // ============================================================================
  
  /// Master toggle for simplified auth system
  /// 🌐 REMOTE CONTROLLED: Can be toggled instantly via Firebase Console
  /// 🔒 FALLBACK: Enabled in debug mode for testing simplified auth
  /// 
  /// When enabled, this activates ALL simplified auth features:
  /// ✅ Direct Supabase signIn/signUp (no custom backend auth)
  /// ✅ Automatic token refresh via Supabase SDK
  /// ✅ Native auth state listeners
  /// ✅ Streamlined auth flow
  static bool get useSimplifiedAuth {
    return _remoteConfig.getBool('use_simplified_auth', fallback: kDebugMode);
  }
  
  // Simplified auth feature getters (all controlled by master toggle)
  static bool get useDirectSupabaseSignin => useSimplifiedAuth;
  static bool get useDirectSupabaseSignup => useSimplifiedAuth;
  static bool get useAutomaticTokenRefresh => useSimplifiedAuth;
  static bool get useSupabaseAuthListener => useSimplifiedAuth;
  
  // ============================================================================
  // 🛡️ BUILT-IN SAFETY FEATURES (Hardcoded for Simplicity)
  // ============================================================================
  
  /// Enable automatic fallback to legacy auth on errors
  /// 🛡️ SAFETY: Always enabled for production safety
  static bool get enableFallbackToLegacyAuth => true;
  
  /// Enable enhanced auth debug logging  
  /// 🔍 DEBUG: Enabled in debug mode, disabled in production
  static bool get enableAuthDebugLogging => kDebugMode;
  
  // ============================================================================
  // 👤 PROFILE MANAGEMENT (Always Enabled - Justified Custom Features)
  // ============================================================================
  
  /// Keep custom user profile management (weight, height, preferences, etc.)
  /// ✅ ALWAYS ENABLED: Extended user profiles beyond Supabase's scope
  static bool get keepCustomProfileManagement => true;
  
  /// Keep avatar upload with image processing
  /// ✅ ALWAYS ENABLED: Complex image processing and storage
  static bool get keepAvatarUploadProcessing => true;
  
  /// Keep Mailjet marketing integration
  /// ✅ ALWAYS ENABLED: Custom marketing automation
  static bool get keepMailjetIntegration => true;
  
  // ============================================================================
  // 📊 STATUS & UTILITY METHODS
  // ============================================================================
  
  /// Get human-readable status of simplified auth
  static Map<String, dynamic> getAuthFeatureStatus() {
    return {
      'USE_SIMPLIFIED_AUTH (Master Toggle)': useSimplifiedAuth,
      'FALLBACK_TO_LEGACY_ENABLED': enableFallbackToLegacyAuth,
      'DEBUG_LOGGING_ENABLED': enableAuthDebugLogging,
    };
  }
  
  /// Check if simplified auth features are enabled
  static bool get hasAnySimplifiedAuthEnabled {
    return useSimplifiedAuth; // Simple now - just one master toggle!
  }
  
  /// Get remote config debug information
  static Map<String, dynamic> getRemoteConfigDebugInfo() {
    return _remoteConfig.getDebugInfo();
  }
  
  /// Force refresh remote config (for debug/admin use)
  static Future<void> forceRefreshRemoteConfig() async {
    await _remoteConfig.forceRefresh();
  }
}

/// 🔐 Auth Feature Flag Helpers (Backward Compatibility)
/// 
/// These getters maintain backward compatibility with existing code
/// while now being powered by Firebase Remote Config
class AuthFeatureFlags {
  static bool get useSimplifiedAuth => FeatureFlags.useSimplifiedAuth;
  static bool get useDirectSupabaseSignIn => FeatureFlags.useDirectSupabaseSignin;
  static bool get useDirectSupabaseSignUp => FeatureFlags.useDirectSupabaseSignup;
  static bool get useAutomaticTokenRefresh => FeatureFlags.useAutomaticTokenRefresh;
  static bool get useSupabaseAuthListener => FeatureFlags.useSupabaseAuthListener;
  static bool get enableFallbackToLegacy => FeatureFlags.enableFallbackToLegacyAuth;
  static bool get enableDebugLogging => FeatureFlags.enableAuthDebugLogging;
  
  /// Get all auth flags as a map (for wrapper and debug use)
  static Map<String, bool> getAllFlags() {
    return {
      'useSimplifiedAuth': useSimplifiedAuth,
      'useDirectSupabaseSignIn': useDirectSupabaseSignIn,
      'useDirectSupabaseSignUp': useDirectSupabaseSignUp,
      'useAutomaticTokenRefresh': useAutomaticTokenRefresh,
      'useSupabaseAuthListener': useSupabaseAuthListener,
      'enableFallbackToLegacy': enableFallbackToLegacy,
      'enableDebugLogging': enableDebugLogging,
    };
  }
}
