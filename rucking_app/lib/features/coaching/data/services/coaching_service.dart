import 'dart:convert';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/coaching/domain/models/plan_personalization.dart';

class CoachingService {
  final ApiClient _apiClient;

  CoachingService(this._apiClient);

  // Template ID mapping no longer needed - we send plan IDs directly

  /// Create a new personalized coaching plan
  Future<Map<String, dynamic>> createCoachingPlan({
    required String basePlanId,
    required String coachingPersonality,
    required PlanPersonalization personalization,
  }) async {
    try {
      final responseData = await _apiClient.post(
        '/coaching-plans',  // Correct endpoint
        {
          'base_plan_id': basePlanId,  // Use the plan type ID directly
          'coaching_personality': coachingPersonality,  // Match backend field name
          'personalization': personalization.toJson(),  // Include all personalization data!
        },
      );

      // Handle both direct response and wrapped response formats
      if (responseData is Map<String, dynamic>) {
        if (responseData.containsKey('success') &&
            responseData['success'] == true) {
          return responseData['data'];
        } else if (responseData.containsKey('success') &&
            responseData['success'] == false) {
          throw Exception(
              responseData['message'] ?? 'Failed to create coaching plan');
        } else {
          // Direct response format
          return responseData;
        }
      } else {
        throw Exception('Unexpected response format: $responseData');
      }
    } catch (e) {
      throw Exception('Failed to create coaching plan: $e');
    }
  }

  /// Get active coaching plan for the current user
  Future<Map<String, dynamic>?> getActiveCoachingPlan() async {
    try {
      final responseData = await _apiClient.get('/user-coaching-plans');
      AppLogger.info('[COACHING_SERVICE] API response: $responseData');

      // API returns {"active_plan": null} or {"active_plan": {...}}
      if (responseData != null && responseData is Map<String, dynamic>) {
        final activePlan = responseData['active_plan'];
        AppLogger.info('[COACHING_SERVICE] Active plan extracted: ${activePlan != null ? "EXISTS" : "NULL"}');
        return activePlan as Map<String, dynamic>?;
      }

      AppLogger.info('[COACHING_SERVICE] Invalid response format, returning null');
      return null;
    } catch (e) {
      AppLogger.error('[COACHING_SERVICE] Error fetching plan: $e');
      throw Exception('Failed to fetch active coaching plan: $e');
    }
  }

  /// Get detailed progress for the current user's active plan
  Future<Map<String, dynamic>> getCoachingPlanProgress() async {
    try {
      final responseData = await _apiClient.get('/user-coaching-plan-progress');
      return responseData;
    } catch (e) {
      throw Exception('Failed to fetch coaching plan progress: $e');
    }
  }

  /// Track session completion against the coaching plan
  Future<Map<String, dynamic>> trackSessionCompletion(int sessionId) async {
    try {
      final responseData = await _apiClient.post(
        '/plan-session-tracking',
        {'session_id': sessionId},
      );
      return responseData;
    } catch (e) {
      throw Exception('Failed to track session completion: $e');
    }
  }
}
