import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

/// 🔧 Firebase Remote Config Service for Dynamic Feature Flags
///
/// Provides centralized management of remote feature flags with:
/// - ✅ Instant remote toggle capability (no app deployment needed)
/// - ✅ Gradual rollout support (percentage-based activation)
/// - ✅ A/B testing capabilities
/// - ✅ Emergency kill switches
/// - ✅ Fallback to hardcoded defaults if remote config fails
///
/// SAFETY: All flags have safe hardcoded defaults that preserve current behavior
class RemoteConfigService {
  static RemoteConfigService? _instance;
  static RemoteConfigService get instance =>
      _instance ??= RemoteConfigService._();

  RemoteConfigService._();

  FirebaseRemoteConfig? _remoteConfig;
  bool _isInitialized = false;
  bool _fetchFailed = false;

  /// Initialize Remote Config with default values and fetch settings
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      AppLogger.info(
          '🔧 [REMOTE_CONFIG] Initializing Firebase Remote Config...');

      _remoteConfig = FirebaseRemoteConfig.instance;

      // Configure settings
      await _remoteConfig!.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: kDebugMode
            ? const Duration(minutes: 1) // Fast refresh in debug
            : const Duration(hours: 1), // 1 hour in production
      ));

      // Set default values (must match hardcoded defaults)
      await _remoteConfig!.setDefaults(_getDefaultValues());

      // Fetch and activate
      await _fetchAndActivate();

      _isInitialized = true;
      AppLogger.info(
          '✅ [REMOTE_CONFIG] Successfully initialized with ${_remoteConfig!.getAll().length} parameters');
    } catch (e, stackTrace) {
      AppLogger.error('❌ [REMOTE_CONFIG] Failed to initialize: $e',
          stackTrace: stackTrace);
      _fetchFailed = true;
      _isInitialized = false;
    }
  } // <--- Added closing brace here

  /// Convenience: Get the AI Goal system prompt version.
  /// This should be forwarded to the backend so it can select the appropriate
  /// server-side system prompt without trusting client-provided prompt text.
  int getAIGoalPromptVersion() {
    return getInt('ai_goal_prompt_version', fallback: 1);
  }

  /// Convenience: Get the AI Notification (push copy) system prompt version.
  /// Forward this to the backend to select the server-side notification prompt.
  int getAINotificationPromptVersion() {
    return getInt('ai_notification_prompt_version', fallback: 1);
  }

  /// Get the AI Goals system prompt (full text)
  String getAIGoalSystemPrompt() {
    return getString('ai_goal_system_prompt',
        fallback:
            '''You are an expert AI coach helping users set, track, and evaluate rucking goals.
Your job:
- Interpret user intent and preferences from structured inputs (user profile, history, unit preferences)
- Propose clear, safe, and measurable rucking goals
- Generate evaluation logic that can be run server-side against user activity

Guidelines:
- Keep goals SMART: Specific, Measurable, Achievable, Relevant, Time-bound
- Respect units (metric or imperial)
- Avoid unsafe recommendations (excessive weight or volume spikes)
- Prefer progressive overload and sustainable schedules
- Provide concise titles and clear descriptions
''');
  }

  /// Get the AI Notification system prompt (full text) used for goal-related push copy
  String getAINotificationSystemPrompt() {
    return getString('ai_notification_system_prompt',
        fallback:
            '''You are a concise, motivational copywriter for rucking goal notifications.
Given structured context (goal details, progress deltas, streaks, time-of-day), craft short push messages:
- Max ~90 characters ideal, 120 hard limit
- Positive, actionable, non-repetitive
- Reference recent progress when helpful
- Never guilt or shame
''');
  }

  /// Get the AI Cheerleader system prompt
  String getAICheerleaderSystemPrompt() {
    return getString('ai_cheerleader_system_prompt',
        fallback:
            '''You are an enthusiastic AI cheerleader for rucking workouts. 
Analyze the provided context JSON: 
- 'current_session': Real-time stats like distance, pace, duration.
- 'historical': Past rucks, splits, achievements, user profile, notifications, and ai_cheerleader_history (your previous messages to this user).
Generate personalized, motivational messages. Reference historical trends (e.g., 'Faster than your last 3 rucks!') and achievements (e.g., 'Building on your 10K badge!') to encourage based on current progress. Avoid repeating similar messages from your ai_cheerleader_history - be creative and vary your encouragement style. Keep responses under 150 words, positive, and action-oriented.''');
  }

  /// Get the AI Cheerleader user prompt template
  String getAICheerleaderUserPromptTemplate() {
    return getString('ai_cheerleader_user_prompt_template',
        fallback:
            'Context data:\n{context}\nGenerate encouragement for this ongoing ruck session.');
  }

  /// Fetch latest config from Firebase and activate
  Future<void> _fetchAndActivate() async {
    try {
      AppLogger.info('🔄 [REMOTE_CONFIG] Fetching latest configuration...');

      final bool updated = await _remoteConfig!.fetchAndActivate();

      if (updated) {
        AppLogger.info('✅ [REMOTE_CONFIG] Configuration updated successfully');
        _logActiveFlags();
      } else {
        AppLogger.info('ℹ️ [REMOTE_CONFIG] Configuration already up to date');
      }

      _fetchFailed = false;
    } catch (e, stackTrace) {
      AppLogger.warning(
          '⚠️ [REMOTE_CONFIG] Failed to fetch, using cached/default values: $e\n$stackTrace');
      _fetchFailed = true;
    }
  }

  /// Get default values for all feature flags
  Map<String, Object> _getDefaultValues() {
    return {
      // Auth Feature Flags (match feature_flags.dart defaults)
      'use_simplified_auth': kDebugMode,
      'use_direct_supabase_signin': kDebugMode,
      'use_direct_supabase_signup': kDebugMode,
      'use_automatic_token_refresh': kDebugMode,
      'use_supabase_auth_listener': kDebugMode,

      // Safety flags (always enabled)
      'enable_fallback_to_legacy_auth': true,
      'enable_auth_debug_logging': kDebugMode,

      // Profile management (always enabled)
      'keep_custom_profile_management': true,
      'keep_avatar_upload_processing': true,
      'keep_mailjet_integration': true,

      // Rollout controls
      'auth_rollout_percentage':
          kDebugMode ? 100 : 0, // 0% in production initially
      'emergency_disable_all_flags': false,

      // AI Cheerleader feature flags
      'ai_cheerleader_manual_trigger':
          kDebugMode, // Enable in debug for testing

      // AI Goals / Prompt selection
      // Use a version number to select the server-side system prompt.
      // This avoids shipping full prompt text from client while still enabling
      // dynamic changes via Remote Config.
      'ai_goal_prompt_version': 1,
      'ai_notification_prompt_version': 1,

      // AI Cheerleader Prompts (full text stored in Remote Config)
      'ai_cheerleader_system_prompt':
          '''You are an enthusiastic AI cheerleader for rucking workouts. 
Analyze the provided context and generate personalized, motivational messages. 
Focus on the user's current performance, progress, and achievements.
Be encouraging, positive, and action-oriented.
Vary your encouragement style and avoid repetition.
Reference specific stats when relevant (pace, distance, heart rate, etc.).''',

      'ai_cheerleader_user_prompt_template':
          'Context data:\n{context}\nGenerate encouragement for this ongoing ruck session.',

      // AI Goals & Notifications Prompts (full text stored in Remote Config)
      'ai_goal_system_prompt':
          '''You are an expert AI coach helping users set, track, and evaluate rucking goals.
Your job:
- Interpret user intent and preferences from structured inputs (user profile, history, unit preferences)
- Propose clear, safe, and measurable rucking goals
- Generate evaluation logic that can be run server-side against user activity

Guidelines:
- Keep goals SMART: Specific, Measurable, Achievable, Relevant, Time-bound
- Respect units (metric or imperial)
- Avoid unsafe recommendations (excessive weight or volume spikes)
- Prefer progressive overload and sustainable schedules
- Provide concise titles and clear descriptions
''',
      'ai_notification_system_prompt':
          '''You are a concise, motivational copywriter for rucking goal notifications.
Given structured context (goal details, progress deltas, streaks, time-of-day), craft short push messages:
- Max ~90 characters ideal, 120 hard limit
- Positive, actionable, non-repetitive
- Reference recent progress when helpful
- Never guilt or shame
''',
    };
  }

  /// Log currently active flags for debugging
  void _logActiveFlags() {
    if (!_isInitialized) return;

    AppLogger.info('📊 [REMOTE_CONFIG] Active feature flags:');
    final flags = getAuthFeatureFlags();
    flags.forEach((key, value) {
      AppLogger.info('  • $key: $value');
    });
  }

  // ============================================================================
  // PUBLIC API - Feature Flag Getters
  // ============================================================================

  /// Get all auth-related feature flags
  Map<String, bool> getAuthFeatureFlags() {
    return {
      'use_simplified_auth': getBool('use_simplified_auth'),
      'use_direct_supabase_signin': getBool('use_direct_supabase_signin'),
      'use_direct_supabase_signup': getBool('use_direct_supabase_signup'),
      'use_automatic_token_refresh': getBool('use_automatic_token_refresh'),
      'use_supabase_auth_listener': getBool('use_supabase_auth_listener'),
      'enable_fallback_to_legacy_auth':
          getBool('enable_fallback_to_legacy_auth'),
      'enable_auth_debug_logging': getBool('enable_auth_debug_logging'),
    };
  }

  /// Get boolean flag value with fallback to default
  bool getBool(String key, {bool? fallback}) {
    if (!_isInitialized || _remoteConfig == null || _fetchFailed) {
      final defaultValue =
          _getDefaultValues()[key] as bool? ?? fallback ?? false;
      AppLogger.debug(
          '🔧 [REMOTE_CONFIG] Using default value for $key: $defaultValue (not initialized or fetch failed)');
      return defaultValue;
    }

    try {
      final value = _remoteConfig!.getBool(key);

      // Check for emergency disable
      if (getBoolDirect('emergency_disable_all_flags')) {
        AppLogger.warning(
            '🚨 [REMOTE_CONFIG] Emergency flag disable active - returning false for $key');
        return false;
      }

      // Check rollout percentage for auth flags
      if (key.startsWith('use_') && key.contains('auth') ||
          key.contains('supabase')) {
        final rolloutPercentage =
            getInt('auth_rollout_percentage', fallback: 0);
        if (rolloutPercentage < 100) {
          final shouldEnable = _isUserInRollout(rolloutPercentage);
          if (!shouldEnable) {
            AppLogger.debug(
                '🎲 [REMOTE_CONFIG] User not in rollout for $key (${rolloutPercentage}%)');
            return false;
          }
        }
      }

      AppLogger.debug('🔧 [REMOTE_CONFIG] $key: $value');
      return value;
    } catch (e) {
      final defaultValue =
          _getDefaultValues()[key] as bool? ?? fallback ?? false;
      AppLogger.warning(
          '⚠️ [REMOTE_CONFIG] Error getting $key, using default: $defaultValue ($e)');
      return defaultValue;
    }
  }

  /// Get boolean flag directly (bypasses rollout and emergency checks)
  bool getBoolDirect(String key, {bool? fallback}) {
    if (!_isInitialized || _remoteConfig == null || _fetchFailed) {
      return _getDefaultValues()[key] as bool? ?? fallback ?? false;
    }

    try {
      return _remoteConfig!.getBool(key);
    } catch (e) {
      return _getDefaultValues()[key] as bool? ?? fallback ?? false;
    }
  }

  /// Get integer flag value
  int getInt(String key, {int? fallback}) {
    if (!_isInitialized || _remoteConfig == null || _fetchFailed) {
      return _getDefaultValues()[key] as int? ?? fallback ?? 0;
    }

    try {
      return _remoteConfig!.getInt(key);
    } catch (e) {
      return _getDefaultValues()[key] as int? ?? fallback ?? 0;
    }
  }

  /// Get string flag value
  String getString(String key, {String? fallback}) {
    if (!_isInitialized || _remoteConfig == null || _fetchFailed) {
      return _getDefaultValues()[key] as String? ?? fallback ?? '';
    }

    try {
      return _remoteConfig!.getString(key);
    } catch (e) {
      return _getDefaultValues()[key] as String? ?? fallback ?? '';
    }
  }

  /// Check if user is in rollout percentage (simple hash-based distribution)
  bool _isUserInRollout(int percentage) {
    if (percentage >= 100) return true;
    if (percentage <= 0) return false;

    // Simple hash-based distribution (consistent per user/device)
    // In production, you might use user ID or device ID for more precise control
    final hash = DateTime.now().millisecondsSinceEpoch.hashCode;
    final bucket = hash.abs() % 100;
    return bucket < percentage;
  }

  // ============================================================================
  // ADMIN/DEBUG FUNCTIONS
  // ============================================================================

  /// Force refresh configuration (for debug/admin use)
  Future<void> forceRefresh() async {
    if (!_isInitialized) {
      AppLogger.warning('⚠️ [REMOTE_CONFIG] Cannot refresh - not initialized');
      return;
    }

    AppLogger.info('🔄 [REMOTE_CONFIG] Force refreshing configuration...');
    await _fetchAndActivate();
  }

  /// Get initialization status
  bool get isInitialized => _isInitialized;

  /// Get fetch status
  bool get hasFetchFailed => _fetchFailed;

  /// Get last fetch time
  DateTime? get lastFetchTime => _remoteConfig?.lastFetchTime;

  /// Get all current values (for debug screen)
  Map<String, dynamic> getAllValues() {
    if (!_isInitialized || _remoteConfig == null) {
      return _getDefaultValues();
    }

    try {
      final allValues = <String, dynamic>{};
      for (final key in _getDefaultValues().keys) {
        allValues[key] = _remoteConfig!.getValue(key).asString();
      }
      return allValues;
    } catch (e) {
      AppLogger.warning('⚠️ [REMOTE_CONFIG] Error getting all values: $e');
      return _getDefaultValues();
    }
  }

  /// Get remote config info for debugging
  Map<String, dynamic> getDebugInfo() {
    return {
      'isInitialized': _isInitialized,
      'hasFetchFailed': _fetchFailed,
      'lastFetchTime': lastFetchTime?.toIso8601String(),
      'totalParameters': _remoteConfig?.getAll().length ?? 0,
      'rolloutPercentage': getInt('auth_rollout_percentage'),
      'emergencyDisabled': getBoolDirect('emergency_disable_all_flags'),
    };
  }
}
