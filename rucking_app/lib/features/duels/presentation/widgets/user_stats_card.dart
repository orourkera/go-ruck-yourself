import 'package:flutter/material.dart';
import '../../domain/entities/duel_stats.dart';
import '../../../../shared/theme/app_colors.dart';

class UserStatsCard extends StatelessWidget {
  final DuelStats userStats;

  const UserStatsCard({
    super.key,
    required this.userStats,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary,
            AppColors.primary.withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 20),
            _buildStatsGrid(),
            const SizedBox(height: 16),
            _buildAchievementBadge(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.person,
            color: Colors.white,
            size: 24,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your Duel Stats',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'All-time performance',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'Rank #${userStats.rank ?? 0}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsGrid() {
    return Row(
      children: [
        Expanded(
          child: _buildStatItem(
            'Wins',
            userStats.duelsWon.toString(),
            Icons.emoji_events,
          ),
        ),
        Expanded(
          child: _buildStatItem(
            'Total Duels',
            userStats.totalDuels.toString(),
            Icons.sports,
          ),
        ),
        Expanded(
          child: _buildStatItem(
            'Win Rate',
            '${(userStats.winRate * 100).toInt()}%',
            Icons.trending_up,
          ),
        ),
        Expanded(
          child: _buildStatItem(
            'Best Streak',
            userStats.duelsWon.toString(),
            Icons.local_fire_department,
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: Colors.white,
            size: 20,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildAchievementBadge() {
    final achievementText = _getAchievementText();
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            _getAchievementIcon(),
            color: Colors.amber,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              achievementText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getAchievementText() {
    if (userStats.duelsWon == 0) {
      return 'Join your first duel to start earning wins!';
    } else if (userStats.duelsWon == 1) {
      return 'First victory achieved! 🎉';
    } else if (userStats.winRate >= 0.8) {
      return 'Dominating with ${(userStats.winRate * 100).toInt()}% win rate!';
    } else if (userStats.duelsWon >= 5) {
      return 'Champion with ${userStats.duelsWon} wins!';
    } else if (userStats.totalDuels >= 10) {
      return 'Veteran duelist with ${userStats.totalDuels} duels completed';
    } else {
      return 'Keep dueling to unlock achievements!';
    }
  }

  IconData _getAchievementIcon() {
    if (userStats.duelsWon == 0) {
      return Icons.flag;
    } else if (userStats.winRate >= 0.8) {
      return Icons.emoji_events;
    } else if (userStats.duelsWon >= 5) {
      return Icons.local_fire_department;
    } else if (userStats.totalDuels >= 10) {
      return Icons.military_tech;
    } else {
      return Icons.star;
    }
  }
}
