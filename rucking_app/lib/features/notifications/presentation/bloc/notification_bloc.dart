import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vibration/vibration.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/notifications/domain/entities/app_notification.dart';
import 'package:rucking_app/features/notifications/domain/repositories/notification_repository.dart';
import 'package:rucking_app/features/notifications/presentation/bloc/notification_event.dart';
import 'package:rucking_app/features/notifications/presentation/bloc/notification_state.dart';

export 'package:rucking_app/features/notifications/presentation/bloc/notification_event.dart';
export 'package:rucking_app/features/notifications/presentation/bloc/notification_state.dart';

class NotificationBloc extends Bloc<NotificationEvent, NotificationState> {
  final NotificationRepository repository;
  int _previousUnreadCount = -1; // -1 means uninitialized
  Timer? _pollingTimer;
  
  NotificationBloc({
    required this.repository,
  }) : super(const NotificationState()) {
    on<NotificationsRequested>(_onNotificationsRequested);
    on<NotificationRead>(_onNotificationRead);
    on<AllNotificationsRead>(_onAllNotificationsRead);
  }

  Future<void> _onNotificationsRequested(
    NotificationsRequested event,
    Emitter<NotificationState> emit,
  ) async {
    try {
      AppLogger.info('Loading notifications...');
      emit(state.copyWith(isLoading: true));
      
      final notifications = await repository.getNotifications();
      final unreadCount = notifications.where((n) => !n.isRead).length;
      
      AppLogger.info('Loaded ${notifications.length} notifications, ${unreadCount} unread');
      AppLogger.info('Previous unread count: $_previousUnreadCount, Current: $unreadCount');
      
      // Check if we have new notifications and should vibrate
      if (unreadCount > _previousUnreadCount && _previousUnreadCount >= 0) {
        AppLogger.info('New notifications detected! Triggering vibration...');
        await _vibrateForNewNotification();
      } else {
        AppLogger.info('No new notifications detected');
      }
      
      _previousUnreadCount = unreadCount;
      
      emit(state.copyWith(
        isLoading: false,
        notifications: notifications,
        unreadCount: unreadCount,
        hasError: false,
        error: '',
      ));
      
      AppLogger.info('Notification state updated successfully');
    } catch (e) {
      AppLogger.error('Error loading notifications: $e');
      emit(state.copyWith(
        isLoading: false,
        hasError: true,
        error: e.toString(),
      ));
    }
  }

  Future<void> _onNotificationRead(
    NotificationRead event,
    Emitter<NotificationState> emit,
  ) async {
    try {
      final success = await repository.markNotificationAsRead(event.notificationId);
      if (success) {
        final updatedNotifications = state.notifications.map((notification) {
          if (notification.id == event.notificationId) {
            return notification.copyWith(isRead: true);
          }
          return notification;
        }).toList();
        
        final newUnreadCount = updatedNotifications.where((n) => !n.isRead).length;
        _previousUnreadCount = newUnreadCount; // Update tracked count
        
        emit(state.copyWith(
          notifications: updatedNotifications,
          unreadCount: newUnreadCount,
        ));
      }
    } catch (e) {
      AppLogger.error('Failed to mark notification as read: $e');
      // We don't emit an error state here to preserve the current notifications list
    }
  }

  Future<void> _onAllNotificationsRead(
    AllNotificationsRead event,
    Emitter<NotificationState> emit,
  ) async {
    try {
      final success = await repository.markAllNotificationsAsRead();
      if (success) {
        final updatedNotifications = state.notifications
            .map((notification) => notification.copyWith(isRead: true))
            .toList();
        
        _previousUnreadCount = 0; // Update tracked count
        
        emit(state.copyWith(
          notifications: updatedNotifications,
          unreadCount: 0,
        ));
      }
    } catch (e) {
      AppLogger.error('Failed to mark all notifications as read: $e');
      // We don't emit an error state here to preserve the current notifications list
    }
  }

  /// Start polling for new notifications
  /// Default interval is 90 seconds to stay under the 50/hour rate limit
  void startPolling({Duration interval = const Duration(seconds: 90)}) {
    // Immediately fetch notifications so UI badge is up-to-date on app launch
    add(const NotificationsRequested());
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

  Future<void> _vibrateForNewNotification() async {
    try {
      AppLogger.info('🔔 Attempting to vibrate for new notification...');
      
      // Check if vibration is available
      bool? hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator != true) {
        AppLogger.warning('Device does not support vibration');
        return;
      }
      
      // Check custom vibration support
      bool? hasCustomVibrations = await Vibration.hasCustomVibrationsSupport();
      
      if (hasCustomVibrations == true) {
        // Use pattern vibration: short-pause-short-pause-long
        await Vibration.vibrate(pattern: [0, 200, 100, 200, 100, 500]);
        AppLogger.info('✅ Custom pattern vibration triggered');
      } else {
        // Use simple vibration
        await Vibration.vibrate(duration: 300);
        AppLogger.info('✅ Simple vibration triggered');
      }
    } catch (e) {
      AppLogger.error('❌ Failed to vibrate: $e');
    }
  }

  @override
  Future<void> close() {
    stopPolling();
    return super.close();
  }
}
