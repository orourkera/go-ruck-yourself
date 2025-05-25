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
      final response = await apiClient.get('/notifications');
      
      List<dynamic> notificationsData;
      if (response is Map<String, dynamic> && response.containsKey('notifications')) {
        notificationsData = response['notifications'] as List<dynamic>;
      } else if (response is List) {
        notificationsData = response;
      } else {
        AppLogger.warning('Unexpected notifications response format: ${response.runtimeType}');
        return [];
      }
      
      return notificationsData
          .map((json) => NotificationModel.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppLogger.error('Failed to fetch notifications: $e');
      throw ServerException(message: 'Failed to fetch notifications: $e');
    }
  }
  
  @override
  Future<bool> markNotificationAsRead(String notificationId) async {
    try {
      final endpoint = ApiEndpoints.getNotificationReadEndpoint(notificationId);
      await apiClient.put(endpoint, {});
      return true;
    } catch (e) {
      AppLogger.error('Failed to mark notification as read: $e');
      throw ServerException(message: 'Failed to mark notification as read: $e');
    }
  }
  
  @override
  Future<bool> markAllNotificationsAsRead() async {
    try {
      await apiClient.put(ApiEndpoints.readAllNotifications, {});
      return true;
    } catch (e) {
      AppLogger.error('Failed to mark all notifications as read: $e');
      throw ServerException(message: 'Failed to mark all notifications as read: $e');
    }
  }
}
