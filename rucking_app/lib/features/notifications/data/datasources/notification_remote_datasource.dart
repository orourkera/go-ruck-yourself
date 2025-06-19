import 'package:rucking_app/core/network/api_endpoints.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/error/exceptions.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/notifications/data/models/notification_model.dart';

abstract class NotificationRemoteDataSource {
  /// Gets all notifications for the current user
  Future<List<NotificationModel>> getNotifications();
  
  /// Marks a specific notification as read
  Future<bool> markNotificationAsRead(String notificationId);
  
  /// Marks all notifications as read
  Future<bool> markAllNotificationsAsRead();
}

class NotificationRemoteDataSourceImpl implements NotificationRemoteDataSource {
  final ApiClient apiClient;
  
  NotificationRemoteDataSourceImpl({required this.apiClient});
  
  @override
  Future<List<NotificationModel>> getNotifications() async {
    try {
      AppLogger.info('Fetching notifications from /notifications endpoint...');
      final response = await apiClient.get('/notifications');
      AppLogger.info('Notifications API response received: ${response.runtimeType}');
      
      List<dynamic> notificationsData;
      if (response is Map<String, dynamic> && response.containsKey('notifications')) {
        notificationsData = response['notifications'] as List<dynamic>;
        AppLogger.info('Found ${notificationsData.length} notifications in response');
      } else if (response is List) {
        notificationsData = response;
        AppLogger.info('Response is direct list with ${notificationsData.length} notifications');
      } else {
        AppLogger.warning('Unexpected notifications response format: ${response.runtimeType}');
        AppLogger.warning('Response content: $response');
        return [];
      }
      
      final notifications = notificationsData
          .map((json) => NotificationModel.fromJson(json as Map<String, dynamic>))
          .toList();
      
      final unreadCount = notifications.where((n) => !n.isRead).length;
      AppLogger.info('Successfully parsed ${notifications.length} notifications (${unreadCount} unread)');
      
      return notifications;
    } catch (e) {
      AppLogger.error('Failed to fetch notifications: $e');
      throw ServerException(message: 'Failed to fetch notifications: $e');
    }
  }
  
  @override
  Future<bool> markNotificationAsRead(String notificationId) async {
    try {
      final endpoint = ApiEndpoints.getNotificationReadEndpoint(notificationId);
      AppLogger.info('Marking notification as read: $notificationId at endpoint: $endpoint');
      // Changed from PUT to POST to match the backend API implementation
      final response = await apiClient.post(endpoint, {});
      AppLogger.info('Mark notification read response: $response');
      return true;
    } catch (e) {
      AppLogger.error('Failed to mark notification as read: $e');
      throw ServerException(message: 'Failed to mark notification as read: $e');
    }
  }
  
  @override
  Future<bool> markAllNotificationsAsRead() async {
    try {
      // Ensure we're not using a duplicated /api prefix like we saw with user profiles
      final endpoint = '/notifications/read-all';
      AppLogger.info('Marking all notifications as read at endpoint: $endpoint');
      // Changed from PUT to POST to match the backend API implementation
      final response = await apiClient.post(endpoint, {});
      AppLogger.info('Mark all notifications read response: $response');
      return true;
    } catch (e) {
      AppLogger.error('Failed to mark all notifications as read: $e');
      throw ServerException(message: 'Failed to mark all notifications as read: $e');
    }
  }
}
