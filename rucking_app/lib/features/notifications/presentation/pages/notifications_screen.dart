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

  @override
  void initState() {
    super.initState();
    // First, request notifications to display them
    _notificationBloc.add(const NotificationsRequested());
    
    // Mark all notifications as read when screen is opened
    // Add a small delay to ensure notifications are loaded first
    Future.delayed(const Duration(milliseconds: 300), () {
      _notificationBloc.add(const AllNotificationsRead());
    });
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
            
            // Fetch the full session details before navigating
            sessionRepo.fetchSessionById(ruckId).then((session) {
              // Close loading dialog
              Navigator.of(context, rootNavigator: true).pop();
              
              if (session != null) {
                // Create a proper RuckBuddy from the session data
                // Use default/empty values for fields that aren't available in RuckSession
                final ruckBuddy = RuckBuddy(
                  id: session.id ?? '',
                  userId: '', // No userId in RuckSession
                  ruckWeightKg: session.ruckWeightKg,
                  durationSeconds: session.duration.inSeconds,
                  distanceKm: session.distance,
                  caloriesBurned: session.caloriesBurned,
                  elevationGainM: session.elevationGain,
                  elevationLossM: session.elevationLoss,
                  createdAt: session.startTime,
                  completedAt: session.endTime,
                  locationPoints: session.locationPoints,
                  user: UserInfo(
                    id: '', // No user info in RuckSession
                    username: '', // Default empty username
                    gender: '', // Default empty gender
                  ),
                );
                
                // Navigate to the detail screen with the full data
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => RuckBuddyDetailScreen(
                      ruckBuddy: ruckBuddy,
                      focusComment: notification.type == NotificationType.comment,
                    ),
                  ),
                );
              } else {
                // Show error snackbar if session couldn't be loaded
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Could not load ruck details'),
                    duration: Duration(seconds: 3),
                  ),
                );
              }
            }).catchError((error) {
              // Close loading dialog and show error
              Navigator.of(context, rootNavigator: true).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error loading ruck: ${error.toString()}'),
                  duration: const Duration(seconds: 3),
                ),
              );
            });
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
