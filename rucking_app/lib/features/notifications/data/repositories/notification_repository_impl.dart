import 'package:rucking_app/core/error/exceptions.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/notifications/data/datasources/notification_remote_datasource.dart';
import 'package:rucking_app/features/notifications/domain/entities/app_notification.dart';
import 'package:rucking_app/features/notifications/domain/repositories/notification_repository.dart';

class NotificationRepositoryImpl implements NotificationRepository {
  final NotificationRemoteDataSource remoteDataSource;

  NotificationRepositoryImpl({required this.remoteDataSource});

  @override
  Future<List<AppNotification>> getNotifications() async {
    try {
      final notificationModels = await remoteDataSource.getNotifications();
      return notificationModels;
    } on ServerException catch (e) {
      AppLogger.error('Repository: Failed to get notifications: ${e.message}');
      return [];
    } catch (e) {
      AppLogger.error('Repository: Unexpected error getting notifications: $e');
      return [];
    }
  }

  @override
  Future<bool> markNotificationAsRead(String notificationId) async {
    try {
      return await remoteDataSource.markNotificationAsRead(notificationId);
    } on ServerException catch (e) {
      AppLogger.error('Repository: Failed to mark notification as read: ${e.message}');
      return false;
    } catch (e) {
      AppLogger.error('Repository: Unexpected error marking notification as read: $e');
      return false;
    }
  }

  @override
  Future<bool> markAllNotificationsAsRead() async {
    try {
      return await remoteDataSource.markAllNotificationsAsRead();
    } on ServerException catch (e) {
      AppLogger.error('Repository: Failed to mark all notifications as read: ${e.message}');
      return false;
    } catch (e) {
      AppLogger.error('Repository: Unexpected error marking all notifications as read: $e');
      return false;
    }
  }
}
