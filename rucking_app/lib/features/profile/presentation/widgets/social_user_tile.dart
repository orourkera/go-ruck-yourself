import 'package:flutter/material.dart';
import 'package:rucking_app/features/profile/domain/entities/social_user.dart';
import 'package:rucking_app/features/profile/presentation/widgets/follow_button.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
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
      leading: CircleAvatar(
        backgroundImage: user.avatarUrl != null && user.avatarUrl!.isNotEmpty
            ? NetworkImage(user.avatarUrl!)
            : null,
        child: user.avatarUrl == null || user.avatarUrl!.isEmpty
            ? Text(
                user.username.isNotEmpty ? user.username[0].toUpperCase() : '?')
            : null,
      ),
      title: Text(
        user.username,
        style: AppTextStyles.headlineMedium.copyWith(
          fontFamily: 'Bangers',
          fontSize: 24,
        ),
      ),
      subtitle: Text('Followed since $formattedDate'),
      trailing: showFollowButton
          ? FollowButton(
              isFollowing: user.isFollowing,
              onPressed: onFollowPressed ?? () {},
            )
          : null,
      onTap: onTap,
    );
  }
}
