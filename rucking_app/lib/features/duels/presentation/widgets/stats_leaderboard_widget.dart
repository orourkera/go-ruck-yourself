import 'package:flutter/material.dart';
import '../../domain/entities/duel_stats.dart';
import '../../../../shared/theme/app_colors.dart';

class StatsLeaderboardWidget extends StatelessWidget {
  final List<DuelStats> leaderboard;
  final String statType;
  final bool isLoading;
  final DuelStats? currentUserStats;

  const StatsLeaderboardWidget({
    super.key,
    required this.leaderboard,
    required this.statType,
    this.isLoading = false,
    this.currentUserStats,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (leaderboard.isEmpty) {
      return _buildEmptyState();
    }

    return Column(
      children: [
        if (currentUserStats != null) _buildCurrentUserCard(),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: leaderboard.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final stats = leaderboard[index];
              final rank = index + 1;
              return _buildLeaderboardTile(stats, rank, context);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentUserCard() {
    if (currentUserStats == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withOpacity(0.1),
            AppColors.accent.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary, width: 2),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Center(
              child: Icon(
                Icons.person,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your Rank',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey,
                  ),
                ),
                Text(
                  '#${currentUserStats!.rank ?? 0}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            _getStatValue(currentUserStats!, statType),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            _getStatUnit(statType),
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderboardTile(DuelStats stats, int rank, BuildContext context) {
    final isTopThree = rank <= 3;
    final isCurrentUser = currentUserStats?.userId == stats.userId;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isCurrentUser 
            ? AppColors.primary.withOpacity(0.1)
            : isTopThree 
                ? _getRankColor(rank).withOpacity(0.1)
                : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrentUser 
              ? AppColors.primary
              : isTopThree 
                  ? _getRankColor(rank)
                  : Colors.grey[200]!,
          width: isCurrentUser || isTopThree ? 2 : 1,
        ),
        boxShadow: isTopThree
            ? [
                BoxShadow(
                  color: _getRankColor(rank).withOpacity(0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          // Rank Badge
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _getRankColor(rank),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Center(
              child: rank <= 3
                  ? Icon(
                      _getRankIcon(rank),
                      color: Colors.white,
                      size: 18,
                    )
                  : Text(
                      rank.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          
          // User Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'User ${stats.userId.substring(0, 8)}', // TODO: Get actual user name
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isTopThree || isCurrentUser 
                              ? FontWeight.bold 
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (isCurrentUser)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'YOU',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _getStatsSubtitle(stats),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          
          // Stat Value
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _getStatValue(stats, statType),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: isTopThree || isCurrentUser 
                      ? FontWeight.bold 
                      : FontWeight.w600,
                  color: isTopThree ? _getRankColor(rank) : Colors.grey[700],
                ),
              ),
              Text(
                _getStatUnit(statType),
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[500],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.leaderboard,
              size: 80,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 16),
            Text(
              'No leaderboard data',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Complete some duels to see your ranking here!',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Color _getRankColor(int rank) {
    switch (rank) {
      case 1:
        return Colors.amber; // Gold
      case 2:
        return Colors.grey[400]!; // Silver
      case 3:
        return Colors.brown; // Bronze
      default:
        return AppColors.primary;
    }
  }

  IconData _getRankIcon(int rank) {
    switch (rank) {
      case 1:
        return Icons.emoji_events; // Trophy
      case 2:
        return Icons.military_tech; // Medal
      case 3:
        return Icons.military_tech; // Medal
      default:
        return Icons.person;
    }
  }

  String _getStatValue(DuelStats stats, String type) {
    switch (type) {
      case 'wins':
        return stats.duelsWon.toString();
      case 'total_duels':
        return stats.totalDuels.toString();
      case 'win_rate':
        return '${(stats.winRate * 100).toInt()}';
      case 'longest_streak':
        return stats.duelsWon.toString(); // Using duelsWon as alternative
      default:
        return '0';
    }
  }

  String _getStatUnit(String type) {
    switch (type) {
      case 'wins':
        return 'wins';
      case 'total_duels':
        return 'duels';
      case 'win_rate':
        return '%';
      case 'longest_streak':
        return 'streak';
      default:
        return '';
    }
  }

  String _getStatsSubtitle(DuelStats stats) {
    return '${stats.totalDuels} duels • ${(stats.winRate * 100).toInt()}% win rate';
  }
}
