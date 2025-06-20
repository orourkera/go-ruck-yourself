import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/features/notifications/presentation/bloc/notification_bloc.dart';
import 'package:rucking_app/features/notifications/presentation/bloc/notification_state.dart';
import 'package:rucking_app/features/notifications/presentation/bloc/notification_event.dart';
import 'package:rucking_app/features/notifications/presentation/pages/notifications_screen.dart';

class NotificationBell extends StatefulWidget {
  final bool useLadyMode;
  
  const NotificationBell({
    Key? key,
    this.useLadyMode = false,
  }) : super(key: key);

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _rotationAnimation;
  
  @override
  void initState() {
    super.initState();
    
    // Create animation controller with faster duration for shake effect
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    
    // Create a rotation animation that shakes back and forth
    _rotationAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 0.05)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.05, end: -0.05)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: -0.05, end: 0.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 25,
      ),
    ]).animate(_animationController);
    
    // Make the animation repeat indefinitely
    _animationController.repeat();
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return BlocConsumer<NotificationBloc, NotificationState>(
      // Listen for state changes to trigger animations
      listener: (context, state) {
        final unreadCount = state.unreadCount;
        
        // Force animation update when unread count changes
        if (unreadCount > 0 && !_animationController.isAnimating) {
          _animationController.repeat();
        } else if (unreadCount <= 0 && _animationController.isAnimating) {
          _animationController.stop();
          _animationController.reset();
        }
      },
      builder: (context, state) {
        final unreadCount = state.unreadCount;
        final isLoading = state.isLoading;
        final totalNotifications = state.notifications.length;
        
        // Debug logging
        print('🔔 NotificationBell: unreadCount=$unreadCount, totalNotifications=$totalNotifications');
        
        return Stack(
          clipBehavior: Clip.none,
          children: [
            SizedBox(
              width: 70, 
              height: 70, 
              child: AnimatedBuilder(
                animation: _rotationAnimation,
                builder: (context, child) {
                  // Only apply rotation animation if there are unread notifications
                  final rotation = unreadCount > 0 ? _rotationAnimation.value : 0.0;
                  
                  return Transform.rotate(
                    angle: rotation, 
                    child: child,
                  );
                },
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(35), 
                    onTap: () async {
                      // Navigate to notifications screen
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const NotificationsScreen(),
                        ),
                      );
                      
                      // When returning from the notifications screen, explicitly request
                      // to reload notifications to ensure the count is updated
                      context.read<NotificationBloc>().add(const NotificationsRequested());
                    },
                    child: Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            spreadRadius: 1,
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          // Bell icon
                          Center(
                            child: Icon(
                              Icons.notifications,
                              size: 32, 
                              color: unreadCount > 0 
                                  ? Theme.of(context).primaryColor
                                  : Colors.grey[600],
                            ),
                          ),
                          // Loading indicator
                          if (isLoading)
                            const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Notification count badge
            if (unreadCount > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 20,
                    minHeight: 20,
                  ),
                  child: Text(
                    unreadCount > 99 ? '99+' : unreadCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
