import 'dart:convert';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/features/coaching/domain/models/plan_personalization.dart';

class CoachingService {
  final ApiClient _apiClient;

  CoachingService(this._apiClient);

  /// Map plan type IDs to backend template IDs
  int _getTemplateId(String planTypeId) {
    switch (planTypeId) {
      case 'fat-loss':
        return 1;
      case 'get-faster':
        return 2;
      case 'event-prep':
        return 3;
      case 'daily-discipline':
        return 4;
      case 'age-strong':
        return 5;
      case 'load-capacity':
        return 6;
      default:
        return 1; // Default to fat-loss
    }
  }

  /// Create a new personalized coaching plan
  Future<Map<String, dynamic>> createCoachingPlan({
    required String basePlanId,
    required String coachingPersonality,
    required PlanPersonalization personalization,
  }) async {
    try {
      final responseData = await _apiClient.post(
        '/user-coaching-plans',
        {
          'template_id': _getTemplateId(basePlanId), // Map plan type ID to backend template ID
          'personality': coachingPersonality,  // Fixed parameter name to match backend
          'start_date': DateTime.now().toIso8601String().split('T')[0], // Today
        },
      );

      // Handle both direct response and wrapped response formats
      if (responseData is Map<String, dynamic>) {
        if (responseData.containsKey('success') && responseData['success'] == true) {
          return responseData['data'];
        } else if (responseData.containsKey('success') && responseData['success'] == false) {
          throw Exception(responseData['message'] ?? 'Failed to create coaching plan');
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

      // Our API returns null if no active plan, or the plan data
      return responseData;
    } catch (e) {
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