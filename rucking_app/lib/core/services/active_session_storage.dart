import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rucking_app/core/models/location_point.dart';
import 'package:rucking_app/features/ruck_session/domain/models/heart_rate_sample.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

/// Service to persist active session data locally for offline scenarios
/// Ensures GPS tracks and session data are not lost during long offline periods
class ActiveSessionStorage {
  static const String _activeSessionKey = 'active_session_data';
  static const String _lastSaveKey = 'active_session_last_save';
  static const String _offlineSessionsKey = 'offline_completed_sessions';
  final SharedPreferences _prefs;

  ActiveSessionStorage(this._prefs);

  /// Save active session data to local storage
  /// Call this every 2-3 minutes during active sessions
  Future<void> saveSessionData({
    required String sessionId,
    required List<LocationPoint> locationPoints,
    required int elapsedSeconds,
    required double distanceKm,
    required double calories,
    required double elevationGain,
    required double elevationLoss,
    required double ruckWeightKg,
    required DateTime sessionStartTime,
    List<HeartRateSample>? heartRateSamples,
    int? latestHeartRate,
    int? minHeartRate,
    int? maxHeartRate,
  }) async {
    try {
      final sessionData = {
        'session_id': sessionId,
        'location_points': locationPoints.map((point) => point.toJson()).toList(),
        'elapsed_seconds': elapsedSeconds,
        'distance_km': distanceKm,
        'calories': calories,
        'elevation_gain': elevationGain,
        'elevation_loss': elevationLoss,
        'ruck_weight_kg': ruckWeightKg,
        'session_start_time': sessionStartTime.toIso8601String(),
        'heart_rate_samples': heartRateSamples?.map((sample) => sample.toJson()).toList(),
        'latest_heart_rate': latestHeartRate,
        'min_heart_rate': minHeartRate,
        'max_heart_rate': maxHeartRate,
        'saved_at': DateTime.now().toIso8601String(),
      };

      await _prefs.setString(_activeSessionKey, jsonEncode(sessionData));
      await _prefs.setInt(_lastSaveKey, DateTime.now().millisecondsSinceEpoch);

      AppLogger.info('[SESSION_STORAGE] Saved session data: ${locationPoints.length} GPS points, ${heartRateSamples?.length ?? 0} HR samples');
    } catch (e) {
      AppLogger.error('[SESSION_STORAGE] Failed to save session data: $e');
    }
  }

  /// Save ActiveSessionRunning state directly
  Future<void> saveActiveSession(dynamic activeSessionState) async {
    try {
      // This method would need to be implemented based on your ActiveSessionRunning state structure
      // For now, calling the generic saveSessionData method
      await saveSessionData(
        sessionId: activeSessionState.sessionId,
        locationPoints: activeSessionState.locationPoints,
        elapsedSeconds: activeSessionState.elapsedSeconds,
        distanceKm: activeSessionState.distanceKm,
        calories: activeSessionState.calories,
        elevationGain: activeSessionState.elevationGain,
        elevationLoss: activeSessionState.elevationLoss,
        ruckWeightKg: activeSessionState.ruckWeightKg,
        sessionStartTime: activeSessionState.originalSessionStartTimeUtc ?? DateTime.now(),
        heartRateSamples: activeSessionState.heartRateSamples,
        latestHeartRate: activeSessionState.latestHeartRate,
        minHeartRate: activeSessionState.minHeartRate,
        maxHeartRate: activeSessionState.maxHeartRate,
      );
    } catch (e) {
      AppLogger.error('[SESSION_STORAGE] Failed to save active session: $e');
    }
  }

  /// Load saved session data for recovery
  Future<Map<String, dynamic>?> loadSessionData() async {
    try {
      final jsonString = _prefs.getString(_activeSessionKey);

      if (jsonString == null) return null;

      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      AppLogger.info('[SESSION_STORAGE] Loaded session data: ${data['session_id']}');

      return data;
    } catch (e) {
      AppLogger.error('[SESSION_STORAGE] Failed to load session data: $e');
      return null;
    }
  }

  /// Check if there's a saved session that might need recovery
  Future<bool> hasActiveSessionData() async {
    final data = await loadSessionData();
    return data != null && data['session_id'] != null;
  }

  /// Recover session and return data needed to reconstruct ActiveSessionRunning state
  Future<Map<String, dynamic>?> recoverSession() async {
    try {
      final data = await loadSessionData();
      if (data == null) return null;

      // Parse the saved data back into usable formats
      final locationPointsJson = data['location_points'] as List<dynamic>?;
      final heartRateSamplesJson = data['heart_rate_samples'] as List<dynamic>?;

      final recoveredData = {
        'session_id': data['session_id'] as String,
        'location_points': locationPointsJson?.map((json) => LocationPoint.fromJson(json as Map<String, dynamic>)).toList() ?? <LocationPoint>[],
        'elapsed_seconds': data['elapsed_seconds'] as int? ?? 0,
        'distance_km': (data['distance_km'] as num?)?.toDouble() ?? 0.0,
        'calories': (data['calories'] as num?)?.toDouble() ?? 0.0,
        'elevation_gain': (data['elevation_gain'] as num?)?.toDouble() ?? 0.0,
        'elevation_loss': (data['elevation_loss'] as num?)?.toDouble() ?? 0.0,
        'ruck_weight_kg': (data['ruck_weight_kg'] as num?)?.toDouble() ?? 0.0,
        'session_start_time': DateTime.parse(data['session_start_time'] as String),
        'heart_rate_samples': heartRateSamplesJson?.map((json) => HeartRateSample.fromJson(json as Map<String, dynamic>)).toList() ?? <HeartRateSample>[],
        'latest_heart_rate': data['latest_heart_rate'] as int?,
        'min_heart_rate': data['min_heart_rate'] as int?,
        'max_heart_rate': data['max_heart_rate'] as int?,
        'saved_at': DateTime.parse(data['last_persisted_at'] as String),
      };

      AppLogger.info('[SESSION_RECOVERY] Recovered session: ${recoveredData['session_id']}, ${(recoveredData['location_points'] as List).length} GPS points');
      
      return recoveredData;
    } catch (e) {
      AppLogger.error('[SESSION_RECOVERY] Failed to recover session: $e');
      return null;
    }
  }

  /// Check if a session should be recovered (not too old)
  Future<bool> shouldRecoverSession() async {
    try {
      final lastSave = await getLastSaveTime();
      if (lastSave == null) return false;

      // Only recover sessions saved within the last 6 hours
      // This prevents recovering very old sessions that are likely abandoned
      final timeSinceLastSave = DateTime.now().difference(lastSave);
      final shouldRecover = timeSinceLastSave.inHours < 6;

      AppLogger.info('[SESSION_RECOVERY] Last save: $lastSave, Time since: ${timeSinceLastSave.inMinutes} mins, Should recover: $shouldRecover');
      
      return shouldRecover;
    } catch (e) {
      AppLogger.error('[SESSION_RECOVERY] Failed to check recovery eligibility: $e');
      return false;
    }
  }

  /// Clear saved session data after successful upload
  Future<void> clearSessionData() async {
    try {
      await _prefs.remove(_activeSessionKey);
      await _prefs.remove(_lastSaveKey);

      AppLogger.info('[SESSION_STORAGE] Cleared saved session data');
    } catch (e) {
      AppLogger.error('[SESSION_STORAGE] Failed to clear session data: $e');
    }
  }

  /// Get the last save timestamp
  Future<DateTime?> getLastSaveTime() async {
    try {
      final timestamp = _prefs.getInt(_lastSaveKey);

      if (timestamp == null) return null;

      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    } catch (e) {
      return null;
    }
  }

  /// Save a completed offline session for later sync
  Future<void> saveCompletedOfflineSession(dynamic activeSessionState, Map<String, dynamic> completionPayload) async {
    try {
      final offlineSessionData = {
        'offlineSessionId': activeSessionState.sessionId,
        'completedAt': DateTime.now().toIso8601String(),
        'ruckWeightKg': activeSessionState.ruckWeightKg,
        'notes': activeSessionState.notes ?? '',
        'originalSessionStartTimeUtc': activeSessionState.originalSessionStartTimeUtc.toIso8601String(),
        'completionPayload': completionPayload,
        'synced': false,
      };

      // Get existing offline sessions
      final existingSessionsJson = _prefs.getString(_offlineSessionsKey);
      List<Map<String, dynamic>> offlineSessions = [];
      
      if (existingSessionsJson != null) {
        final decoded = jsonDecode(existingSessionsJson) as List<dynamic>;
        offlineSessions = decoded.cast<Map<String, dynamic>>();
      }

      // Add the new session
      offlineSessions.add(offlineSessionData);

      // Save back to storage
      await _prefs.setString(_offlineSessionsKey, jsonEncode(offlineSessions));
      
      AppLogger.info('[OFFLINE_STORAGE] Saved offline session: ${activeSessionState.sessionId}');
    } catch (e) {
      AppLogger.error('[OFFLINE_STORAGE] Failed to save offline session', exception: e);
    }
  }

  /// Get all completed offline sessions that need to be synced
  Future<List<Map<String, dynamic>>> getCompletedOfflineSessions() async {
    try {
      final existingSessionsJson = _prefs.getString(_offlineSessionsKey);
      if (existingSessionsJson == null) return [];

      final decoded = jsonDecode(existingSessionsJson) as List<dynamic>;
      final offlineSessions = decoded.cast<Map<String, dynamic>>();

      // Return only unsynced sessions
      return offlineSessions.where((session) => session['synced'] != true).toList();
    } catch (e) {
      AppLogger.error('[OFFLINE_STORAGE] Failed to get offline sessions', exception: e);
      return [];
    }
  }

  /// Mark an offline session as synced
  Future<void> markOfflineSessionSynced(String offlineSessionId) async {
    try {
      final existingSessionsJson = _prefs.getString(_offlineSessionsKey);
      if (existingSessionsJson == null) return;

      final decoded = jsonDecode(existingSessionsJson) as List<dynamic>;
      final offlineSessions = decoded.cast<Map<String, dynamic>>();

      // Find and mark the session as synced
      for (final session in offlineSessions) {
        if (session['offlineSessionId'] == offlineSessionId) {
          session['synced'] = true;
          session['syncedAt'] = DateTime.now().toIso8601String();
          break;
        }
      }

      // Save back to storage
      await _prefs.setString(_offlineSessionsKey, jsonEncode(offlineSessions));
      
      AppLogger.info('[OFFLINE_STORAGE] Marked session as synced: $offlineSessionId');
    } catch (e) {
      AppLogger.error('[OFFLINE_STORAGE] Failed to mark session as synced', exception: e);
    }
  }

  /// Clean up synced offline sessions (remove old ones)
  Future<void> cleanupSyncedOfflineSessions() async {
    try {
      final existingSessionsJson = _prefs.getString(_offlineSessionsKey);
      if (existingSessionsJson == null) return;

      final decoded = jsonDecode(existingSessionsJson) as List<dynamic>;
      final offlineSessions = decoded.cast<Map<String, dynamic>>();

      // Keep only unsynced sessions and recently synced ones (last 7 days)
      final now = DateTime.now();
      final keepSessions = offlineSessions.where((session) {
        if (session['synced'] != true) return true; // Keep unsynced
        
        final syncedAtStr = session['syncedAt'] as String?;
        if (syncedAtStr == null) return false;
        
        final syncedAt = DateTime.parse(syncedAtStr);
        final daysSinceSync = now.difference(syncedAt).inDays;
        return daysSinceSync < 7; // Keep recently synced sessions for 7 days
      }).toList();

      // Save cleaned up list
      await _prefs.setString(_offlineSessionsKey, jsonEncode(keepSessions));
      
      final removedCount = offlineSessions.length - keepSessions.length;
      if (removedCount > 0) {
        AppLogger.info('[OFFLINE_STORAGE] Cleaned up $removedCount old synced sessions');
      }
    } catch (e) {
      AppLogger.error('[OFFLINE_STORAGE] Failed to cleanup synced sessions', exception: e);
    }
  }
}
