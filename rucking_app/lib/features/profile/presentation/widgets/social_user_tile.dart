import 'package:flutter/material.dart';
import 'package:rucking_app/features/profile/domain/entities/social_user.dart';
import 'package:rucking_app/features/profile/presentation/widgets/follow_button.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/features/live_following/presentation/screens/live_ruck_following_screen.dart';
import 'package:intl/intl.dart';

class SocialUserTile extends StatelessWidget {
  final SocialUser user;
  final VoidCallback? onFollowPressed;
  final VoidCallback? onTap;
  final bool showFollowButton;

  const SocialUserTile({
    Key? key,
    required this.user,
    this.onFollowPressed,
    this.onTap,
    this.showFollowButton = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Format the date to show only the date part
    final dateFormat = DateFormat('MMM dd, yyyy');
    final formattedDate = dateFormat.format(user.followedAt);

    return ListTile(
      leading: Stack(
        children: [
          CircleAvatar(
            backgroundImage: user.avatarUrl != null && user.avatarUrl!.isNotEmpty
                ? NetworkImage(user.avatarUrl!)
                : null,
            child: user.avatarUrl == null || user.avatarUrl!.isEmpty
                ? Text(
                    user.username.isNotEmpty ? user.username[0].toUpperCase() : '?')
                : null,
          ),
          // Live indicator dot
          if (user.isLiveRuckingNow)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
        ],
      ),
      title: Row(
        children: [
          Text(
            user.username,
            style: AppTextStyles.headlineMedium.copyWith(
              fontFamily: 'Bangers',
              fontSize: 24,
            ),
          ),
          if (user.isLiveRuckingNow) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '🔴 LIVE',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        user.isLiveRuckingNow
            ? 'Rucking now - Tap to follow live!'
            : 'Followed since $formattedDate'
      ),
      trailing: showFollowButton
          ? FollowButton(
              isFollowing: user.isFollowing,
              onPressed: onFollowPressed ?? () {},
            )
          : null,
      onTap: user.isLiveRuckingNow
          ? () {
              // Navigate to live following screen
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LiveRuckFollowingScreen(
                    ruckId: user.activeRuckId!,
                    ruckerName: user.username,
                  ),
                ),
              );
            }
          : onTap,
    );
  }
}
