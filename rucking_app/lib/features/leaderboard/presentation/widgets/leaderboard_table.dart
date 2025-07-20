import 'package:flutter/material.dart';
import '../../data/models/leaderboard_user_model.dart';
import 'leaderboard_row.dart';

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

  /// Loading indicator prettier than a summer sunset
  Widget _buildLoadingMoreIndicator() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(height: 8),
            Text(
              'Loading more ruckers...',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
