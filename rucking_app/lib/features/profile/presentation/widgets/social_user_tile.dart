import 'package:flutter/material.dart';
import 'package:rucking_app/features/profile/domain/entities/social_user.dart';
import 'package:rucking_app/features/profile/presentation/widgets/follow_button.dart';

class SocialUserTile extends StatelessWidget {
  final SocialUser user;
  final VoidCallback? onFollowPressed;
  final VoidCallback? onTap;

  const SocialUserTile({
    Key? key,
    required this.user,
    this.onFollowPressed,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(backgroundImage: NetworkImage(user.avatarUrl ?? '')),
      title: Text(user.username),
      subtitle: Text('Followed since ${user.followedAt.toString()}'),
      trailing: FollowButton(isFollowing: user.isFollowing, onPressed: onFollowPressed ?? () {}),
      onTap: onTap,
    );
  }
} 