import 'package:equatable/equatable.dart';

abstract class NotificationEvent extends Equatable {
  const NotificationEvent();

  @override
  List<Object> get props => [];
}

/// Event to request notifications from API
class NotificationsRequested extends NotificationEvent {
  const NotificationsRequested();
}

/// Event when a notification is marked as read
class NotificationRead extends NotificationEvent {
  final String notificationId;

  const NotificationRead(this.notificationId);

  @override
  List<Object> get props => [notificationId];
}

/// Event when all notifications are marked as read
class AllNotificationsRead extends NotificationEvent {
  const AllNotificationsRead();
}
