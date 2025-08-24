import 'package:flutter/material.dart';
import '../../data/models/leaderboard_user_model.dart';
import 'leaderboard_row.dart';
import 'leaderboard_skeleton.dart';

const double _kFixedPaneWidth = 190; // 40 rank + 150 user

/// Well ain't this something! This table shows all them ruckers in a fancy list
class LeaderboardTable extends StatelessWidget {
  final List<LeaderboardUserModel> users;
  final ScrollController scrollController;
  final ValueNotifier<double>? horizontalScrollNotifier;
  final bool isLoadingMore;
  final bool hasMore;
  final bool isUpdating;
  final bool showOnlyFixed;
  final bool showOnlyStats;

  const LeaderboardTable({
    Key? key,
    required this.users,
    required this.scrollController,
    this.horizontalScrollNotifier,
    required this.isLoadingMore,
    required this.hasMore,
    this.isUpdating = false,
    this.showOnlyFixed = false,
    this.showOnlyStats = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Shared vertical controller so panes stay in sync
    final ScrollController verticalController = scrollController;

    return ListView.builder(
      controller: verticalController,
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: users.length + (isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        // Show loading indicator at bottom
        if (index >= users.length) {
          return _buildLoadingMoreIndicator();
        }

        final user = users[index];
        final rank = index + 1;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: _getRowColor(context, user, rank, isUpdating && user.isCurrentlyRucking),
            borderRadius: showOnlyFixed 
                ? const BorderRadius.only(topLeft: Radius.circular(8), bottomLeft: Radius.circular(8))
                : showOnlyStats 
                    ? const BorderRadius.only(topRight: Radius.circular(8), bottomRight: Radius.circular(8))
                    : BorderRadius.circular(8),
            border: user.isCurrentUser 
                ? Border.all(color: Theme.of(context).primaryColor, width: 2)
                : null,
            boxShadow: user.isCurrentUser && !showOnlyStats
                ? [
                    BoxShadow(
                      color: Theme.of(context).primaryColor.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: showOnlyFixed 
                  ? const BorderRadius.only(topLeft: Radius.circular(8), bottomLeft: Radius.circular(8))
                  : showOnlyStats 
                      ? const BorderRadius.only(topRight: Radius.circular(8), bottomRight: Radius.circular(8))
                      : BorderRadius.circular(8),
              onTap: showOnlyFixed ? () => _navigateToProfile(context, user) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: _buildRowContent(context, user, rank),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Loading indicator prettier than a summer sunset - now with skeleton shimmer!
  Widget _buildLoadingMoreIndicator() {
    return const LeaderboardLoadingMoreSkeleton();
  }

  /// Build row content based on display mode
  Widget _buildRowContent(BuildContext context, LeaderboardUserModel user, int rank) {
    if (showOnlyFixed) {
      // Only show fixed columns (rank + user)
      return Row(
        children: [
          _buildRankColumn(rank),
          _buildUserColumn(context, user),
        ],
      );
    } else if (showOnlyStats) {
      // Only show stats columns
      return Row(
        children: [
          _buildStatColumn(_formatPowerPoints(user.stats.powerPoints), width: 100, isPowerPoints: true),
          _buildStatColumn(user.stats.totalRucks.toString(), width: 80, isRucks: true),
          _buildStatColumn(_formatDistance(user.stats.distanceKm), width: 100),
          _buildStatColumn(_formatElevation(user.stats.elevationGainMeters), width: 100),
          _buildStatColumn(_formatCalories(user.stats.caloriesBurned.round()), width: 100),
        ],
      );
    } else {
      // Show full row (fallback for old usage)
      return Row(
        children: [
          // FIXED SECTION (rank + avatar + username)
          SizedBox(
            width: _kFixedPaneWidth,
            child: Row(
              children: [
                _buildRankColumn(rank),
                _buildUserColumn(context, user),
              ],
            ),
          ),
          
          // STATS SECTION - let's keep it simple for now
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 480, // total width of stats columns (80 + 4*100)
                child: Row(
                  children: [
                    _buildStatColumn(user.stats.totalRucks.toString(), width: 80, isRucks: true),
                    _buildStatColumn(_formatDistance(user.stats.distanceKm), width: 100),
                    _buildStatColumn(_formatElevation(user.stats.elevationGainMeters), width: 100),
                    _buildStatColumn(_formatCalories(user.stats.caloriesBurned.round()), width: 100),
                    _buildStatColumn(_formatPowerPoints(user.stats.powerPoints), width: 100, isPowerPoints: true),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }
  }

  /// Build rank column with fancy medals for top 3
  Widget _buildRankColumn(int rank) {
    return SizedBox(
      width: 40,
      child: Column(
        children: [
          if (rank <= 3)
            Text(
              _getRankEmoji(rank),
              style: const TextStyle(fontSize: 20),
            ),
          Text(
            rank.toString(),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16, // Increased from 13 to match stat columns
              color: rank <= 3 ? _getMedalColor(rank) : null,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// Build user column with avatar and name
  Widget _buildUserColumn(BuildContext context, LeaderboardUserModel user) {
    return SizedBox(
      width: 150,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            _buildAvatar(user),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.username,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16, // Increased from 14 to match other elements
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (user.isCurrentlyRucking) ...[
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.green.withOpacity(0.3)),
                      ),
                      child: Text(
                        'LIVE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build avatar with clean display
  Widget _buildAvatar(LeaderboardUserModel user) {
    final hasAvatar = user.avatarUrl != null && user.avatarUrl!.isNotEmpty;

    Widget avatarWidget;
    if (hasAvatar) {
      avatarWidget = ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image.network(
          user.avatarUrl!,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
        ),
      );
    } else {
      String assetPath = (user.gender == 'female')
          ? 'assets/images/lady rucker profile.png'
          : 'assets/images/profile.png';
      avatarWidget = ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image.asset(
          assetPath,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
        ),
      );
    }

    return Stack(
      children: [
        avatarWidget,
        Positioned(
          right: 0,
          bottom: 0,
          child: user.isCurrentlyRucking
              ? Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  /// Build stat column
  Widget _buildStatColumn(String value, {required double width, bool isPowerPoints = false, bool isRucks = false}) {
    return SizedBox(
      width: width,
      child: Text(
        value,
        style: TextStyle(
          fontWeight: isRucks ? FontWeight.w900 : FontWeight.w600, // Extra bold for rucks
          fontSize: 16, // Increased from 13 to make values bigger
          color: isPowerPoints ? Colors.amber.shade700 : null,
        ),
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// Get row background color
  Color _getRowColor(BuildContext context, LeaderboardUserModel user, int rank, bool isUpdating) {
    if (user.isCurrentUser) {
      return Theme.of(context).primaryColor.withOpacity(0.05);
    } else if (rank <= 3) {
      return _getMedalColor(rank).withOpacity(0.05);
    } else if (isUpdating) {
      return Colors.green.withOpacity(0.05);
    }
    return Theme.of(context).cardColor;
  }

  /// Get rank emoji for top 3
  String _getRankEmoji(int rank) {
    switch (rank) {
      case 1: return '🥇';
      case 2: return '🥈';
      case 3: return '🥉';
      default: return '';
    }
  }

  /// Get medal color for top 3
  Color _getMedalColor(int rank) {
    switch (rank) {
      case 1: return const Color(0xFFFFD700);
      case 2: return const Color(0xFFC0C0C0);
      case 3: return const Color(0xFFCD7F32);
      default: return Colors.grey;
    }
  }

  /// Navigate to user's public profile
  void _navigateToProfile(BuildContext context, LeaderboardUserModel user) {
    Navigator.pushNamed(context, '/profile/${user.userId}');
  }

  // Formatting methods
  String _formatDistance(double distanceKm) {
    if (distanceKm >= 1000) {
      return '${(distanceKm / 1000).toStringAsFixed(1)}K km';
    } else {
      return '${distanceKm.toStringAsFixed(1)} km';
    }
  }

  String _formatElevation(double elevationM) {
    if (elevationM >= 1000) {
      return '${(elevationM / 1000).toStringAsFixed(1)}K m';
    } else {
      return '${elevationM.toStringAsFixed(0)} m';
    }
  }

  String _formatCalories(int calories) {
    if (calories >= 1000) {
      return '${(calories / 1000).toStringAsFixed(1)}K';
    } else {
      return calories.toString();
    }
  }

  String _formatPowerPoints(double points) {
    if (points >= 1000000) {
      return '${(points / 1000000).toStringAsFixed(1)}M';
    } else if (points >= 1000) {
      return '${(points / 1000).toStringAsFixed(1)}k';
    } else {
      return points.toStringAsFixed(0);
    }
  }
}
