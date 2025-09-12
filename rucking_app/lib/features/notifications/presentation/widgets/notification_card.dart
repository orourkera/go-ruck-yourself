import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/features/notifications/domain/entities/app_notification.dart';
import 'package:rucking_app/features/notifications/util/notification_types.dart';

class NotificationCard extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;
  final VoidCallback? onDismiss;

  const NotificationCard({
    Key? key,
    required this.notification,
    required this.onTap,
    this.onDismiss,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(notification.id),
      direction: onDismiss != null
          ? DismissDirection.endToStart
          : DismissDirection.none,
      onDismissed: (_) => onDismiss?.call(),
      background: Container(
        color: AppColors.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16.0),
        child: const Icon(
          Icons.delete_outline,
          color: Colors.white,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          decoration: BoxDecoration(
            color: notification.isRead
                ? Colors.white
                : AppColors.backgroundLight.withOpacity(0.5),
            border: Border(
              bottom: BorderSide(
                color: AppColors.greyLight,
                width: 1.0,
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildNotificationIcon(),
              const SizedBox(width: 16.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.message,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: notification.isRead
                            ? FontWeight.normal
                            : FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4.0),
                    Text(
                      _formatTimestamp(notification.createdAt),
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textDarkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (!notification.isRead)
                Container(
                  width: 8.0,
                  height: 8.0,
                  margin: const EdgeInsets.only(top: 8.0),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationIcon() {
    IconData iconData;
    Color iconColor;

    switch (notification.type) {
      case NotificationType.like:
        iconData = Icons.favorite;
        iconColor = Colors.red;
        break;
      case NotificationType.comment:
        iconData = Icons.comment;
        iconColor = Colors.blue;
        break;
      case NotificationType.duelComment:
        iconData = Icons.comment;
        iconColor = Colors.green;
        break;
      case NotificationType.follow:
        iconData = Icons.person_add;
        iconColor = Colors.green;
        break;
      case NotificationType.system:
        iconData = Icons.notifications;
        iconColor = Colors.orange;
        break;
      case NotificationType.clubEventCreated:
        iconData = Icons.event;
        iconColor = AppColors.primary;
        break;
      case NotificationType.clubMembershipRequest:
        iconData = Icons.group_add;
        iconColor = AppColors.primary;
        break;
      case NotificationType.clubMembershipApproved:
        iconData = Icons.group;
        iconColor = Colors.green;
        break;
      case NotificationType.clubMembershipRejected:
        iconData = Icons.group_remove;
        iconColor = Colors.red;
        break;
      default:
        iconData = Icons.notifications;
        iconColor = AppColors.primary;
    }

    return Container(
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(
        iconData,
        color: iconColor,
        size: 20.0,
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays > 7) {
      return DateFormat('MMM d, yyyy').format(timestamp);
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}
