/// API Endpoints for Ruck!
/// This file contains all the endpoint constants used throughout the application

class ApiEndpoints {
  // Base API endpoint
  static const String baseApi = '/api';
  
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
  static const String notifications = '$baseApi/notifications/';
  static const String notificationRead = '$baseApi/notifications/{id}/read'; // Replace {id} with notification ID
  static const String readAllNotifications = '$baseApi/notifications/read-all';
  
  // Helper methods for path parameters
  static String getRuckEndpoint(String ruckId) => '$ruckById/$ruckId';
  static String getLikesEndpoint(String ruckId) => likes.replaceAll('{id}', ruckId);
  static String getCommentsEndpoint(String ruckId) => comments.replaceAll('{id}', ruckId);
  static String getDeleteCommentEndpoint(String ruckId, String commentId) => 
      deleteComment.replaceAll('{id}', ruckId).replaceAll('{comment_id}', commentId);
  static String getNotificationReadEndpoint(String notificationId) => 
      notificationRead.replaceAll('{id}', notificationId);
}
