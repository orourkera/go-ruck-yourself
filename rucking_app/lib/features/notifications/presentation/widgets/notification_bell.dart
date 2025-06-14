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
    return BlocBuilder<NotificationBloc, NotificationState>(
      builder: (context, state) {
        int unreadCount = 0;
        
        if (state is NotificationsLoaded) {
          unreadCount = state.unreadCount;
        }
        
        // Stop animation if no unread notifications
        if (unreadCount <= 0 && _animationController.isAnimating) {
          _animationController.stop();
          _animationController.reset();
        } else if (unreadCount > 0 && !_animationController.isAnimating) {
          _animationController.repeat();
        }
        
        return Stack(
          clipBehavior: Clip.none,
          children: [
            SizedBox(
              width: 96, // Doubled from 48px
              height: 96, // Doubled from 48px
              child: AnimatedBuilder(
                animation: _rotationAnimation,
                builder: (context, child) {
                  // Only apply rotation animation if there are unread notifications
                  final rotation = unreadCount > 0 ? _rotationAnimation.value : 0.0;
                  
                  return Transform.rotate(
                    angle: rotation, // rotation in radians
                    child: child,
                  );
                },
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(48), // Doubled from 24
                    onTap: () async {
                      // Navigate to notifications screen
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const NotificationsScreen(),
                        ),
                      );
                      
                      // When returning from the notifications screen, explicitly request
                      // notification state refresh to update the counter
                      if (context.mounted) {
                        context.read<NotificationBloc>().add(const NotificationsRequested());
                      }
                    },
                    child: Container(
                      width: 96, // Doubled from 48px
                      height: 96, // Doubled from 48px
                      alignment: Alignment.center, // Center the icon within tap target
                      child: Image.asset(
                        'assets/images/notifications.png',
                        width: 64, // Doubled from 32px
                        height: 64, // Doubled from 32px
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (unreadCount > 0)
              Positioned(
                right: 8, // Adjusted positioning for smaller icon
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(4), // Slightly smaller badge
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 20,
                    minHeight: 20,
                  ),
                  child: Text(
                    unreadCount > 99 ? '99+' : '$unreadCount',
                    style: AppTextStyles.bodySmall.copyWith( // Smaller text for smaller badge
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
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
