/// API Endpoints for Ruck!
/// This file contains all the endpoint constants used throughout the application

class ApiEndpoints {
  // Base API endpoint - empty since baseURL already includes /api
  static const String baseApi = '';

  // Ruck Sessions
  static const String ruckSessions = '$baseApi/ruck-sessions';
  static const String ruckById =
      '$baseApi/rucks'; // Typically used as: "$ruckById/$ruckId"

  // Ruck Buddies (Community Rucks)
  static const String ruckBuddies = '$baseApi/ruck-buddies';
  static const String communityRucks = '$baseApi/rucks/community';

  // Social Interactions
  static const String likes =
      '$baseApi/rucks/{id}/like'; // Replace {id} with actual ruck ID
  static const String comments =
      '$baseApi/rucks/{id}/comments'; // Replace {id} with actual ruck ID
  static const String deleteComment =
      '$baseApi/rucks/{id}/comments/{comment_id}'; // Replace {id} and {comment_id}

  // Photos
  static const String ruckPhotos = '$baseApi/ruck-photos';

  // Notifications
  static const String notifications = '$baseApi/notifications';
  static const String notificationRead =
      '$baseApi/notifications/{id}/read'; // Replace {id} with notification ID
  static const String readAllNotifications = '$baseApi/notifications/read-all';

  // Achievements
  static const String achievements = '$baseApi/achievements';
  static const String achievementCategories =
      '$baseApi/achievements/categories';
  static const String userAchievements =
      '$baseApi/users/{user_id}/achievements'; // Replace {user_id} with actual user ID
  static const String userAchievementsProgress =
      '$baseApi/users/{user_id}/achievements/progress'; // Replace {user_id} with actual user ID
  static const String checkSessionAchievements =
      '$baseApi/achievements/check/{session_id}'; // Replace {session_id} with actual session ID
  static const String achievementStats =
      '$baseApi/achievements/stats/{user_id}'; // Replace {user_id} with actual user ID
  static const String recentAchievements = '$baseApi/achievements/recent';

  // AI Cheerleader
  static const String aiCheerleader = '$baseApi/ai-cheerleader';
  static const String aiCheerleaderLogs = '$baseApi/ai-cheerleader/logs';

  // User insights snapshot (facts + triggers + optional LLM candidates)
  static const String userInsights = '$baseApi/user-insights';

  // AI Goals
  static const String goals = '$baseApi/goals';
  static const String goalsWithProgress = '$baseApi/goals-with-progress';
  static const String goalById = '$baseApi/goals/{goal_id}';
  static const String goalDetails = '$baseApi/goals/{goal_id}/details';
  static const String goalProgress = '$baseApi/goals/{goal_id}/progress';
  static const String goalSchedule = '$baseApi/goals/{goal_id}/schedule';
  static const String goalMessages = '$baseApi/goals/{goal_id}/messages';
  static const String goalEvaluate = '$baseApi/goals/{goal_id}/evaluate';
  static const String goalNotify = '$baseApi/goals/{goal_id}/notify';
  static const String goalsEvaluateAll = '$baseApi/goals/evaluate-all';

  // Coaching Plans
  static const String userCoachingPlans = '$baseApi/user-coaching-plans';
  static const String userCoachingPlansActive = '$userCoachingPlans/active';
  static const String userCoachingPlanProgress =
      '$baseApi/user-coaching-plan-progress';

  // Helper methods for path parameters
  static String getRuckEndpoint(String ruckId) => '$ruckById/$ruckId';
  static String getLikesEndpoint(String ruckId) =>
      likes.replaceAll('{id}', ruckId);
  static String getCommentsEndpoint(String ruckId) =>
      comments.replaceAll('{id}', ruckId);
  static String getDeleteCommentEndpoint(String ruckId, String commentId) =>
      deleteComment
          .replaceAll('{id}', ruckId)
          .replaceAll('{comment_id}', commentId);
  static String getNotificationReadEndpoint(String notificationId) =>
      notificationRead.replaceAll('{id}', notificationId);
  static String getMarkAllNotificationsAsReadEndpoint() => readAllNotifications;
  static String getUserAchievementsEndpoint(String userId) =>
      userAchievements.replaceAll('{user_id}', userId);
  static String getUserAchievementsProgressEndpoint(String userId) =>
      userAchievementsProgress.replaceAll('{user_id}', userId);
  static String getCheckSessionAchievementsEndpoint(String sessionId) =>
      checkSessionAchievements.replaceAll('{session_id}', sessionId);
  static String getAchievementStatsEndpoint(String userId) =>
      achievementStats.replaceAll('{user_id}', userId);
  static String getAchievementCategoriesEndpoint() => achievementCategories;
  static String getRecentAchievementsEndpoint() => recentAchievements;

  // Goals helper methods
  static String getGoalEndpoint(String goalId) =>
      goalById.replaceAll('{goal_id}', goalId);
  static String getGoalDetailsEndpoint(String goalId) =>
      goalDetails.replaceAll('{goal_id}', goalId);
  static String getGoalProgressEndpoint(String goalId) =>
      goalProgress.replaceAll('{goal_id}', goalId);
  static String getGoalScheduleEndpoint(String goalId) =>
      goalSchedule.replaceAll('{goal_id}', goalId);
  static String getGoalMessagesEndpoint(String goalId) =>
      goalMessages.replaceAll('{goal_id}', goalId);
  static String getGoalEvaluateEndpoint(String goalId) =>
      goalEvaluate.replaceAll('{goal_id}', goalId);
  static String getGoalNotifyEndpoint(String goalId) =>
      goalNotify.replaceAll('{goal_id}', goalId);
  static String getGoalsEvaluateAllEndpoint() => goalsEvaluateAll;
}
