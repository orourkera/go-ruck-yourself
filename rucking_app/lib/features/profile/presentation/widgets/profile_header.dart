import 'package:flutter/material.dart';
import 'package:rucking_app/features/profile/domain/entities/user_profile.dart';
import 'package:rucking_app/features/profile/presentation/widgets/follow_button.dart';

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
        children: [
          CircleAvatar(
            radius: 50,
            backgroundImage: profile.avatarUrl != null ? NetworkImage(profile.avatarUrl!) : null,
          ),
          SizedBox(height: 8),
          Text(profile.username, style: Theme.of(context).textTheme.headlineMedium),
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