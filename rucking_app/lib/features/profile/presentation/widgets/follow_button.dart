import 'package:flutter/material.dart';

class FollowButton extends StatelessWidget {
  final bool isFollowing;
  final bool isLoading;
  final VoidCallback onPressed;

  const FollowButton({
    Key? key,
    required this.isFollowing,
    this.isLoading = false,
    required this.onPressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      child: isLoading
          ? CircularProgressIndicator()
          : Text(isFollowing ? 'Unfollow' : 'Follow'),
    );
  }
}
