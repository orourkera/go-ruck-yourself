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
          // Note: notification.data!['user_id'] contains the ID of the person who liked/commented,
          // NOT the ruck owner. We want to show the ruck owner's info, so we'll let the detail 
          // screen fetch the correct owner information via the API using the ruck_id.
          
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
                focusComment: notification.type == NotificationType.comment,
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
      case NotificationType.system:
        // Handle system notifications
        break;
      default:
        // For unknown notification types, try to navigate to club details if club_id is present
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
    }
  }
}
