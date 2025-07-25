import 'package:flutter/material.dart';
import 'package:rucking_app/features/profile/domain/entities/user_profile.dart';
import 'package:rucking_app/features/profile/presentation/widgets/follow_button.dart';
import 'package:rucking_app/shared/widgets/user_avatar.dart';

class ProfileHeader extends StatelessWidget {
  final UserProfile profile;
  final bool isOwnProfile;
  final VoidCallback? onFollowTap;
  final VoidCallback? onMessageTap;

  const ProfileHeader({
    Key? key,
    required this.profile,
    this.isOwnProfile = false,
    this.onFollowTap,
    this.onMessageTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Center(
            child: UserAvatar(
              avatarUrl: profile.avatarUrl,
              username: profile.username,
              size: 100, // radius 50 = diameter 100
            ),
          ),
          SizedBox(height: 8),
          Center(
            child: Text(profile.username, style: Theme.of(context).textTheme.headlineMedium),
          ),
          if (profile.isPrivateProfile && !isOwnProfile)
            Text('This profile is private', style: TextStyle(color: Colors.grey)),
          if (!isOwnProfile) ...[
            SizedBox(height: 16),
            FollowButton(
              isFollowing: profile.isFollowing,
              onPressed: onFollowTap ?? () {},
            ),
          ],
        ],
      ),
    );
  }
} 