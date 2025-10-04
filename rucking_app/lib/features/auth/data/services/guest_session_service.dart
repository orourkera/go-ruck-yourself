import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/services/api_client.dart';

/// Service for managing guest mode sessions and migrating them on signup
class GuestSessionService {
  static const String _guestSessionsKey = 'guest_sessions';
  static const String _guestSessionCountKey = 'guest_session_count';

  /// Save a guest session to local storage
  static Future<void> saveGuestSession(Map<String, dynamic> sessionData) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Get existing guest sessions
      final sessionsJson = prefs.getString(_guestSessionsKey) ?? '[]';
      final List<dynamic> sessions = jsonDecode(sessionsJson);

      // Add new session
      sessions.add(sessionData);

      // Save back to storage
      await prefs.setString(_guestSessionsKey, jsonEncode(sessions));

      // Update count
      await prefs.setInt(_guestSessionCountKey, sessions.length);

      AppLogger.info('[GUEST_SESSION] Saved guest session. Total: ${sessions.length}');
    } catch (e) {
      AppLogger.error('[GUEST_SESSION] Error saving guest session: $e');
    }
  }

  /// Get all guest sessions
  static Future<List<Map<String, dynamic>>> getGuestSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionsJson = prefs.getString(_guestSessionsKey) ?? '[]';
      final List<dynamic> sessions = jsonDecode(sessionsJson);
      return sessions.cast<Map<String, dynamic>>();
    } catch (e) {
      AppLogger.error('[GUEST_SESSION] Error getting guest sessions: $e');
      return [];
    }
  }

  /// Get count of guest sessions
  static Future<int> getGuestSessionCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_guestSessionCountKey) ?? 0;
    } catch (e) {
      AppLogger.error('[GUEST_SESSION] Error getting guest session count: $e');
      return 0;
    }
  }

  /// Clear all guest sessions (after migration or on user request)
  static Future<void> clearGuestSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_guestSessionsKey);
      await prefs.remove(_guestSessionCountKey);
      AppLogger.info('[GUEST_SESSION] Cleared all guest sessions');
    } catch (e) {
      AppLogger.error('[GUEST_SESSION] Error clearing guest sessions: $e');
    }
  }

  /// Migrate guest sessions to the backend after user signs up
  static Future<bool> migrateGuestSessions(ApiClient apiClient) async {
    try {
      final sessions = await getGuestSessions();

      if (sessions.isEmpty) {
        AppLogger.info('[GUEST_SESSION] No guest sessions to migrate');
        return true;
      }

      AppLogger.info('[GUEST_SESSION] Migrating ${sessions.length} guest sessions');

      int successCount = 0;
      int failCount = 0;

      for (final session in sessions) {
        try {
          // POST session to backend
          await apiClient.post('/rucks', session);
          successCount++;
        } catch (e) {
          AppLogger.error('[GUEST_SESSION] Failed to migrate session: $e');
          failCount++;
        }
      }

      AppLogger.info(
        '[GUEST_SESSION] Migration complete: $successCount succeeded, $failCount failed',
      );

      // Clear guest sessions after successful migration (even if some failed)
      if (successCount > 0) {
        await clearGuestSessions();
      }

      return failCount == 0;
    } catch (e) {
      AppLogger.error('[GUEST_SESSION] Error migrating guest sessions: $e');
      return false;
    }
  }

  /// Check if user is in guest mode
  static Future<bool> isGuestMode() async {
    final count = await getGuestSessionCount();
    return count > 0;
  }
}
