import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'firebase_messaging_service.dart';

/// Service to recover sessions that were saved locally but failed to upload to server
class SessionRecoveryService {
  static const String _backupKeyPrefix = 'backup_session_';
  
  /// Check for any saved sessions and attempt to upload them to server
  static Future<void> recoverSavedSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();
      
      // Find all backup session keys
      final backupKeys = allKeys.where((key) => key.startsWith(_backupKeyPrefix)).toList();
      
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
          
          final sessionData = jsonDecode(sessionDataJson) as Map<String, dynamic>;
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
          
          // Attempt to upload to server
          await apiClient.patch('/rucks/$ruckId', completionData);
          
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
        AppLogger.info('✅ Successfully recovered $successCount out of ${backupKeys.length} sessions');
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
      
      final backupKeys = allKeys.where((key) => key.startsWith(_backupKeyPrefix)).toList();
      final sessions = <Map<String, dynamic>>[];
      
      for (final key in backupKeys) {
        try {
          final sessionDataJson = prefs.getString(key);
          if (sessionDataJson != null) {
            final sessionData = jsonDecode(sessionDataJson) as Map<String, dynamic>;
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
      
      final backupKeys = allKeys.where((key) => key.startsWith(_backupKeyPrefix)).toList();
      
      for (final key in backupKeys) {
        await prefs.remove(key);
      }
      
      AppLogger.info('🗑️ Cleared ${backupKeys.length} saved session backups');
    } catch (e) {
      AppLogger.error('Error clearing saved sessions: $e');
    }
  }

  /// Check for inactive sessions and optionally auto-end them
  static Future<Map<String, dynamic>> checkInactiveSessions({
    int inactivityMinutes = 30,
    bool autoEnd = false,
  }) async {
    try {
      final apiClient = GetIt.instance<ApiClient>();
      
      final response = await apiClient.post('/rucks/auto-end', {
        'inactivity_minutes': inactivityMinutes,
        'auto_end': autoEnd,
      });
      
      final data = response.data as Map<String, dynamic>;
      final inactiveSessions = data['inactive_sessions'] as List<dynamic>? ?? [];
      final endedSessions = data['ended_sessions'] as List<dynamic>? ?? [];
      
      AppLogger.info('Found ${inactiveSessions.length} inactive sessions, ended ${endedSessions.length}');
      
      return {
        'inactive_sessions': inactiveSessions,
        'ended_sessions': endedSessions,
        'threshold_minutes': data['threshold_minutes'],
      };
    } catch (e) {
      AppLogger.error('Error checking inactive sessions: $e');
      return {
        'inactive_sessions': [],
        'ended_sessions': [],
        'threshold_minutes': inactivityMinutes,
      };
    }
  }

  /// Send notification for inactive sessions
  static Future<void> notifyInactiveSessions({
    int inactivityMinutes = 30,
  }) async {
    try {
      final result = await checkInactiveSessions(
        inactivityMinutes: inactivityMinutes,
        autoEnd: false, // Just check, don't auto-end
      );
      
      final inactiveSessions = result['inactive_sessions'] as List<dynamic>;
      
      if (inactiveSessions.isNotEmpty) {
        final messagingService = GetIt.instance<FirebaseMessagingService>();
        
        for (final session in inactiveSessions) {
          final sessionMap = session as Map<String, dynamic>;
          final sessionId = sessionMap['id'];
          final inactiveMinutes = (sessionMap['inactive_minutes'] as double).round();
          
          await messagingService.showNotification(
            id: sessionId is int ? sessionId : sessionId.hashCode,
            title: 'Inactive Ruck Session',
            body: 'Your ruck has been inactive for $inactiveMinutes minutes. Did you forget to end it?',
            payload: 'inactive_session:$sessionId',
          );
        }
        
        AppLogger.info('Sent notifications for ${inactiveSessions.length} inactive sessions');
      }
    } catch (e) {
      AppLogger.error('Error sending inactive session notifications: $e');
    }
  }

  /// Start periodic background checking for inactive sessions
  static Timer? _inactivityTimer;
  
  static void startInactivityMonitoring({
    Duration checkInterval = const Duration(minutes: 10),
    int inactivityThreshold = 30,
  }) {
    stopInactivityMonitoring(); // Stop any existing timer
    
    _inactivityTimer = Timer.periodic(checkInterval, (timer) async {
      try {
        await notifyInactiveSessions(inactivityMinutes: inactivityThreshold);
      } catch (e) {
        AppLogger.error('Error in periodic inactivity check: $e');
      }
    });
    
    AppLogger.info('Started inactivity monitoring (check every ${checkInterval.inMinutes} min, threshold: $inactivityThreshold min)');
  }
  
  static void stopInactivityMonitoring() {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    AppLogger.info('Stopped inactivity monitoring');
  }
}
