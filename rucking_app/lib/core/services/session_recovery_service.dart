import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

/// Service to recover sessions that were saved locally but failed to upload to server
class SessionRecoveryService {
  static const String _backupKeyPrefix = 'backup_session_';

  /// Check for any saved sessions and attempt to upload them to server
  static Future<void> recoverSavedSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();

      // Find all backup session keys
      final backupKeys =
          allKeys.where((key) => key.startsWith(_backupKeyPrefix)).toList();

      if (backupKeys.isEmpty) {
        AppLogger.info('🔄 No sessions to recover');
        return;
      }

      AppLogger.info('🔄 Found ${backupKeys.length} sessions to recover');

      final apiClient = GetIt.instance<ApiClient>();
      int successCount = 0;

      for (final key in backupKeys) {
        try {
          final sessionDataJson = prefs.getString(key);
          if (sessionDataJson == null) continue;

          final sessionData =
              jsonDecode(sessionDataJson) as Map<String, dynamic>;
          final ruckId = sessionData['ruckId'] as String;

          AppLogger.info('🔄 Attempting to recover session $ruckId');

          // Prepare completion data for server
          final completionData = {
            'rating': sessionData['rating'],
            'perceived_exertion': sessionData['perceivedExertion'],
            'completed': true,
            'notes': sessionData['notes'] ?? '',
            'distance_km': sessionData['distance'],
            'calories_burned': sessionData['caloriesBurned'],
            'elevation_gain_m': sessionData['elevationGain'],
            'elevation_loss_m': sessionData['elevationLoss'],
          };

          // Include splits if available
          if (sessionData['splits'] != null) {
            completionData['splits'] = sessionData['splits'];
          }

          // Attempt to upload to server via completion endpoint
          await apiClient.post('/rucks/$ruckId/complete', completionData);

          // Success! Remove the backup
          await prefs.remove(key);
          successCount++;

          AppLogger.info('✅ Successfully recovered session $ruckId');
        } catch (e) {
          AppLogger.warning('⚠️ Failed to recover session from key $key: $e');
          // Keep the backup for next app startup
        }
      }

      if (successCount > 0) {
        AppLogger.info(
            '✅ Successfully recovered $successCount out of ${backupKeys.length} sessions');
      }
    } catch (e) {
      AppLogger.error('❌ Error during session recovery: $e');
    }
  }

  /// Get list of all sessions currently saved locally as backup
  static Future<List<Map<String, dynamic>>> getSavedSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();

      final backupKeys =
          allKeys.where((key) => key.startsWith(_backupKeyPrefix)).toList();
      final sessions = <Map<String, dynamic>>[];

      for (final key in backupKeys) {
        try {
          final sessionDataJson = prefs.getString(key);
          if (sessionDataJson != null) {
            final sessionData =
                jsonDecode(sessionDataJson) as Map<String, dynamic>;
            sessions.add(sessionData);
          }
        } catch (e) {
          AppLogger.warning('Failed to parse saved session $key: $e');
        }
      }

      return sessions;
    } catch (e) {
      AppLogger.error('Error getting saved sessions: $e');
      return [];
    }
  }

  /// Manually clear all saved session backups (for debugging)
  static Future<void> clearAllSavedSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();

      final backupKeys =
          allKeys.where((key) => key.startsWith(_backupKeyPrefix)).toList();

      for (final key in backupKeys) {
        await prefs.remove(key);
      }
      AppLogger.info(' Cleared ${backupKeys.length} saved session backups');
    } catch (e) {
      AppLogger.error('Error clearing saved sessions: $e');
    }
  }
}
