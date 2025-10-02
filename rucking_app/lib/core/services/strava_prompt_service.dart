import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_logger.dart';
import 'strava_service.dart';

class StravaPromptService {
  static const String _lastPromptKey = 'strava_prompt_last_shown';
  static const String _promptCountKey = 'strava_prompt_count';
  static const String _dismissCountKey = 'strava_prompt_dismiss_count';
  static const String _permanentlyDismissedKey = 'strava_prompt_permanently_dismissed';

  // Exponential backoff schedule (in days)
  // 1st prompt: after 3 sessions
  // 2nd prompt: 3 days later
  // 3rd prompt: 7 days later
  // 4th prompt: 14 days later
  // 5th prompt: 30 days later
  // 6th+: 60 days later
  static const List<int> _backoffDays = [0, 3, 7, 14, 30, 60];

  final StravaService _stravaService = StravaService();

  /// Check if we should show the Strava prompt
  Future<bool> shouldShowPrompt({int? sessionCount}) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Check if permanently dismissed
      if (prefs.getBool(_permanentlyDismissedKey) ?? false) {
        return false;
      }

      // Check if already connected to Strava
      try {
        final status = await _stravaService.getConnectionStatus();
        if (status.connected) {
          AppLogger.info('[STRAVA_PROMPT] User already connected to Strava, not showing prompt');
          return false;
        }
      } catch (e) {
        AppLogger.error('[STRAVA_PROMPT] Error checking connection status: $e');
        // If we can't check connection status (API error), assume connected to be safe
        // Better to not show prompt than to spam a connected user
        return false;
      }

      // Get prompt history
      final promptCount = prefs.getInt(_promptCountKey) ?? 0;
      final lastPromptTimestamp = prefs.getInt(_lastPromptKey) ?? 0;
      final dismissCount = prefs.getInt(_dismissCountKey) ?? 0;

      // If user has dismissed 5+ times, stop prompting
      if (dismissCount >= 5) {
        await prefs.setBool(_permanentlyDismissedKey, true);
        return false;
      }

      // First prompt: show after 3 sessions
      if (promptCount == 0) {
        // If sessionCount provided, use it; otherwise check if enough time has passed
        if (sessionCount != null) {
          return sessionCount >= 3;
        } else {
          // Fallback: show after 3 days from account creation
          return true;
        }
      }

      // Subsequent prompts: use exponential backoff
      final lastPromptDate = DateTime.fromMillisecondsSinceEpoch(lastPromptTimestamp);
      final daysSinceLastPrompt = DateTime.now().difference(lastPromptDate).inDays;

      // Get the appropriate backoff period
      final backoffIndex = promptCount >= _backoffDays.length ? _backoffDays.length - 1 : promptCount;
      final requiredDays = _backoffDays[backoffIndex];

      return daysSinceLastPrompt >= requiredDays;
    } catch (e) {
      AppLogger.error('[STRAVA_PROMPT] Error checking prompt eligibility: $e');
      return false;
    }
  }

  /// Record that the prompt was shown
  Future<void> recordPromptShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentCount = prefs.getInt(_promptCountKey) ?? 0;

      await prefs.setInt(_promptCountKey, currentCount + 1);
      await prefs.setInt(_lastPromptKey, DateTime.now().millisecondsSinceEpoch);

      AppLogger.info('[STRAVA_PROMPT] Recorded prompt shown. Count: ${currentCount + 1}');
    } catch (e) {
      AppLogger.error('[STRAVA_PROMPT] Error recording prompt shown: $e');
    }
  }

  /// Record that the user dismissed the prompt
  Future<void> recordPromptDismissed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentCount = prefs.getInt(_dismissCountKey) ?? 0;

      await prefs.setInt(_dismissCountKey, currentCount + 1);

      AppLogger.info('[STRAVA_PROMPT] Recorded prompt dismissed. Count: ${currentCount + 1}');

      // Check if we should permanently stop prompting
      if (currentCount + 1 >= 5) {
        await prefs.setBool(_permanentlyDismissedKey, true);
        AppLogger.info('[STRAVA_PROMPT] User dismissed 5 times. Permanently disabled.');
      }
    } catch (e) {
      AppLogger.error('[STRAVA_PROMPT] Error recording prompt dismissed: $e');
    }
  }

  /// Record that the user clicked "Connect"
  Future<void> recordPromptAccepted() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Reset dismiss count since they showed interest
      await prefs.setInt(_dismissCountKey, 0);

      AppLogger.info('[STRAVA_PROMPT] Recorded prompt accepted');
    } catch (e) {
      AppLogger.error('[STRAVA_PROMPT] Error recording prompt accepted: $e');
    }
  }

  /// Reset all prompt data (useful for testing)
  Future<void> resetPromptData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastPromptKey);
      await prefs.remove(_promptCountKey);
      await prefs.remove(_dismissCountKey);
      await prefs.remove(_permanentlyDismissedKey);

      AppLogger.info('[STRAVA_PROMPT] Reset all prompt data');
    } catch (e) {
      AppLogger.error('[STRAVA_PROMPT] Error resetting prompt data: $e');
    }
  }

  /// Get prompt statistics (for debugging)
  Future<Map<String, dynamic>> getPromptStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      return {
        'prompt_count': prefs.getInt(_promptCountKey) ?? 0,
        'dismiss_count': prefs.getInt(_dismissCountKey) ?? 0,
        'permanently_dismissed': prefs.getBool(_permanentlyDismissedKey) ?? false,
        'last_prompt': prefs.getInt(_lastPromptKey) != null
            ? DateTime.fromMillisecondsSinceEpoch(prefs.getInt(_lastPromptKey)!).toIso8601String()
            : 'never',
        'next_backoff_days': _getNextBackoffDays(prefs.getInt(_promptCountKey) ?? 0),
      };
    } catch (e) {
      AppLogger.error('[STRAVA_PROMPT] Error getting prompt stats: $e');
      return {};
    }
  }

  int _getNextBackoffDays(int promptCount) {
    if (promptCount >= _backoffDays.length) {
      return _backoffDays.last;
    }
    return _backoffDays[promptCount];
  }
}