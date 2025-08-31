import 'dart:convert';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/features/coaching/domain/models/plan_personalization.dart';

class CoachingService {
  final ApiClient _apiClient;

  CoachingService(this._apiClient);

  /// Create a new personalized coaching plan
  Future<Map<String, dynamic>> createCoachingPlan({
    required String basePlanId,
    required String coachingPersonality,
    required PlanPersonalization personalization,
  }) async {
    try {
      final responseData = await _apiClient.post(
        '/coaching-plans',
        {
          'base_plan_id': basePlanId,
          'coaching_personality': coachingPersonality,
          'personalization': personalization.toJson(),
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

  /// Get all coaching plans for the current user
  Future<List<Map<String, dynamic>>> getCoachingPlans({String? status}) async {
    try {
      final queryParams = status != null ? {'status': status} : <String, dynamic>{};
      
      final responseData = await _apiClient.get(
        '/coaching-plans',
        queryParams: queryParams,
      );

      // Handle both direct response and wrapped response formats
      if (responseData is Map<String, dynamic>) {
        if (responseData.containsKey('success') && responseData['success'] == true) {
          final List<dynamic> plans = responseData['data']['coaching_plans'];
          return plans.cast<Map<String, dynamic>>();
        } else if (responseData.containsKey('success') && responseData['success'] == false) {
          throw Exception(responseData['message'] ?? 'Failed to fetch coaching plans');
        } else {
          // Direct response format - assume it's a list
          if (responseData is List) {
            return (responseData as List).cast<Map<String, dynamic>>();
          } else {
            throw Exception('Unexpected response format');
          }
        }
      } else if (responseData is List) {
        return (responseData as List).cast<Map<String, dynamic>>();
      } else {
        throw Exception('Unexpected response format');
      }
    } catch (e) {
      throw Exception('Failed to fetch coaching plans: $e');
    }
  }

  /// Get a specific coaching plan
  Future<Map<String, dynamic>> getCoachingPlan(String planId) async {
    try {
      final responseData = await _apiClient.get('/coaching-plans/$planId');

      // Handle both direct response and wrapped response formats
      if (responseData is Map<String, dynamic>) {
        if (responseData.containsKey('success') && responseData['success'] == true) {
          return responseData['data']['coaching_plan'];
        } else if (responseData.containsKey('success') && responseData['success'] == false) {
          throw Exception(responseData['message'] ?? 'Failed to fetch coaching plan');
        } else {
          // Direct response format
          return responseData;
        }
      } else {
        throw Exception('Unexpected response format: $responseData');
      }
    } catch (e) {
      throw Exception('Failed to fetch coaching plan: $e');
    }
  }

  /// Update a coaching plan's status
  Future<Map<String, dynamic>> updateCoachingPlanStatus(
    String planId,
    String status,
  ) async {
    try {
      final responseData = await _apiClient.patch(
        '/coaching-plans/$planId',
        {'status': status},
      );

      // Handle both direct response and wrapped response formats
      if (responseData is Map<String, dynamic>) {
        if (responseData.containsKey('success') && responseData['success'] == true) {
          return responseData['data']['coaching_plan'];
        } else if (responseData.containsKey('success') && responseData['success'] == false) {
          throw Exception(responseData['message'] ?? 'Failed to update coaching plan');
        } else {
          // Direct response format
          return responseData;
        }
      } else {
        throw Exception('Unexpected response format: $responseData');
      }
    } catch (e) {
      throw Exception('Failed to update coaching plan: $e');
    }
  }
}