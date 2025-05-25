import 'package:rucking_app/features/notifications/domain/entities/app_notification.dart';

/// Repository interface for notification operations
abstract class NotificationRepository {
  /// Get all notifications for current user
  Future<List<AppNotification>> getNotifications();
  
  /// Mark a specific notification as read
  Future<bool> markNotificationAsRead(String notificationId);
  
  /// Mark all notifications as read
  Future<bool> markAllNotificationsAsRead();
}
