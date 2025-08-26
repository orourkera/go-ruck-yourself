import 'dart:convert';
import 'package:get_it/get_it.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/app_logger.dart';
import '../utils/measurement_utils.dart';
import 'api_client.dart';

class StravaConnectionStatus {
  final bool connected;
  final String? athleteId;
  final DateTime? connectedAt;

  StravaConnectionStatus({
    required this.connected,
    this.athleteId,
    this.connectedAt,
  });

  factory StravaConnectionStatus.fromJson(Map<String, dynamic> json) {
    return StravaConnectionStatus(
      connected: json['connected'] ?? false,
      athleteId: json['athlete_id']?.toString(),
      connectedAt: json['connected_at'] != null 
          ? DateTime.tryParse(json['connected_at']) 
          : null,
    );
  }
}

class StravaService {
  final ApiClient _apiClient = GetIt.instance<ApiClient>();

  /// Get current Strava connection status
  Future<StravaConnectionStatus> getConnectionStatus() async {
    try {
      final response = await _apiClient.get('/auth/strava/status');
      return StravaConnectionStatus.fromJson(response);
    } catch (e) {
      AppLogger.error('[STRAVA] Failed to get connection status: $e');
      return StravaConnectionStatus(connected: false);
    }
  }

  /// Initiate Strava OAuth connection
  Future<bool> connectToStrava() async {
    try {
      AppLogger.info('[STRAVA] Initiating connection...');
      
      // Get OAuth URL from backend
      final response = await _apiClient.post('/auth/strava/connect', {});
      final oauthUrl = response['oauth_url'] as String?;
      
      if (oauthUrl == null) {
        AppLogger.error('[STRAVA] No OAuth URL received');
        return false;
      }

      AppLogger.info('[STRAVA] Opening OAuth URL: $oauthUrl');
      
      // Launch OAuth URL in browser
      final uri = Uri.parse(oauthUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        return true;
      } else {
        AppLogger.error('[STRAVA] Cannot launch OAuth URL');
        return false;
      }
    } catch (e) {
      AppLogger.error('[STRAVA] Failed to connect: $e');
      return false;
    }
  }

  /// Disconnect from Strava
  Future<bool> disconnect() async {
    try {
      AppLogger.info('[STRAVA] Disconnecting...');
      
      await _apiClient.post('/auth/strava/disconnect', {});
      
      AppLogger.info('[STRAVA] Successfully disconnected');
      return true;
    } catch (e) {
      AppLogger.error('[STRAVA] Failed to disconnect: $e');
      return false;
    }
  }

  /// Export a ruck session to Strava
  Future<bool> exportRuckSession({
    required String sessionId,
    required String sessionName,
    required double ruckWeightKg,
    required Duration duration,
    required double distanceMeters,
    String? description,
  }) async {
    try {
      AppLogger.info('[STRAVA] Exporting session $sessionId to Strava...');
      
      // Check if connected first
      final status = await getConnectionStatus();
      if (!status.connected) {
        AppLogger.warning('[STRAVA] Not connected - cannot export');
        return false;
      }

      // Export session via backend
      final response = await _apiClient.post('/rucks/$sessionId/export/strava', {
        'session_name': sessionName,
        'ruck_weight_kg': ruckWeightKg,
        'duration_seconds': duration.inSeconds,
        'distance_meters': distanceMeters,
        'description': description,
      });
      
      final success = response['success'] ?? false;
      if (success) {
        AppLogger.info('[STRAVA] Successfully exported session to Strava');
        final activityId = response['activity_id'];
        if (activityId != null) {
          AppLogger.info('[STRAVA] Created Strava activity: $activityId');
        }
      } else {
        AppLogger.warning('[STRAVA] Export failed: ${response['message']}');
      }
      
      return success;
    } catch (e) {
      AppLogger.error('[STRAVA] Failed to export session: $e');
      return false;
    }
  }

  /// Format ruck session name for Strava
  String formatSessionName({
    required double ruckWeightKg,
    required double distanceKm,
    required Duration duration,
    required bool preferMetric,
  }) {
    final weightStr = MeasurementUtils.formatWeight(ruckWeightKg, metric: preferMetric);
    final distanceStr = MeasurementUtils.formatDistance(distanceKm, metric: preferMetric);
    final durationStr = _formatDuration(duration);
    
    return 'Ruck - $weightStr • $distanceStr • $durationStr';
  }

  /// Format ruck session description for Strava
  String formatSessionDescription({
    required double ruckWeightKg,
    required double distanceKm,
    required Duration duration,
    required bool preferMetric,
    int? calories,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('🎒 Ruck Session');
    buffer.writeln('📏 Distance: ${MeasurementUtils.formatDistance(distanceKm, metric: preferMetric)}');
    
    if (ruckWeightKg > 0) {
      buffer.writeln('⚖️ Ruck Weight: ${MeasurementUtils.formatWeight(ruckWeightKg, metric: preferMetric)}');
    }
    
    buffer.writeln('⏱️ Duration: ${_formatDuration(duration)}');
    
    if (calories != null) {
      buffer.writeln('🔥 Estimated Calories: $calories');
    }
    
    buffer.writeln();
    buffer.writeln("Tracked with Ruck! The world's #1 rucking app for iOS and Android.");
    
    return buffer.toString();
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }
}
