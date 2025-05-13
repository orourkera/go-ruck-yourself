import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_session.dart';
import 'package:rucking_app/features/ruck_session/domain/models/heart_rate_sample.dart';

/// Repository class for session-related operations
class SessionRepository {
  final ApiClient _apiClient;
  
  const SessionRepository({required ApiClient apiClient})
      : _apiClient = apiClient;

  /// Fetch a ruck session by its ID, including all heart rate samples.
  Future<RuckSession?> fetchSessionById(String sessionId) async {
    try {
      AppLogger.info('Fetching session with ID: $sessionId');
      if (sessionId.isEmpty) {
        AppLogger.error('Session ID is empty');
        return null;
      }
      final response = await _apiClient.get('/rucks/$sessionId');
      if (response == null) {
        AppLogger.error('No response from backend for session $sessionId');
        return null;
      }
      // Parse RuckSession
      final session = RuckSession.fromJson(response as Map<String, dynamic>);
      // Parse heart rate samples if present
      List<HeartRateSample> heartRateSamples = [];
      if (response['heart_rate_samples'] != null) {
        heartRateSamples = (response['heart_rate_samples'] as List)
            .map((e) => HeartRateSample.fromJson(e as Map<String, dynamic>))
            .toList();
        AppLogger.info('Received ${heartRateSamples.length} heart rate samples for session $sessionId');
      }
      // Return a session with samples attached (assumes RuckSession has a field for this)
      return session.copyWith(heartRateSamples: heartRateSamples);
    } catch (e) {
      AppLogger.error('Error fetching session: $e');
      return null;
    }
  }
  
  /// Delete a ruck session by its ID
  /// 
  /// Returns true if the deletion was successful, false otherwise
  Future<bool> deleteSession(String sessionId) async {
    try {
      AppLogger.info('Deleting session with ID: $sessionId');
      
      // Verify sessionId is not empty
      if (sessionId.isEmpty) {
        AppLogger.error('Session ID is empty');
        return false;
      }
      
      // Use direct DELETE operation with the correct endpoint pattern
      final response = await _apiClient.delete('/rucks/$sessionId');
      
      // The API returns the response data directly, not a Response object
      // If we get here without an exception, the deletion was successful
      AppLogger.info('Successfully deleted session: $sessionId. Response: $response');
      return true;
    } catch (e) {
      AppLogger.error('Error deleting session: $e');
      return false;
    }
  }
}
