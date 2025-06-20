import 'dart:async';
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
import 'package:rucking_app/features/duels/presentation/screens/duel_detail_screen.dart';
import 'package:rucking_app/features/clubs/presentation/screens/club_detail_screen.dart';
import 'package:rucking_app/features/events/presentation/screens/event_detail_screen.dart';

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
    // Stop any notification polling while viewing notifications screen
    _notificationBloc.stopPolling();
    
    // Request notifications to display them
    _notificationBloc.add(const NotificationsRequested());
  }

  @override
  void dispose() {
    // When leaving screen, restart polling with a delay to ensure our reads are processed
    Future.delayed(const Duration(seconds: 3), () {
      if (_notificationBloc.state is NotificationState) {
        _notificationBloc.startPolling();
      }
    });
    super.dispose();
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
                if (state.unreadCount > 0) {
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
            if (state.isLoading) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            } else if (state.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Error loading notifications',
                      style: AppTextStyles.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      state.error,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: Colors.grey[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        _notificationBloc.add(const NotificationsRequested());
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            } else {
              // Mark all notifications as read when screen is displayed and there are unread ones
              if (state.unreadCount > 0) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _notificationBloc.add(const AllNotificationsRead());
                });
              }
              
              if (state.notifications.isEmpty) {
                return _buildEmptyState();
              }
              
              return RefreshIndicator(
                onRefresh: () async {
                  _notificationBloc.add(const NotificationsRequested());
                },
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: state.notifications.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final notification = state.notifications[index];
                    return NotificationCard(
                      notification: notification,
                      onTap: () => _handleNotificationTap(notification),
                    );
                  },
                ),
              );
            }
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
        case 'duel_comment':
        case 'duel_joined':
        case 'duel_started':
        case 'duel_completed':
        case 'duel_progress':
        case 'duel_deleted':
          final duelId = notification.data?['duel_id']?.toString();
          final commentId = notification.data?['duel_comment_id']?.toString();
          
          if (duelId != null) {
            // Close loading dialog first
            Navigator.of(context, rootNavigator: true).pop();
            
            // Navigate to duel detail screen
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DuelDetailScreen(
                  duelId: duelId,
                ),
              ),
            );
          } else {
            Navigator.of(context, rootNavigator: true).pop();
          }
          break;
          
        case NotificationType.like:
        case NotificationType.comment:
          final ruckId = notification.data?['ruck_id']?.toString();
          if (ruckId != null) {
            // Create the session repository with the API client
            final sessionRepo = SessionRepository(apiClient: GetIt.I<ApiClient>());
            
            // Close loading dialog first
            Navigator.of(context, rootNavigator: true).pop();

            // Extract the user_id from the notification data if available
            final userId = notification.data?['user_id']?.toString() ?? '';
            
            // Create a minimal RuckBuddy with just the ID and userId
            // The detail screen will fetch the full data including the proper user profile
            final ruckBuddy = RuckBuddy(
              id: ruckId,
              userId: userId,  // Set the userId from notification data
              ruckWeightKg: 0,
              durationSeconds: 0,
              distanceKm: 0,
              caloriesBurned: 0,
              elevationGainM: 0,
              elevationLossM: 0,
              createdAt: DateTime.now(),
              user: UserInfo(
                id: userId,  // Set the ID to match the userId
                username: '',  // Leave empty to trigger profile fetch in detail screen
                gender: '',    // Leave empty, will be properly set when profile is fetched
              ),
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
          
        case NotificationType.clubEventCreated:
          print('🎯 DEBUG: Club event notification tapped');
          print('🎯 DEBUG: Notification data: ${notification.data}');
          final clubId = notification.data?['club_id']?.toString();
          final eventId = notification.data?['event_id']?.toString();
          print('🎯 DEBUG: Extracted clubId: $clubId');
          print('🎯 DEBUG: Extracted eventId: $eventId');
          if (eventId != null) {
            Navigator.of(context, rootNavigator: true).pop(); // Close loading dialog
            
            print('🎯 DEBUG: Navigating to EventDetailScreen with eventId: $eventId');
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => EventDetailScreen(eventId: eventId),
              ),
            );
          } else if (clubId != null) {
            Navigator.of(context, rootNavigator: true).pop(); // Close loading dialog
            
            print('🎯 DEBUG: Fallback - Navigating to ClubDetailScreen with clubId: $clubId');
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ClubDetailScreen(clubId: clubId),
              ),
            );
          } else {
            print('🎯 DEBUG: No eventId or clubId found in notification data');
            Navigator.of(context, rootNavigator: true).pop();
          }
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
