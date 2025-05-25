import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/notifications/domain/entities/app_notification.dart';
import 'package:rucking_app/features/notifications/domain/repositories/notification_repository.dart';
import 'package:rucking_app/features/notifications/presentation/bloc/notification_event.dart';
import 'package:rucking_app/features/notifications/presentation/bloc/notification_state.dart';

class NotificationBloc extends Bloc<NotificationEvent, NotificationState> {
  final NotificationRepository repository;
  Timer? _pollingTimer;

  NotificationBloc({required this.repository}) : super(NotificationsInitial()) {
    on<NotificationsRequested>(_onNotificationsRequested);
    on<NotificationRead>(_onNotificationRead);
    on<AllNotificationsRead>(_onAllNotificationsRead);
  }

  Future<void> _onNotificationsRequested(
    NotificationsRequested event,
    Emitter<NotificationState> emit,
  ) async {
    emit(NotificationsLoading());
    try {
      final notifications = await repository.getNotifications();
      final unreadCount = notifications.where((n) => !n.isRead).length;
      emit(NotificationsLoaded(
        notifications: notifications,
        unreadCount: unreadCount,
      ));
    } catch (e) {
      AppLogger.error('Failed to load notifications: $e');
      emit(NotificationsError(message: 'Failed to load notifications'));
    }
  }

  Future<void> _onNotificationRead(
    NotificationRead event,
    Emitter<NotificationState> emit,
  ) async {
    final currentState = state;
    if (currentState is NotificationsLoaded) {
      try {
        final success = await repository.markNotificationAsRead(event.notificationId);
        if (success) {
          final updatedNotifications = currentState.notifications.map((notification) {
            if (notification.id == event.notificationId) {
              return notification.copyWith(isRead: true);
            }
            return notification;
          }).toList();
          
          final newUnreadCount = updatedNotifications.where((n) => !n.isRead).length;
          
          emit(currentState.copyWith(
            notifications: updatedNotifications,
            unreadCount: newUnreadCount,
          ));
        }
      } catch (e) {
        AppLogger.error('Failed to mark notification as read: $e');
        // We don't emit an error state here to preserve the current notifications list
      }
    }
  }

  Future<void> _onAllNotificationsRead(
    AllNotificationsRead event,
    Emitter<NotificationState> emit,
  ) async {
    final currentState = state;
    if (currentState is NotificationsLoaded) {
      try {
        final success = await repository.markAllNotificationsAsRead();
        if (success) {
          final updatedNotifications = currentState.notifications
              .map((notification) => notification.copyWith(isRead: true))
              .toList();
          
          emit(currentState.copyWith(
            notifications: updatedNotifications,
            unreadCount: 0,
          ));
        }
      } catch (e) {
        AppLogger.error('Failed to mark all notifications as read: $e');
        // We don't emit an error state here to preserve the current notifications list
      }
    }
  }

  /// Start polling for new notifications
  void startPolling({Duration interval = const Duration(seconds: 30)}) {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(interval, (_) {
      add(const NotificationsRequested());
    });
  }

  /// Stop polling for new notifications
  void stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  @override
  Future<void> close() {
    stopPolling();
    return super.close();
  }
}
