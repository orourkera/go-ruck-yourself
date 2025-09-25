import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/coaching/domain/models/plan_personalization.dart';
import 'package:rucking_app/core/network/api_endpoints.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

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
      // Automatically detect user's timezone using IANA timezone identifier
      String userTimezone;
      try {
        userTimezone = await FlutterTimezone.getLocalTimezone();
      } catch (e) {
        // Fallback to UTC if we can't detect timezone
        userTimezone = 'UTC';
        AppLogger.warning('[COACHING_SERVICE] Could not detect timezone, using UTC: $e');
      }

      // Create personalization with timezone
      final personalizedData = personalization.toJson();
      personalizedData['timezone'] = userTimezone;

      AppLogger.info('[COACHING_SERVICE] Detected timezone: $userTimezone');

      final responseData = await _apiClient.post(
        '/coaching-plans', // Correct endpoint
        {
          'base_plan_id': basePlanId, // Use the plan type ID directly
          'coaching_personality':
              coachingPersonality, // Match backend field name
          'personalization': personalizedData, // Include personalization with timezone!
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
    print('🔍🔍🔍 [COACHING_SERVICE] Fetching active coaching plan...');
    print('🔍🔍🔍 [COACHING_SERVICE] API endpoint: ${ApiEndpoints.userCoachingPlansActive}');
    try {
      print('🔍🔍🔍 [COACHING_SERVICE] Making API call...');
      final responseData = await _apiClient.get(ApiEndpoints.userCoachingPlansActive)
          .timeout(Duration(seconds: 30), onTimeout: () {
        print('🔍🔍🔍 [COACHING_SERVICE] API call TIMEOUT after 30 seconds');
        throw Exception('API call timeout');
      });
      print('🔍🔍🔍 [COACHING_SERVICE] API call completed successfully');
      print('🔍🔍🔍 [COACHING_SERVICE] Raw API response: $responseData');
      AppLogger.info('[COACHING_SERVICE] API response: $responseData');

      Map<String, dynamic>? activePlan;
      if (responseData is Map<String, dynamic>) {
        if (responseData.containsKey('active_plan')) {
          // Check if active_plan is null (no plan) or a Map (has plan)
          final planData = responseData['active_plan'];
          if (planData == null) {
            print('🔍🔍🔍 [COACHING_SERVICE] No active plan (active_plan is null)');
            AppLogger.info('[COACHING_SERVICE] No active plan for user');
            return null;
          } else if (planData is Map<String, dynamic>) {
            activePlan = Map<String, dynamic>.from(planData);
          }
        } else {
          activePlan = Map<String, dynamic>.from(responseData);
        }
      }

      // Check for truly empty plan (no plan exists)
      if (activePlan == null ||
          activePlan.isEmpty ||
          (activePlan.length == 1 && activePlan.containsKey('active_plan') && activePlan['active_plan'] == null)) {
        print('🔍🔍🔍 [COACHING_SERVICE] Active plan not found or empty');
        AppLogger.info('[COACHING_SERVICE] No active plan for user');
        return null;
      }

      final normalized = _normalizeActivePlan(activePlan);
      print(
          '🔍🔍🔍 [COACHING_SERVICE] Normalized plan: ${normalized.toString()}');
      AppLogger.info(
          '[COACHING_SERVICE] Active plan normalized: ${normalized['plan_name']}');
      return normalized;
    } catch (e) {
      print('🔍🔍🔍 [COACHING_SERVICE] ERROR: $e');
      AppLogger.error('[COACHING_SERVICE] Error fetching plan: $e');
      throw Exception('Failed to fetch active coaching plan: $e');
    }
  }

  /// Get detailed progress for the current user's active plan
  Future<Map<String, dynamic>> getCoachingPlanProgress() async {
    try {
      final responseData =
          await _apiClient.get(ApiEndpoints.userCoachingPlanProgress);
      if (responseData is Map<String, dynamic>) {
        return _normalizePlanProgress(responseData);
      }
      return {};
    } catch (e) {
      // If it's a 404 (no active plan), return empty progress rather than throwing
      if (e.toString().contains('404') || e.toString().contains('No active coaching plan')) {
        AppLogger.info('[COACHING_SERVICE] No active plan to get progress for');
        return {};
      }
      // For other errors, still throw
      throw Exception('Failed to fetch coaching plan progress: $e');
    }
  }

  /// Delete the user's active coaching plan
  Future<void> deleteCoachingPlan() async {
    try {
      AppLogger.info('[COACHING_SERVICE] Deleting active coaching plan...');
      await _apiClient.delete(ApiEndpoints.userCoachingPlansActive);
      AppLogger.info('[COACHING_SERVICE] Coaching plan deleted successfully');
    } catch (e) {
      AppLogger.error('[COACHING_SERVICE] Error deleting coaching plan: $e');
      throw Exception('Failed to delete coaching plan: $e');
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

  Map<String, dynamic> _normalizeActivePlan(Map<String, dynamic> raw) {
    final template = raw['template'] is Map
        ? Map<String, dynamic>.from(raw['template'])
        : <String, dynamic>{};

    final planName =
        raw['plan_name'] ?? raw['name'] ?? template['name'] ?? 'Training Plan';

    final adherence = (raw['adherence_stats'] is Map &&
            raw['adherence_stats']['overall_adherence'] is num)
        ? (raw['adherence_stats']['overall_adherence'] as num).toDouble()
        : (raw['progress_percent'] is num)
            ? (raw['progress_percent'] as num).toDouble()
            : null;

    final normalized = <String, dynamic>{}
      ..addAll(raw)
      ..['template'] = template
      ..['plan_name'] = planName
      ..['name'] = planName
      ..['duration_weeks'] =
          raw['duration_weeks'] ?? template['duration_weeks'] ?? 8
      ..['duration'] = raw['duration_weeks'] ?? template['duration_weeks'] ?? 8
      ..['current_week'] = raw['current_week'] ?? 1
      ..['weekNumber'] = raw['current_week'] ?? 1
      ..['current_phase'] = raw['current_phase'] ??
          raw['phase'] ??
          raw['plan_phase'] ??
          'Training'
      ..['phase'] = (raw['phase'] ?? raw['current_phase'] ?? 'Training')
      ..['goal'] = raw['goal'] ?? template['goal']
      ..['coaching_personality'] =
          raw['coaching_personality'] ?? raw['personality']
      ..['adherence_percentage'] = adherence
      ..['adherence'] = adherence ?? 0.0
      ..['is_on_track'] = (adherence ?? 0) >= 70
      ..['isOnTrack'] = (adherence ?? 0) >= 70
      ..['next_session'] = raw['next_session'];

    if (raw['adherence_stats'] is Map<String, dynamic>) {
      final stats = Map<String, dynamic>.from(raw['adherence_stats']);
      normalized['adherence_stats'] = stats;
    }

    return normalized;
  }

  Map<String, dynamic> _normalizePlanProgress(Map<String, dynamic> raw) {
    final planInfoRaw = raw['plan_info'] is Map
        ? Map<String, dynamic>.from(raw['plan_info'])
        : <String, dynamic>{};
    final progressRaw = raw['progress'] is Map
        ? Map<String, dynamic>.from(raw['progress'])
        : <String, dynamic>{};

    final nextSession = _normalizeNextSession(raw['next_session']);

    final planInfo = {
      ...planInfoRaw,
      'plan_name': planInfoRaw['name'] ?? planInfoRaw['plan_name'],
      'name': planInfoRaw['name'] ?? planInfoRaw['plan_name'],
      'current_week': planInfoRaw['current_week'] ?? 1,
      'duration_weeks':
          planInfoRaw['total_weeks'] ?? planInfoRaw['duration_weeks'] ?? 8,
    };

    final progress = {
      'adherence_percentage':
          (progressRaw['overall_adherence'] as num?)?.toDouble() ?? 0.0,
      'completed_sessions':
          (progressRaw['completed_sessions'] as num?)?.toInt() ?? 0,
      'total_sessions': (progressRaw['total_sessions'] as num?)?.toInt() ?? 0,
      'weekly_consistency':
          (progressRaw['weekly_consistency'] as num?)?.toDouble() ?? 0.0,
      'weekly_streak': (progressRaw['weekly_streak'] as num?)?.toInt() ?? 0,
      'is_on_track':
          ((progressRaw['overall_adherence'] as num?)?.toDouble() ?? 0.0) >= 70,
      'next_session': nextSession,
    };

    return {
      'plan_info': planInfo,
      'progress': progress,
      'next_session': nextSession,
      'weekly_schedule': raw['weekly_schedule'],
      'raw': raw,
    };
  }

  Map<String, dynamic>? _normalizeNextSession(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final recommendation = map['recommendation'] is Map
        ? Map<String, dynamic>.from(map['recommendation'])
        : <String, dynamic>{};

    double? _toDouble(dynamic value) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value);
      return null;
    }

    return {
      'type': map['session_type'] ??
          map['planned_session_type'] ??
          recommendation['session_type'] ??
          recommendation['type'],
      'session_type': map['session_type'] ?? map['planned_session_type'],
      'scheduled_date': map['scheduled_date'],
      'duration_minutes': map['duration_minutes'] ??
          recommendation['duration_minutes'] ??
          recommendation['duration'],
      'distance_km':
          _toDouble(map['distance_km'] ?? recommendation['distance_km']),
      'weight_kg': _toDouble(map['weight_kg'] ?? recommendation['weight_kg']),
      'notes': recommendation['notes'] ?? map['notes'],
      'intensity': recommendation['intensity'],
      'description': recommendation['description'],
      'recommendation': recommendation,
    };
  }

  Map<String, dynamic>? buildAIPlanContext({
    Map<String, dynamic>? plan,
    Map<String, dynamic>? progress,
    Map<String, dynamic>? nextSession,
  }) {
    if (plan == null || plan.isEmpty) return null;

    final adherence = (progress?['adherence_percentage'] as num?)?.toDouble() ??
        (plan['adherence_percentage'] as num?)?.toDouble() ??
        0.0;
    final isOnTrack = (progress?['is_on_track'] == true) ||
        (plan['is_on_track'] == true) ||
        (plan['isOnTrack'] == true) ||
        (adherence >= 70);

    final normalizedNextSession = nextSession ?? plan['next_session'];

    return {
      'plan_name': plan['plan_name'] ?? plan['name'] ?? 'Training Plan',
      'name': plan['plan_name'] ?? plan['name'] ?? 'Training Plan',
      'weekNumber': plan['current_week'] ?? plan['weekNumber'] ?? 1,
      'duration': plan['duration_weeks'] ?? plan['duration'] ?? 0,
      'current_week': plan['current_week'] ?? plan['weekNumber'] ?? 1,
      'duration_weeks': plan['duration_weeks'] ?? plan['duration'] ?? 0,
      'phase': plan['current_phase'] ?? plan['phase'] ?? 'Training',
      'adherence': adherence,
      'adherence_percentage': adherence,
      'isOnTrack': isOnTrack,
      'is_on_track': isOnTrack,
      'nextSession': normalizedNextSession,
      'next_session': normalizedNextSession,
      'sources': plan['sources'],
      'hydration_fueling': plan['hydration_fueling'],
      'goal': plan['goal'],
      'progress': progress,
    };
  }
}
