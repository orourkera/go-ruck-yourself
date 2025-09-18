import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rucking_app/features/social_sharing/widgets/quick_share_bottom_sheet.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

/// Frequency levels for share prompts
enum ShareFrequency {
  majorOnly, // ~1x per week max
  moderate, // ~2x per week max
  active, // ~3x per week max
}

/// Service that determines when to show share prompts
class SharePromptLogic {
  static const String _keyTotalShares = 'total_shares_count';
  static const String _keyLastPromptShown = 'last_share_prompt_shown';
  static const String _keySnoozedUntil = 'share_prompt_snoozed_until';
  static const String _keyDismissCount = 'share_prompt_dismiss_count';
  static const String _keyLastDismiss = 'share_prompt_last_dismiss';
  static const String _keySessionsShared = 'sessions_shared';
  static const String _keyPromptsDisabled = 'share_prompts_disabled';
  // New keys for staged backoff logic
  static const String _keyRuckCount = 'sp_ruck_count';
  static const String _keyStage = 'sp_stage'; // 0: every ruck, 1: every 3rd, 2: every 10th, 3: monthly
  static const String _keyEngagedAlways = 'sp_engaged_always';
  static const String _keyLastMonthlyShown = 'sp_last_monthly_shown';

  /// Check if we should show the share prompt for this session
  static Future<bool> shouldShowPrompt({
    required String sessionId,
    required double distanceKm,
    required Duration duration,
    required bool hasAchievement,
    required bool isPR,
    required int sessionNumber,
    bool? isRated5Stars,
    int? streakDays,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Check if prompts are disabled
      if (prefs.getBool(_keyPromptsDisabled) ?? false) {
        AppLogger.info('[SHARE_PROMPT] Prompts disabled by user');
        return false;
      }

      // Check if session is too short
      if (duration.inMinutes < 10) {
        AppLogger.info('[SHARE_PROMPT] Session too short: ${duration.inMinutes}m');
        return false;
      }

      // Check if already shared this session
      final sharedSessions = prefs.getStringList(_keySessionsShared) ?? [];
      if (sharedSessions.contains(sessionId)) {
        AppLogger.info('[SHARE_PROMPT] Session already shared');
        return false;
      }

      // Check if we've already shown a prompt for this session
      if (await hasPromptBeenShown(sessionId)) {
        AppLogger.info('[SHARE_PROMPT] Prompt already shown for this session');
        return false;
      }

      // Check if snoozed
      final snoozedUntil = prefs.getString(_keySnoozedUntil);
      if (snoozedUntil != null) {
        final snoozeEnd = DateTime.parse(snoozedUntil);
        if (DateTime.now().isBefore(snoozeEnd)) {
          AppLogger.info('[SHARE_PROMPT] Snoozed until $snoozeEnd');
          return false;
        }
      }

      // Check dismiss count
      final dismissCount = prefs.getInt(_keyDismissCount) ?? 0;
      final lastDismiss = prefs.getString(_keyLastDismiss);
      if (dismissCount >= 3 && lastDismiss != null) {
        final lastDismissDate = DateTime.parse(lastDismiss);
        final daysSinceDismiss = DateTime.now().difference(lastDismissDate).inDays;
        if (daysSinceDismiss < 30) {
          AppLogger.info('[SHARE_PROMPT] Dismissed 3 times in last 30 days');
          return false;
        }
      }

      // Increment ruck counter (one call per completed ruck)
      final currentCount = (prefs.getInt(_keyRuckCount) ?? 0) + 1;
      await prefs.setInt(_keyRuckCount, currentCount);

      // If user engaged previously, show after every ruck
      if (prefs.getBool(_keyEngagedAlways) ?? false) {
        await prefs.setString(_keyLastPromptShown, DateTime.now().toIso8601String());
        return true;
      }

      // Determine stage
      final stage = prefs.getInt(_keyStage) ?? 0;
      bool allow = false;
      if (stage == 0) {
        // First time after a ruck
        allow = true;
      } else if (stage == 1) {
        // Every 3rd ruck
        allow = currentCount % 3 == 0;
      } else if (stage == 2) {
        // Every 10th ruck
        allow = currentCount % 10 == 0;
      } else {
        // Monthly
        final lastMonthly = prefs.getString(_keyLastMonthlyShown);
        if (lastMonthly == null) {
          allow = true;
        } else {
          final last = DateTime.parse(lastMonthly);
          allow = DateTime.now().difference(last).inDays >= 30;
        }
      }

      if (allow) {
        await prefs.setString(_keyLastPromptShown, DateTime.now().toIso8601String());
        if (stage == 3) {
          await prefs.setString(_keyLastMonthlyShown, DateTime.now().toIso8601String());
        }
        return true;
      }

      return false;
    } catch (e) {
      AppLogger.error('[SHARE_PROMPT] Error checking prompt logic: $e');
      return false;
    }
  }

  /// Get user's sharing frequency level
  static ShareFrequency _getFrequency(SharedPreferences prefs) {
    final totalShares = prefs.getInt(_keyTotalShares) ?? 0;

    if (totalShares == 0) {
      return ShareFrequency.majorOnly;
    } else if (totalShares < 5) {
      return ShareFrequency.moderate;
    } else {
      return ShareFrequency.active;
    }
  }

  /// Check if we're within frequency limits
  static Future<bool> _checkFrequencyLimit(
    SharedPreferences prefs,
    ShareFrequency frequency,
  ) async {
    final lastShown = prefs.getString(_keyLastPromptShown);
    if (lastShown == null) return true;

    final lastShownDate = DateTime.parse(lastShown);
    final hoursSinceLastPrompt = DateTime.now().difference(lastShownDate).inHours;

    switch (frequency) {
      case ShareFrequency.majorOnly:
        // Max once per week
        return hoursSinceLastPrompt >= 168; // 7 days
      case ShareFrequency.moderate:
        // Max twice per week (~3.5 days)
        return hoursSinceLastPrompt >= 84; // 3.5 days
      case ShareFrequency.active:
        // Max 3 times per week (~2.3 days)
        return hoursSinceLastPrompt >= 56; // 2.3 days
    }
  }

  /// Determine if session is significant enough to prompt
  static bool _isSignificantSession({
    required bool hasAchievement,
    required bool isPR,
    required int sessionNumber,
    bool? isRated5Stars,
    int? streakDays,
    required ShareFrequency frequency,
  }) {
    // Always show for achievements and PRs
    if (hasAchievement || isPR) return true;

    // 5-star sessions
    if (isRated5Stars == true) return true;

    // Milestone session numbers
    final milestones = [10, 25, 50, 100, 200, 500, 1000];
    if (milestones.contains(sessionNumber)) return true;

    // Streak milestones
    if (streakDays != null) {
      final streakMilestones = [7, 30, 100, 365];
      if (streakMilestones.contains(streakDays)) return true;
    }

    // For active sharers, show for any decent session
    if (frequency == ShareFrequency.active) {
      // Could add more logic here for "decent" sessions
      // For now, return false for regular sessions
      return false;
    }

    return false;
  }

  /// Track that a session was shared
  static Future<void> trackShare(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();

    // Add to shared sessions
    final sharedSessions = prefs.getStringList(_keySessionsShared) ?? [];
    if (!sharedSessions.contains(sessionId)) {
      sharedSessions.add(sessionId);
      // Keep only last 100 sessions to avoid unbounded growth
      if (sharedSessions.length > 100) {
        sharedSessions.removeAt(0);
      }
      await prefs.setStringList(_keySessionsShared, sharedSessions);
    }

    // Increment total shares
    final totalShares = prefs.getInt(_keyTotalShares) ?? 0;
    await prefs.setInt(_keyTotalShares, totalShares + 1);

    // Mark user as engaged so we show after every ruck going forward
    await prefs.setBool(_keyEngagedAlways, true);

    AppLogger.info('[SHARE_PROMPT] Tracked share for session $sessionId');
  }

  /// Track that a prompt was shown for a session (to prevent multiple prompts for same session)
  static Future<void> trackPromptShown(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    const String keyPromptedSessions = 'prompted_sessions';

    final promptedSessions = prefs.getStringList(keyPromptedSessions) ?? [];
    if (!promptedSessions.contains(sessionId)) {
      promptedSessions.add(sessionId);
      // Keep only last 50 sessions to avoid unbounded growth
      if (promptedSessions.length > 50) {
        promptedSessions.removeAt(0);
      }
      await prefs.setStringList(keyPromptedSessions, promptedSessions);
    }

    AppLogger.info('[SHARE_PROMPT] Tracked prompt shown for session $sessionId');
  }

  /// Record an explicit dismissal to advance the backoff stage.
  static Future<void> recordDismiss() async {
    final prefs = await SharedPreferences.getInstance();
    int stage = prefs.getInt(_keyStage) ?? 0;
    if (stage < 3) {
      stage += 1; // 0->1 (every 3rd), 1->2 (every 10th), 2->3 (monthly)
      await prefs.setInt(_keyStage, stage);
      AppLogger.info('[SHARE_PROMPT] Dismissed, advancing stage to $stage');
    } else {
      // monthly stage: update last monthly timestamp to avoid immediate re-show
      await prefs.setString(_keyLastMonthlyShown, DateTime.now().toIso8601String());
    }
  }

  /// Check if we've already shown a prompt for this session
  static Future<bool> hasPromptBeenShown(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    const String keyPromptedSessions = 'prompted_sessions';

    final promptedSessions = prefs.getStringList(keyPromptedSessions) ?? [];
    return promptedSessions.contains(sessionId);
  }

  /// Show the share prompt if appropriate
  static Future<void> maybeShowPrompt({
    required BuildContext context,
    required String sessionId,
    required double distanceKm,
    required Duration duration,
    String? achievement,
    bool isPR = false,
    int? sessionNumber,
    bool? isRated5Stars,
    int? streakDays,
  }) async {
    // Add delay before showing
    await Future.delayed(const Duration(seconds: 10));

    if (!context.mounted) return;

    final shouldShow = await shouldShowPrompt(
      sessionId: sessionId,
      distanceKm: distanceKm,
      duration: duration,
      hasAchievement: achievement != null,
      isPR: isPR,
      sessionNumber: sessionNumber ?? 0,
      isRated5Stars: isRated5Stars,
      streakDays: streakDays,
    );

    if (shouldShow && context.mounted) {
      // Track that we're showing a prompt for this session
      await trackPromptShown(sessionId);

      await QuickShareBottomSheet.show(
        context: context,
        sessionId: sessionId,
        distanceKm: distanceKm,
        duration: duration,
        achievement: achievement,
      );
    }
  }

  /// Disable share prompts
  static Future<void> disablePrompts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyPromptsDisabled, true);
    AppLogger.info('[SHARE_PROMPT] Prompts disabled');
  }

  /// Enable share prompts
  static Future<void> enablePrompts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyPromptsDisabled, false);
    AppLogger.info('[SHARE_PROMPT] Prompts enabled');
  }

  /// Check if prompts are enabled
  static Future<bool> arePromptsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_keyPromptsDisabled) ?? false);
  }

  /// Reset all prompt settings (for debugging)
  static Future<void> resetPromptSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLastPromptShown);
    await prefs.remove(_keySnoozedUntil);
    await prefs.remove(_keyDismissCount);
    await prefs.remove(_keyLastDismiss);
    AppLogger.info('[SHARE_PROMPT] Settings reset');
  }
}
