import 'package:rucking_app/core/network/api_endpoints.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/models/goal.dart';
import 'package:rucking_app/core/models/goal_progress.dart';
import 'package:rucking_app/core/models/goal_schedule.dart';
import 'package:rucking_app/core/models/goal_message.dart';
import 'package:rucking_app/core/models/goal_details.dart';
import 'package:rucking_app/core/models/goal_with_progress.dart';

class GoalsApiService {
  final ApiClient _api;
  GoalsApiService(this._api);

  // List goals with latest progress
  Future<List<GoalWithProgress>> listGoalsWithProgress({
    int? page,
    int? pageSize,
    String? status,
  }) async {
    final query = <String, dynamic>{};
    if (page != null) query['page'] = page;
    if (pageSize != null) query['page_size'] = pageSize;
    if (status != null) query['status'] = status;

    final data = await _api.get(ApiEndpoints.goalsWithProgress, queryParams: query);
    final list = (data as List?) ?? const [];
    return list
        .map((e) => GoalWithProgress.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  // Get consolidated goal details
  Future<GoalDetails> getGoalDetails(String goalId) async {
    final data = await _api.get(ApiEndpoints.getGoalDetailsEndpoint(goalId));
    return GoalDetails.fromJson(Map<String, dynamic>.from(data as Map));
  }

  // Get goal progress
  Future<GoalProgress?> getGoalProgress(String goalId) async {
    final data = await _api.get(ApiEndpoints.getGoalProgressEndpoint(goalId));
    if (data == null) return null;
    return GoalProgress.fromJson(Map<String, dynamic>.from(data as Map));
  }

  // Get goal schedule
  Future<GoalSchedule?> getGoalSchedule(String goalId) async {
    final data = await _api.get(ApiEndpoints.getGoalScheduleEndpoint(goalId));
    if (data == null) return null;
    return GoalSchedule.fromJson(Map<String, dynamic>.from(data as Map));
  }

  // Upsert goal schedule
  Future<GoalSchedule> upsertGoalSchedule(String goalId, GoalSchedule schedule) async {
    final body = schedule.toJson();
    final data = await _api.put(ApiEndpoints.getGoalScheduleEndpoint(goalId), body);
    return GoalSchedule.fromJson(Map<String, dynamic>.from(data as Map));
  }

  // List goal messages with optional filters
  Future<List<GoalMessage>> getGoalMessages(
    String goalId, {
    String? channel,
    String? messageType,
    DateTime? before,
    DateTime? after,
    int? limit,
    bool? sentOnly,
  }) async {
    final query = <String, dynamic>{};
    if (channel != null) query['channel'] = channel;
    if (messageType != null) query['message_type'] = messageType;
    if (before != null) query['before'] = before.toIso8601String();
    if (after != null) query['after'] = after.toIso8601String();
    if (limit != null) query['limit'] = limit;
    if (sentOnly != null) query['sent_only'] = sentOnly;

    final data = await _api.get(ApiEndpoints.getGoalMessagesEndpoint(goalId), queryParams: query);
    final list = (data as List?) ?? const [];
    return list
        .map((e) => GoalMessage.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  // Trigger evaluation for a goal
  Future<Map<String, dynamic>> evaluateGoal(String goalId, {bool? force}) async {
    final body = <String, dynamic>{};
    if (force != null) body['force'] = force;
    final data = await _api.post(ApiEndpoints.getGoalEvaluateEndpoint(goalId), body);
    return Map<String, dynamic>.from(data as Map);
  }

  // Trigger evaluation for all goals (scheduler/crons)
  Future<Map<String, dynamic>> evaluateAllGoals() async {
    final data = await _api.post(ApiEndpoints.getGoalsEvaluateAllEndpoint(), {});
    return Map<String, dynamic>.from(data as Map);
  }

  // Send deterministic notification for a goal
  Future<GoalMessage> sendGoalNotification(
    String goalId, {
    String? channel,
    String? messageType,
    Map<String, dynamic>? params,
  }) async {
    final body = <String, dynamic>{};
    if (channel != null) body['channel'] = channel;
    if (messageType != null) body['message_type'] = messageType;
    if (params != null) body['params'] = params;

    final data = await _api.post(ApiEndpoints.getGoalNotifyEndpoint(goalId), body);
    return GoalMessage.fromJson(Map<String, dynamic>.from(data as Map));
  }

  // Parse a natural language goal into a structured object
  Future<Map<String, dynamic>> parseGoal(String inputText) async {
    final data = await _api.post(ApiEndpoints.goals + '/parse', {
      'text': inputText,
    });
    return Map<String, dynamic>.from(data as Map);
  }

  // Optional: fetch a single goal (basic)
  Future<Goal> getGoal(String goalId) async {
    final data = await _api.get(ApiEndpoints.getGoalEndpoint(goalId));
    return Goal.fromJson(Map<String, dynamic>.from(data as Map));
  }
}
