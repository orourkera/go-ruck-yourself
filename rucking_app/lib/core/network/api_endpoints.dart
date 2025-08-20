/// API Endpoints for Ruck!
/// This file contains all the endpoint constants used throughout the application

class ApiEndpoints {
  // Base API endpoint - empty since baseURL already includes /api
  static const String baseApi = '';
  
  // Ruck Sessions
  static const String ruckSessions = '$baseApi/ruck-sessions';
  static const String ruckById = '$baseApi/rucks'; // Typically used as: "$ruckById/$ruckId"
  
  // Ruck Buddies (Community Rucks)
  static const String ruckBuddies = '$baseApi/ruck-buddies';
  static const String communityRucks = '$baseApi/rucks/community';
  
  // Social Interactions
  static const String likes = '$baseApi/rucks/{id}/like'; // Replace {id} with actual ruck ID
  static const String comments = '$baseApi/rucks/{id}/comments'; // Replace {id} with actual ruck ID
  static const String deleteComment = '$baseApi/rucks/{id}/comments/{comment_id}'; // Replace {id} and {comment_id}
  
  // Photos
  static const String ruckPhotos = '$baseApi/ruck-photos';
  
  // Notifications
  static const String notifications = '$baseApi/notifications';
  static const String notificationRead = '$baseApi/notifications/{id}/read'; // Replace {id} with notification ID
  static const String readAllNotifications = '$baseApi/notifications/read-all';
  
  // Achievements
  static const String achievements = '$baseApi/achievements';
  static const String achievementCategories = '$baseApi/achievements/categories';
  static const String userAchievements = '$baseApi/users/{user_id}/achievements'; // Replace {user_id} with actual user ID
  static const String userAchievementsProgress = '$baseApi/users/{user_id}/achievements/progress'; // Replace {user_id} with actual user ID
  static const String checkSessionAchievements = '$baseApi/achievements/check/{session_id}'; // Replace {session_id} with actual session ID
  static const String achievementStats = '$baseApi/achievements/stats/{user_id}'; // Replace {user_id} with actual user ID
  static const String recentAchievements = '$baseApi/achievements/recent';

  // Helper methods for path parameters
  static String getRuckEndpoint(String ruckId) => '$ruckById/$ruckId';
  static String getLikesEndpoint(String ruckId) => likes.replaceAll('{id}', ruckId);
  static String getCommentsEndpoint(String ruckId) => comments.replaceAll('{id}', ruckId);
  static String getDeleteCommentEndpoint(String ruckId, String commentId) => 
      deleteComment.replaceAll('{id}', ruckId).replaceAll('{comment_id}', commentId);
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
}
