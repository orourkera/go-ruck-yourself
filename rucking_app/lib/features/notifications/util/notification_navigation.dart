import 'package:flutter/material.dart';
import 'package:rucking_app/features/notifications/domain/entities/app_notification.dart';
import 'package:rucking_app/features/notifications/util/notification_types.dart';
import 'package:rucking_app/features/ruck_buddies/presentation/pages/ruck_buddy_detail_screen.dart';
import 'package:rucking_app/features/duels/presentation/screens/duel_detail_screen.dart';
import 'package:rucking_app/features/clubs/presentation/screens/club_detail_screen.dart';
import 'package:rucking_app/features/events/presentation/screens/event_detail_screen.dart';
import 'package:rucking_app/features/profile/presentation/screens/public_profile_screen.dart';
import 'package:rucking_app/features/live_following/presentation/screens/live_ruck_following_screen.dart';

/// Helper class for handling notification-related navigation
class NotificationNavigation {
  /// Check if a notification type is comment-related and should focus the comment input
  static bool _isCommentNotification(String notificationType) {
    return notificationType == NotificationType.comment ||
        notificationType == NotificationType.ruckComment ||
        notificationType == NotificationType.ruckActivity;
  }

  /// Navigate to the appropriate screen based on the notification type and data
  static void navigateToNotificationDestination(
    BuildContext context,
    AppNotification notification,
  ) {
    if (notification.data == null) return;

    switch (notification.type) {
      case NotificationType.ruckStarted: // Navigate to live following
      case NotificationType.ruckMessage: // Navigate to live following
        final ruckId = notification.data!['ruck_id']?.toString();
        final ruckerName = notification.data!['rucker_name']?.toString() ??
                          notification.data!['sender_name']?.toString() ??
                          'Rucker';
        if (ruckId != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => LiveRuckFollowingScreen(
                ruckId: ruckId,
                ruckerName: ruckerName,
              ),
            ),
          );
        }
        break;
      case NotificationType.like:
      case NotificationType.comment:
      case NotificationType
            .system: // Handle system notifications like first ruck completion
      case NotificationType
            .achievement: // If there's an achievement type for first ruck
      case NotificationType
            .firstRuckCelebration: // First ruck celebration notifications
      case NotificationType.firstRuckGlobal: // First ruck global notifications
      case NotificationType.ruckComment: // Ruck comment notifications
      case NotificationType.ruckLike: // Ruck like notifications
      case NotificationType
            .ruckActivity: // Ruck activity notifications (when others comment/like rucks you've interacted with)
        final ruckId = notification.data!['ruck_id']?.toString();
        if (ruckId != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => RuckBuddyDetailScreen.fromRuckId(
                ruckId,
                focusComment: _isCommentNotification(notification.type),
              ),
            ),
          );
        }
        break;
      case NotificationType.duelComment:
      case NotificationType.duelInvitation:
      case NotificationType.duelJoined:
      case NotificationType.duelCompleted:
      case NotificationType.duelProgress:
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
      case NotificationType.clubEventCreated:
        final clubId = notification.data!['club_id']?.toString();
        final eventId = notification.data!['event_id']?.toString();
        if (eventId != null) {
          // Navigate to specific event detail screen
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EventDetailScreen(eventId: eventId),
            ),
          );
        } else if (clubId != null) {
          // Fallback to club detail if no event ID
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ClubDetailScreen(clubId: clubId),
            ),
          );
        }
        break;
      case NotificationType.clubMembershipRequest:
      case NotificationType.clubMembershipApproved:
      case NotificationType.clubMembershipRejected:
        final clubId = notification.data!['club_id']?.toString();
        if (clubId != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ClubDetailScreen(clubId: clubId),
            ),
          );
        }
        break;
      case NotificationType.follow:
        // Navigate to the follower's public profile page
        final followerId = notification.data!['follower_id']?.toString() ??
            notification.data!['user_id']?.toString();
        if (followerId != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PublicProfileScreen(userId: followerId),
            ),
          );
        }
        break;
      default:
        // For unknown notification types, try to navigate to club details if club_id is present
        final clubId = notification.data!['club_id']?.toString();
        final ruckId = notification.data!['ruck_id']
            ?.toString(); // Fallback to ruck if present
        if (ruckId != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  RuckBuddyDetailScreen.fromRuckId(ruckId),
            ),
          );
        } else if (clubId != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ClubDetailScreen(clubId: clubId),
            ),
          );
        } else {
          // Show a snackbar or dialog for unhandled notifications
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text('Unhandled notification type: ${notification.type}')),
          );
        }
        break;
    }
  }
}
