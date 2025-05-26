import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/features/notifications/presentation/bloc/notification_bloc.dart';
import 'package:rucking_app/features/notifications/presentation/bloc/notification_state.dart';
import 'package:rucking_app/features/notifications/presentation/bloc/notification_event.dart';
import 'package:rucking_app/features/notifications/presentation/pages/notifications_screen.dart';

class NotificationBell extends StatelessWidget {
  final bool useLadyMode;
  
  const NotificationBell({
    Key? key,
    this.useLadyMode = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NotificationBloc, NotificationState>(
      builder: (context, state) {
        int unreadCount = 0;
        
        if (state is NotificationsLoaded) {
          unreadCount = state.unreadCount;
        }
        
        return Stack(
          clipBehavior: Clip.none,
          children: [
            SizedBox(
              width: 96, // 50% larger container
              height: 96,
              child: IconButton(
                iconSize: 96, // 50% larger icon size
                padding: EdgeInsets.zero, // Remove padding to maximize space
                constraints: const BoxConstraints(), // Remove constraints to allow full size
                icon: Image.asset(
                  'assets/images/notifications.png',
                  width: 96, // 50% larger (previously 64px)
                  height: 96, // 50% larger (previously 64px)
                ),
                onPressed: () async {
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
              ),
            ),
            if (unreadCount > 0)
              Positioned(
                right: 18,
                top: 18,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  child: Text(
                    unreadCount > 99 ? '99+' : '$unreadCount',
                    style: AppTextStyles.titleSmall.copyWith(
                      color: Colors.white,
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
