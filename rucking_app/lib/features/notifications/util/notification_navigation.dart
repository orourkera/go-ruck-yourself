import 'package:flutter/material.dart';
import 'package:rucking_app/features/notifications/domain/entities/app_notification.dart';
import 'package:rucking_app/features/notifications/util/notification_types.dart';
import 'package:rucking_app/features/ruck_buddies/presentation/pages/ruck_buddy_detail_screen.dart';
import 'package:rucking_app/features/ruck_buddies/domain/entities/ruck_buddy.dart';
import 'package:rucking_app/features/ruck_buddies/domain/entities/user_info.dart';
import 'package:rucking_app/features/duels/presentation/screens/duel_detail_screen.dart';
import 'package:rucking_app/features/clubs/presentation/screens/club_detail_screen.dart';
import 'package:rucking_app/features/events/presentation/screens/event_detail_screen.dart';
import 'package:rucking_app/features/profile/presentation/screens/public_profile_screen.dart';

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
      case NotificationType.like:
      case NotificationType.comment:
      case NotificationType.system:  // Handle system notifications like first ruck completion
      case NotificationType.achievement:  // If there's an achievement type for first ruck
      case NotificationType.firstRuckCelebration:  // First ruck celebration notifications
      case NotificationType.firstRuckGlobal:  // First ruck global notifications
      case NotificationType.ruckComment:  // Ruck comment notifications
      case NotificationType.ruckLike:  // Ruck like notifications
      case NotificationType.ruckActivity:  // Ruck activity notifications (when others comment/like rucks you've interacted with)
        final ruckId = notification.data!['ruck_id']?.toString();
        if (ruckId != null) {
          // Create a minimal RuckBuddy with just the ruck ID
          // The detail screen will fetch the complete ruck data including the owner's profile
          final ruckBuddy = RuckBuddy(
            id: ruckId,
            userId: '',  // Leave empty - let detail screen fetch the correct ruck owner
            ruckWeightKg: 0,
            durationSeconds: 0,
            distanceKm: 0,
            caloriesBurned: 0,
            elevationGainM: 0,
            elevationLossM: 0,
            createdAt: DateTime.now(),
            user: UserInfo(
              id: '',      // Leave empty - will be populated with ruck owner's info
              username: '', // Leave empty to trigger full data fetch in detail screen
              gender: '',   // Leave empty, will be properly set when profile is fetched
            ),
            locationPoints: null, // Will be loaded by detail screen
            photos: null, // Will be loaded by detail screen
          );
          
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => RuckBuddyDetailScreen(
                ruckBuddy: ruckBuddy,
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
        final ruckId = notification.data!['ruck_id']?.toString();  // Fallback to ruck if present
        if (ruckId != null) {
          // Reuse the same minimal RuckBuddy creation and navigation as above
          final ruckBuddy = RuckBuddy(
            id: ruckId,
            userId: '',  // Leave empty - let detail screen fetch the correct ruck owner
            ruckWeightKg: 0,
            durationSeconds: 0,
            distanceKm: 0,
            caloriesBurned: 0,
            elevationGainM: 0,
            elevationLossM: 0,
            createdAt: DateTime.now(),
            user: UserInfo(
              id: '',      // Leave empty - will be populated with ruck owner's info
              username: '', // Leave empty to trigger full data fetch in detail screen
              gender: '',   // Leave empty, will be properly set when profile is fetched
            ),
            locationPoints: null, // Will be loaded by detail screen
            photos: null, // Will be loaded by detail screen
          );
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => RuckBuddyDetailScreen(ruckBuddy: ruckBuddy),
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
            SnackBar(content: Text('Unhandled notification type: ${notification.type}')),
          );
        }
        break;
    }
  }
}
