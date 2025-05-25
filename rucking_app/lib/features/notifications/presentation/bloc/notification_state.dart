import 'package:equatable/equatable.dart';
import 'package:rucking_app/features/notifications/domain/entities/app_notification.dart';

abstract class NotificationState extends Equatable {
  const NotificationState();
  
  @override
  List<Object> get props => [];
}

class NotificationsInitial extends NotificationState {}

class NotificationsLoading extends NotificationState {}

class NotificationsLoaded extends NotificationState {
  final List<AppNotification> notifications;
  final int unreadCount;
  
  const NotificationsLoaded({
    required this.notifications,
    required this.unreadCount,
  });
  
  @override
  List<Object> get props => [notifications, unreadCount];
  
  NotificationsLoaded copyWith({
    List<AppNotification>? notifications,
    int? unreadCount,
  }) {
    return NotificationsLoaded(
      notifications: notifications ?? this.notifications,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}

class NotificationsError extends NotificationState {
  final String message;
  
  const NotificationsError({required this.message});
  
  @override
  List<Object> get props => [message];
}
