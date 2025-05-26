import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/features/notifications/domain/entities/app_notification.dart';
import 'package:rucking_app/features/notifications/presentation/bloc/notification_bloc.dart';
import 'package:rucking_app/features/notifications/presentation/bloc/notification_event.dart';
import 'package:rucking_app/features/notifications/presentation/bloc/notification_state.dart';
import 'package:rucking_app/features/notifications/presentation/widgets/notification_card.dart';
import 'package:rucking_app/features/notifications/util/notification_types.dart';
import 'package:rucking_app/features/ruck_buddies/presentation/pages/ruck_buddy_detail_screen.dart';
import 'package:rucking_app/features/ruck_buddies/domain/entities/ruck_buddy.dart';
import 'package:rucking_app/features/ruck_buddies/domain/entities/user_info.dart';
import 'package:rucking_app/features/ruck_session/data/repositories/session_repository.dart';
import 'package:rucking_app/core/services/api_client.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _notificationBloc = GetIt.I<NotificationBloc>();

  bool _markedAsRead = false;

  @override
  void initState() {
    super.initState();
    // Request notifications to display them
    _notificationBloc.add(const NotificationsRequested());
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _notificationBloc,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Notifications',
            style: AppTextStyles.titleLarge,
          ),
          actions: [
            BlocBuilder<NotificationBloc, NotificationState>(
              builder: (context, state) {
                if (state is NotificationsLoaded && state.unreadCount > 0) {
                  return TextButton(
                    onPressed: () {
                      _notificationBloc.add(const AllNotificationsRead());
                    },
                    child: Text(
                      'Mark all read',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
        body: BlocBuilder<NotificationBloc, NotificationState>(
          builder: (context, state) {
            if (state is NotificationsLoading) {
              return Center(
                child: CircularProgressIndicator(),
              );
            } else if (state is NotificationsLoaded) {
              // Don't automatically mark all as read - let the user see them first
              // They'll be marked as read when the user interacts with them
              
              if (state.notifications.isEmpty) {
                return _buildEmptyState();
              }
              
              return RefreshIndicator(
                onRefresh: () async {
                  _notificationBloc.add(const NotificationsRequested());
                  // Wait for the refresh to complete
                  await Future.delayed(const Duration(milliseconds: 500));
                },
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: state.notifications.length,
                  itemBuilder: (context, index) {
                    final notification = state.notifications[index];
                    return NotificationCard(
                      notification: notification,
                      onTap: () => _handleNotificationTap(notification),
                      onDismiss: () {
                        _notificationBloc.add(NotificationRead(notification.id));
                      },
                    );
                  },
                ),
              );
            } else if (state is NotificationsError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: AppColors.error,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Failed to load notifications',
                      style: AppTextStyles.bodyLarge,
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () {
                        _notificationBloc.add(const NotificationsRequested());
                      },
                      child: const Text('Try Again'),
                    ),
                  ],
                ),
              );
            }
            
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_none,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No notifications yet',
            style: AppTextStyles.titleMedium.copyWith(
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You\'ll see notifications about likes, comments, and other activity here',
            style: AppTextStyles.bodyMedium.copyWith(
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _handleNotificationTap(AppNotification notification) {
    // Mark as read first
    _notificationBloc.add(NotificationRead(notification.id));
    
    // Show loading indicator
    final loadingDialog = showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Dialog(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading details...'),
            ],
          ),
        ),
      ),
    );
    
    // Then navigate based on notification type and data
    if (notification.data != null) {
      switch (notification.type) {
        case NotificationType.like:
        case NotificationType.comment:
          final ruckId = notification.data!['ruck_id']?.toString();
          if (ruckId != null) {
            // Create the session repository with the API client
            final sessionRepo = SessionRepository(apiClient: GetIt.I<ApiClient>());
            
            // Close loading dialog first
            Navigator.of(context, rootNavigator: true).pop();

            // Create a minimal RuckBuddy with just the ID
            // This is the approach used by the regular flow
            // The RuckBuddyDetailScreen will handle loading the full data including username
            final ruckBuddy = RuckBuddy(
              id: ruckId,
              userId: '',
              ruckWeightKg: 0,
              durationSeconds: 0,
              distanceKm: 0,
              caloriesBurned: 0,
              elevationGainM: 0,
              elevationLossM: 0,
              createdAt: DateTime.now(),
              user: UserInfo(id: '', username: '', gender: ''),
            );
            
            // Navigate to the detail screen with just the ID
            // This lets the detail screen's normal data loading flow handle everything
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
        
        case NotificationType.follow:
          Navigator.of(context, rootNavigator: true).pop(); // Close loading dialog
          // Navigate to user profile in the future
          break;
          
        case NotificationType.system:
          Navigator.of(context, rootNavigator: true).pop(); // Close loading dialog
          // Handle system notifications
          break;
          
        default:
          Navigator.of(context, rootNavigator: true).pop(); // Close loading dialog
          // No specific handling for unknown types
          break;
      }
    } else {
      // No notification data, close loading dialog
      Navigator.of(context, rootNavigator: true).pop();
    }
  }
}
