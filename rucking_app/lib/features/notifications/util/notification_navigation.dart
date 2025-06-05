import 'package:flutter/material.dart';
import 'package:rucking_app/features/notifications/domain/entities/app_notification.dart';
import 'package:rucking_app/features/notifications/util/notification_types.dart';
import 'package:rucking_app/features/ruck_buddies/presentation/pages/ruck_buddy_detail_screen.dart';
import 'package:rucking_app/features/duels/presentation/screens/duel_detail_screen.dart';

/// Helper class for handling notification-related navigation
class NotificationNavigation {
  /// Navigate to the appropriate screen based on the notification type and data
  static void navigateToNotificationDestination(
    BuildContext context,
    AppNotification notification,
  ) {
    if (notification.data == null) return;

    switch (notification.type) {
      case NotificationType.like:
      case NotificationType.comment:
        final ruckId = notification.data!['ruck_id']?.toString();
        if (ruckId != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => RuckBuddyDetailScreen(ruckId: ruckId),
            ),
          );
        }
        break;
      case NotificationType.duelComment:
      case NotificationType.duelInvitation:
      case NotificationType.duelJoined:
      case NotificationType.duelCompleted:
        final duelId = notification.data!['duel_id']?.toString();
        if (duelId != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DuelDetailScreen(duelId: duelId),
            ),
          );
        }
        break;
      case NotificationType.follow:
        // Handle follow notifications when user profiles are implemented
        break;
      case NotificationType.system:
        // Handle system notifications
        break;
      default:
        // No specific handling for unknown types
        break;
    }
  }
}
