import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vibration/vibration.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/notifications/domain/entities/app_notification.dart';
import 'package:rucking_app/features/notifications/domain/repositories/notification_repository.dart';
import 'package:rucking_app/features/notifications/presentation/bloc/notification_event.dart';
import 'package:rucking_app/features/notifications/presentation/bloc/notification_state.dart';

class NotificationBloc extends Bloc<NotificationEvent, NotificationState> {
  final NotificationRepository repository;
  Timer? _pollingTimer;
  int _previousUnreadCount = 0;

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
      
      // Vibrate if there are new notifications (unread count increased)
      if (unreadCount > _previousUnreadCount && _previousUnreadCount > 0) {
        _vibrateForNewNotification();
        AppLogger.info('New notification(s) received - vibrating phone');
      }
      
      _previousUnreadCount = unreadCount;
      
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
          _previousUnreadCount = newUnreadCount; // Update tracked count
          
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
          
          _previousUnreadCount = 0; // Update tracked count
          
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
  /// Default interval is 90 seconds to stay under the 50/hour rate limit
  void startPolling({Duration interval = const Duration(seconds: 90)}) {
    // Cancel any existing timer
    _pollingTimer?.cancel();
    
    // Create new timer with appropriate interval
    _pollingTimer = Timer.periodic(interval, (_) {
      add(const NotificationsRequested());
    });
    
    // Log the polling interval for debugging
    AppLogger.info('Starting notification polling with interval: ${interval.inSeconds} seconds');
  }

  /// Stop polling for new notifications
  void stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  /// Pause polling (for app lifecycle management)
  void pausePolling() {
    AppLogger.info('Pausing notification polling');
    stopPolling();
  }

  /// Resume polling (for app lifecycle management)
  void resumePolling({Duration interval = const Duration(seconds: 90)}) {
    AppLogger.info('Resuming notification polling');
    startPolling(interval: interval);
  }

  void _vibrateForNewNotification() async {
    if (await Vibration.hasVibrator()) {
      // Fast, intense vibration pattern: 3 quick bursts
      await Vibration.vibrate(pattern: [50, 50, 50, 50, 50]);
    }
  }

  @override
  Future<void> close() {
    stopPolling();
    return super.close();
  }
}
