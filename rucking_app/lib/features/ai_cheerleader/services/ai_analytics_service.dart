import 'dart:convert';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

class AIAnalyticsService {
  final ApiClient _apiClient;

  AIAnalyticsService(this._apiClient);

  /// Log AI cheerleader interaction for analytics
  Future<void> logInteraction({
    required String sessionId,
    required String userId,
    required String personality,
    required String triggerType,
    required String openaiPrompt,
    required String openaiResponse,
    String? elevenlabsVoiceId,
    required Map<String, dynamic> sessionContext,
    Map<String, dynamic>? locationContext,
    Map<String, dynamic>? triggerData,
    required bool explicitContentEnabled,
    String? userGender,
    bool? userPreferMetric,
    int? generationTimeMs,
    bool? synthesisSuccess,
    int? synthesisTimeMs,
  }) async {
    try {
      // Analyze message content for analytics flags
      final hasLocationReference = _checkLocationReference(openaiResponse, locationContext);
      final hasWeatherReference = _checkWeatherReference(openaiResponse, locationContext);
      final hasPersonalReference = _checkPersonalReference(openaiPrompt, openaiResponse);
      
      final interactionData = {
        'session_id': sessionId,
        'user_id': userId,
        'personality': personality,
        'trigger_type': triggerType,
        'openai_prompt': openaiPrompt,
        'openai_response': openaiResponse,
        'elevenlabs_voice_id': elevenlabsVoiceId,
        'session_context': sessionContext,
        'location_context': locationContext,
        'trigger_data': triggerData,
        'explicit_content_enabled': explicitContentEnabled,
        'user_gender': userGender,
        'user_prefer_metric': userPreferMetric,
        'generation_time_ms': generationTimeMs,
        'synthesis_success': synthesisSuccess,
        'synthesis_time_ms': synthesisTimeMs,
        'message_length': openaiResponse.length,
        'word_count': openaiResponse.split(' ').length,
        'has_location_reference': hasLocationReference,
        'has_weather_reference': hasWeatherReference,
        'has_personal_reference': hasPersonalReference,
      };

      final response = await _apiClient.post(
        '/ai-cheerleader/interactions',
        interactionData,
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        AppLogger.info('[AI_ANALYTICS] Interaction logged successfully');
      } else {
        AppLogger.warning('[AI_ANALYTICS] Failed to log interaction: ${response.statusCode}');
      }
    } catch (e) {
      AppLogger.error('[AI_ANALYTICS] Error logging interaction: $e');
      // Don't throw - analytics logging shouldn't break the user experience
    }
  }

  /// Log personality selection for analytics
  Future<void> logPersonalitySelection({
    required String userId,
    required String sessionId,
    required String personality,
    required bool explicitContentEnabled,
    int? sessionDurationPlannedMinutes,
    double? sessionDistancePlannedKm,
    double? ruckWeightKg,
    int? userTotalRucks,
    double? userTotalDistanceKm,
  }) async {
    try {
      final selectionData = {
        'user_id': userId,
        'session_id': sessionId,
        'personality': personality,
        'explicit_content_enabled': explicitContentEnabled,
        'session_duration_planned_minutes': sessionDurationPlannedMinutes,
        'session_distance_planned_km': sessionDistancePlannedKm,
        'ruck_weight_kg': ruckWeightKg,
        'user_total_rucks': userTotalRucks,
        'user_total_distance_km': userTotalDistanceKm,
      };

      final response = await _apiClient.post(
        '/ai-cheerleader/personality-selections',
        selectionData,
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        AppLogger.info('[AI_ANALYTICS] Personality selection logged successfully');
      } else {
        AppLogger.warning('[AI_ANALYTICS] Failed to log personality selection: ${response.statusCode}');
      }
    } catch (e) {
      AppLogger.error('[AI_ANALYTICS] Error logging personality selection: $e');
    }
  }

  /// Log AI cheerleader session start
  Future<void> logSessionStart({
    required String sessionId,
    required String userId,
    required String personality,
    required bool explicitContentEnabled,
    bool aiEnabledAtStart = true,
  }) async {
    try {
      final sessionData = {
        'session_id': sessionId,
        'user_id': userId,
        'personality': personality,
        'explicit_content_enabled': explicitContentEnabled,
        'ai_enabled_at_start': aiEnabledAtStart,
      };

      final response = await _apiClient.post(
        '/ai-cheerleader/sessions',
        sessionData,
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        AppLogger.info('[AI_ANALYTICS] Session start logged successfully');
      }
    } catch (e) {
      AppLogger.error('[AI_ANALYTICS] Error logging session start: $e');
    }
  }

  /// Update AI cheerleader session metrics
  Future<void> updateSessionMetrics({
    required String sessionId,
    int? totalInteractions,
    int? totalTriggersFired,
    int? totalSuccessfulSyntheses,
    int? totalFailedSyntheses,
    int? avgGenerationTimeMs,
    int? avgSynthesisTimeMs,
    bool? sessionCompleted,
    bool? aiDisabledDuringSession,
    DateTime? aiDisabledAt,
  }) async {
    try {
      final updateData = <String, dynamic>{};
      
      if (totalInteractions != null) updateData['total_interactions'] = totalInteractions;
      if (totalTriggersFired != null) updateData['total_triggers_fired'] = totalTriggersFired;
      if (totalSuccessfulSyntheses != null) updateData['total_successful_syntheses'] = totalSuccessfulSyntheses;
      if (totalFailedSyntheses != null) updateData['total_failed_syntheses'] = totalFailedSyntheses;
      if (avgGenerationTimeMs != null) updateData['avg_generation_time_ms'] = avgGenerationTimeMs;
      if (avgSynthesisTimeMs != null) updateData['avg_synthesis_time_ms'] = avgSynthesisTimeMs;
      if (sessionCompleted != null) updateData['session_completed'] = sessionCompleted;
      if (aiDisabledDuringSession != null) updateData['ai_disabled_during_session'] = aiDisabledDuringSession;
      if (aiDisabledAt != null) updateData['ai_disabled_at'] = aiDisabledAt.toIso8601String();

      if (updateData.isEmpty) return;

      final response = await _apiClient.patch(
        '/ai-cheerleader/sessions/$sessionId',
        updateData,
      );

      if (response.statusCode == 200) {
        AppLogger.info('[AI_ANALYTICS] Session metrics updated successfully');
      }
    } catch (e) {
      AppLogger.error('[AI_ANALYTICS] Error updating session metrics: $e');
    }
  }

  /// Check if message references location
  bool _checkLocationReference(String message, Map<String, dynamic>? locationContext) {
    if (locationContext == null) return false;
    
    final lowerMessage = message.toLowerCase();
    final city = locationContext['city']?.toString().toLowerCase();
    final landmark = locationContext['landmark']?.toString().toLowerCase();
    
    if (city != null && city.isNotEmpty && lowerMessage.contains(city)) {
      return true;
    }
    
    if (landmark != null && landmark.isNotEmpty && lowerMessage.contains(landmark)) {
      return true;
    }
    
    // Check for general location terms
    final locationTerms = ['park', 'trail', 'hill', 'mountain', 'beach', 'city', 'downtown', 'neighborhood'];
    return locationTerms.any((term) => lowerMessage.contains(term));
  }

  /// Check if message references weather
  bool _checkWeatherReference(String message, Map<String, dynamic>? locationContext) {
    if (locationContext == null) return false;
    
    final lowerMessage = message.toLowerCase();
    final weatherCondition = locationContext['weatherCondition']?.toString().toLowerCase();
    
    if (weatherCondition != null && weatherCondition.isNotEmpty && lowerMessage.contains(weatherCondition)) {
      return true;
    }
    
    // Check for general weather terms
    final weatherTerms = ['sunny', 'rain', 'wind', 'hot', 'cold', 'warm', 'cool', 'weather', 'temperature', 'degrees'];
    return weatherTerms.any((term) => lowerMessage.contains(term));
  }

  /// Check if message includes personal references (name usage)
  bool _checkPersonalReference(String prompt, String response) {
    // Look for first name extraction patterns in prompt and usage in response
    final promptLower = prompt.toLowerCase();
    final responseLower = response.toLowerCase();
    
    // Simple heuristic: if response contains common personal pronouns or direct address
    final personalTerms = ['you\'re', 'your', 'you are', 'keep going', 'great job'];
    
    // Check if response uses extracted name (would need to be more sophisticated)
    // This is a basic implementation - could be enhanced to track actual name usage
    return personalTerms.any((term) => responseLower.contains(term));
  }

  /// Get analytics summary for a user (admin feature)
  Future<Map<String, dynamic>?> getUserAnalytics(String userId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final queryParams = <String, String>{
        'user_id': userId,
      };
      
      if (startDate != null) {
        queryParams['start_date'] = startDate.toIso8601String();
      }
      if (endDate != null) {
        queryParams['end_date'] = endDate.toIso8601String();
      }

      final response = await _apiClient.get(
        '/ai-cheerleader/analytics',
        queryParams: queryParams,
      );

      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      }
    } catch (e) {
      AppLogger.error('[AI_ANALYTICS] Error fetching user analytics: $e');
    }
    return null;
  }
}
