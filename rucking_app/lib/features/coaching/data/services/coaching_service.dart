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
      final response = await _apiClient.post(
        '/api/coaching-plans',
        data: {
          'base_plan_id': basePlanId,
          'coaching_personality': coachingPersonality,
          'personalization': personalization.toJson(),
        },
      );

      if (response.data['success'] == true) {
        return response.data['data'];
      } else {
        throw Exception(response.data['message'] ?? 'Failed to create coaching plan');
      }
    } catch (e) {
      throw Exception('Failed to create coaching plan: $e');
    }
  }

  /// Get all coaching plans for the current user
  Future<List<Map<String, dynamic>>> getCoachingPlans({String? status}) async {
    try {
      final queryParams = status != null ? {'status': status} : <String, dynamic>{};
      
      final response = await _apiClient.get(
        '/api/coaching-plans',
        queryParameters: queryParams,
      );

      if (response.data['success'] == true) {
        final List<dynamic> plans = response.data['data']['coaching_plans'];
        return plans.cast<Map<String, dynamic>>();
      } else {
        throw Exception(response.data['message'] ?? 'Failed to fetch coaching plans');
      }
    } catch (e) {
      throw Exception('Failed to fetch coaching plans: $e');
    }
  }

  /// Get a specific coaching plan
  Future<Map<String, dynamic>> getCoachingPlan(String planId) async {
    try {
      final response = await _apiClient.get('/api/coaching-plans/$planId');

      if (response.data['success'] == true) {
        return response.data['data']['coaching_plan'];
      } else {
        throw Exception(response.data['message'] ?? 'Failed to fetch coaching plan');
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
      final response = await _apiClient.patch(
        '/api/coaching-plans/$planId',
        data: {'status': status},
      );

      if (response.data['success'] == true) {
        return response.data['data']['coaching_plan'];
      } else {
        throw Exception(response.data['message'] ?? 'Failed to update coaching plan');
      }
    } catch (e) {
      throw Exception('Failed to update coaching plan: $e');
    }
  }
}