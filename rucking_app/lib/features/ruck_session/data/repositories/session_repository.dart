import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

/// Repository class for session-related operations
class SessionRepository {
  final ApiClient _apiClient;
  
  const SessionRepository({required ApiClient apiClient})
      : _apiClient = apiClient;
  
  /// Delete a ruck session by its ID
  /// 
  /// Returns true if the deletion was successful, false otherwise
  Future<bool> deleteSession(String sessionId) async {
    try {
      AppLogger.info('Deleting session with ID: $sessionId');
      
      // Call the Supabase RPC function to delete the session
      // This handles the cascade deletion of associated records
      final response = await _apiClient.post(
        '/rpc/delete_user_ruck_session',
        body: {'session_id': sessionId},
      );
      
      // Check if the deletion was successful
      // The RPC function should return a success flag
      if (response != null && response['success'] == true) {
        AppLogger.info('Successfully deleted session: $sessionId');
        return true;
      }
      
      // Alternative implementation if using direct DELETE operation:
      // final response = await _apiClient.delete('/rucks/$sessionId');
      // return response != null; // Success if response is not null
      
      AppLogger.warning('Failed to delete session: $sessionId. Response: $response');
      return false;
    } catch (e) {
      AppLogger.error('Error deleting session: $e');
      return false;
    }
  }
}
