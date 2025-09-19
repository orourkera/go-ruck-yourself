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
  Timer? _fallbackTimer;
  bool _isFallbackPolling = false;
  Duration _fallbackInterval = const Duration(minutes: 2);

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
      AppLogger.sessionCompletion('Loading notifications started', context: {
        'previous_unread_count': _previousUnreadCount,
        'current_state_loading': state.isLoading,
      });
      emit(state.copyWith(isLoading: true));

      final notifications = await repository.getNotifications();
      final unreadCount = notifications.where((n) => !n.isRead).length;

      AppLogger.sessionCompletion('Notifications loaded successfully',
          context: {
            'total_notifications': notifications.length,
            'unread_count': unreadCount,
            'previous_unread_count': _previousUnreadCount,
            'notification_types':
                notifications.map((n) => n.type).toSet().toList(),
          });

      // Check if we have new notifications and should vibrate
      if (unreadCount > _previousUnreadCount && _previousUnreadCount >= 0) {
        AppLogger.sessionCompletion(
            'New notifications detected - triggering vibration',
            context: {
              'new_unread_count': unreadCount,
              'previous_unread_count': _previousUnreadCount,
              'new_notifications_count': unreadCount - _previousUnreadCount,
            });
        await _vibrateForNewNotification();
      } else {
        AppLogger.sessionCompletion('No new notifications detected', context: {
          'current_unread_count': unreadCount,
          'previous_unread_count': _previousUnreadCount,
          'is_initialized': _previousUnreadCount >= 0,
        });
      }

      _previousUnreadCount = unreadCount;

      emit(state.copyWith(
        isLoading: false,
        notifications: notifications,
        unreadCount: unreadCount,
        hasError: false,
        error: '',
      ));

      AppLogger.sessionCompletion('Notification state updated successfully',
          context: {
            'final_unread_count': unreadCount,
            'total_notifications': notifications.length,
          });
    } catch (e) {
      AppLogger.sessionCompletion('Error loading notifications', context: {
        'error': e.toString(),
        'error_type': e.runtimeType.toString(),
        'previous_unread_count': _previousUnreadCount,
      });
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
      final success =
          await repository.markNotificationAsRead(event.notificationId);
      if (success) {
        final updatedNotifications = state.notifications.map((notification) {
          if (notification.id == event.notificationId) {
            return notification.copyWith(isRead: true);
          }
          return notification;
        }).toList();

        final newUnreadCount =
            updatedNotifications.where((n) => !n.isRead).length;
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
  bool get isFallbackPolling => _isFallbackPolling;

  void startFallbackPolling({Duration interval = const Duration(minutes: 2)}) {
    AppLogger.sessionCompletion('Starting fallback notification polling',
        context: {
          'interval_seconds': interval.inSeconds,
          'already_active': _fallbackTimer?.isActive ?? false,
        });

    _isFallbackPolling = true;
    _fallbackInterval = interval;
    _fallbackTimer?.cancel();
    add(const NotificationsRequested());
    _fallbackTimer = Timer.periodic(interval, (_) {
      add(const NotificationsRequested());
    });
  }

  /// Stop polling for new notifications
  void stopPolling() {
    AppLogger.sessionCompletion('Stopping fallback notification polling',
        context: {
          'timer_was_active': _fallbackTimer?.isActive ?? false,
        });
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    _isFallbackPolling = false;
  }

  /// Pause polling (for app lifecycle management)
  void pausePolling() {
    if (!_isFallbackPolling) return;
    AppLogger.sessionCompletion('Pausing fallback notification polling',
        context: {
          'timer_was_active': _fallbackTimer?.isActive ?? false,
        });
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
  }

  /// Resume polling (for app lifecycle management)
  void resumePolling({Duration? interval}) {
    if (!_isFallbackPolling) return;
    AppLogger.sessionCompletion('Resuming fallback notification polling',
        context: {
          'interval_seconds': (interval ?? _fallbackInterval).inSeconds,
        });
    startFallbackPolling(interval: interval ?? _fallbackInterval);
  }

  Future<void> _vibrateForNewNotification() async {
    try {
      AppLogger.sessionCompletion('Attempting vibration for new notification',
          context: {});

      // Check if vibration is available
      bool? hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator != true) {
        AppLogger.sessionCompletion('Device vibration not supported', context: {
          'has_vibrator': hasVibrator,
        });
        return;
      }

      // Check custom vibration support
      bool? hasCustomVibrations = await Vibration.hasCustomVibrationsSupport();

      AppLogger.sessionCompletion('Vibration capabilities checked', context: {
        'has_vibrator': hasVibrator,
        'has_custom_vibrations': hasCustomVibrations,
      });

      if (hasCustomVibrations == true) {
        // Use pattern vibration: short-pause-short-pause-long
        await Vibration.vibrate(pattern: [0, 200, 100, 200, 100, 500]);
        AppLogger.sessionCompletion('Custom pattern vibration completed',
            context: {
              'pattern_used': [0, 200, 100, 200, 100, 500],
            });
      } else {
        // Use simple vibration
        await Vibration.vibrate(duration: 300);
        AppLogger.sessionCompletion('Simple vibration completed', context: {
          'duration_ms': 300,
        });
      }
    } catch (e) {
      AppLogger.sessionCompletion('Vibration failed', context: {
        'error': e.toString(),
        'error_type': e.runtimeType.toString(),
      });
      AppLogger.error('❌ Failed to vibrate: $e');
    }
  }

  @override
  Future<void> close() {
    stopPolling();
    return super.close();
  }
}
