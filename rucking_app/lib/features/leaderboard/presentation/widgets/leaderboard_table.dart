import 'package:flutter/material.dart';
import '../../data/models/leaderboard_user_model.dart';
import 'leaderboard_row.dart';
import 'leaderboard_skeleton.dart';

/// Well ain't this something! This table shows all them ruckers in a fancy list
class LeaderboardTable extends StatelessWidget {
  final List<LeaderboardUserModel> users;
  final ScrollController scrollController;
  final bool isLoadingMore;
  final bool hasMore;
  final bool isUpdating;

  const LeaderboardTable({
    Key? key,
    required this.users,
    required this.scrollController,
    required this.isLoadingMore,
    required this.hasMore,
    this.isUpdating = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.only(bottom: 80), // Space for loading indicator
      itemCount: users.length + (isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        // Show loading indicator at bottom
        if (index >= users.length) {
          return _buildLoadingMoreIndicator();
        }

        final user = users[index];
        final rank = index + 1;

        return LeaderboardRow(
          user: user,
          rank: rank,
          isUpdating: isUpdating && user.isCurrentlyRucking,
        );
      },
    );
  }

  /// Loading indicator prettier than a summer sunset - now with skeleton shimmer!
  Widget _buildLoadingMoreIndicator() {
    return const LeaderboardLoadingMoreSkeleton();
  }
}
