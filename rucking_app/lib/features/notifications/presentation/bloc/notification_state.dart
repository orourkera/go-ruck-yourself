import 'package:equatable/equatable.dart';
import 'package:rucking_app/features/notifications/domain/entities/app_notification.dart';

class NotificationState extends Equatable {
  final List<AppNotification> notifications;
  final int unreadCount;
  final bool isLoading;
  final bool hasError;
  final String error;

  const NotificationState({
    this.notifications = const [],
    this.unreadCount = 0,
    this.isLoading = false,
    this.hasError = false,
    this.error = '',
  });

  @override
  List<Object> get props =>
      [notifications, unreadCount, isLoading, hasError, error];

  NotificationState copyWith({
    List<AppNotification>? notifications,
    int? unreadCount,
    bool? isLoading,
    bool? hasError,
    String? error,
  }) {
    return NotificationState(
      notifications: notifications ?? this.notifications,
      unreadCount: unreadCount ?? this.unreadCount,
      isLoading: isLoading ?? this.isLoading,
      hasError: hasError ?? this.hasError,
      error: error ?? this.error,
    );
  }
}

// Keep these for backward compatibility if needed
class NotificationsInitial extends NotificationState {
  const NotificationsInitial() : super();
}

class NotificationsLoading extends NotificationState {
  const NotificationsLoading() : super(isLoading: true);
}

class NotificationsLoaded extends NotificationState {
  const NotificationsLoaded({
    required List<AppNotification> notifications,
    required int unreadCount,
  }) : super(notifications: notifications, unreadCount: unreadCount);
}

class NotificationsError extends NotificationState {
  const NotificationsError({required String message})
      : super(hasError: true, error: message);
}
