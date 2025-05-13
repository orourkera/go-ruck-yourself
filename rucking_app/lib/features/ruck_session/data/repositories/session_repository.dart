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
      AppLogger.info('DEBUGGING: Fetching session with ID: $sessionId');
      if (sessionId.isEmpty) {
        AppLogger.error('Session ID is empty');
        return null;
      }
      final response = await _apiClient.get('/rucks/$sessionId');
      AppLogger.info('DEBUGGING: Raw session response keys: ${response?.keys.toList()}');
      
      if (response == null) {
        AppLogger.error('No response from backend for session $sessionId');
        return null;
      }
      // Parse RuckSession
      final session = RuckSession.fromJson(response);
      AppLogger.info('DEBUGGING: Parsed session ${session.id} with start time ${session.startTime}');
      
      // Check if there are heart rate samples and parse them
      List<HeartRateSample> heartRateSamples = [];
      if (response.containsKey('heart_rate_samples') && response['heart_rate_samples'] != null) {
        var hrSamples = response['heart_rate_samples'] as List;
        AppLogger.info('DEBUGGING: Found ${hrSamples.length} raw heart rate samples in response');
        
        heartRateSamples = hrSamples
            .map((e) => HeartRateSample.fromJson(e as Map<String, dynamic>))
            .toList();
        AppLogger.info('DEBUGGING: Successfully parsed ${heartRateSamples.length} heart rate samples');
        
        // Add sample timestamps debug
        if (heartRateSamples.isNotEmpty) {
          AppLogger.info('DEBUGGING: First sample: ${heartRateSamples.first.timestamp}, bpm: ${heartRateSamples.first.bpm}');
          AppLogger.info('DEBUGGING: Last sample: ${heartRateSamples.last.timestamp}, bpm: ${heartRateSamples.last.bpm}');
        }
      } else {
        AppLogger.info('DEBUGGING: No heart_rate_samples field in session response');
      }
      // Return a session with samples attached
      final resultSession = session.copyWith(heartRateSamples: heartRateSamples);
      AppLogger.info('DEBUGGING: Returning session with ${resultSession.heartRateSamples?.length ?? 0} heart rate samples');
      return resultSession;
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
