import 'package:flutter/material.dart';
import '../../domain/entities/duel.dart';
import '../../domain/entities/duel_participant.dart';
import '../../../../shared/theme/app_colors.dart';

class DuelLeaderboardWidget extends StatelessWidget {
  final Duel duel;
  final List<DuelParticipant> participants;
  final bool showAllParticipants;

  const DuelLeaderboardWidget({
    super.key,
    required this.duel,
    required this.participants,
    this.showAllParticipants = false,
  });

  @override
  Widget build(BuildContext context) {
    if (participants.isEmpty) {
      return _buildEmptyState();
    }

    final sortedParticipants = List<DuelParticipant>.from(participants)
      ..sort((a, b) => b.currentValue.compareTo(a.currentValue));

    final displayParticipants = showAllParticipants 
        ? sortedParticipants 
        : sortedParticipants.take(10).toList();

    return Card(
      margin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(sortedParticipants.length),
          const Divider(height: 1),
          if (duel.status == 'completed' && duel.winnerId != null)
            _buildWinnerBanner(sortedParticipants.first),
          _buildLeaderboardList(displayParticipants),
          if (!showAllParticipants && sortedParticipants.length > 10)
            _buildViewAllButton(sortedParticipants.length),
        ],
      ),
    );
  }

  Widget _buildHeader(int totalParticipants) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(
            Icons.leaderboard,
            color: AppColors.primary,
            size: 24,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Leaderboard',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$totalParticipants participants',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWinnerBanner(DuelParticipant winner) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.amber.withOpacity(0.2),
            Colors.orange.withOpacity(0.1),
          ],
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.emoji_events,
            color: Colors.amber,
            size: 32,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🎉 Duel Winner!',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber,
                  ),
                ),
                Text(
                  winner.username, // TODO: Get actual user name
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${winner.currentValue.toStringAsFixed(winner.currentValue % 1 == 0 ? 0 : 1)} ${_getUnit()}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.amber,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderboardList(List<DuelParticipant> participants) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: participants.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final participant = participants[index];
        final rank = index + 1;
        final progress = (participant.currentValue / duel.targetValue).clamp(0.0, 1.0);
        
        return _buildParticipantTile(participant, rank, progress);
      },
    );
  }

  Widget _buildParticipantTile(DuelParticipant participant, int rank, double progress) {
    final isTopThree = rank <= 3;
    final isCompleted = progress >= 1.0;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: isTopThree ? AppColors.accent.withOpacity(0.05) : null,
      child: Row(
        children: [
          // Rank Badge
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _getRankColor(rank),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: rank <= 3
                  ? Icon(
                      _getRankIcon(rank),
                      color: Colors.white,
                      size: 16,
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
          
          // Participant Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        participant.username, // TODO: Get actual user name
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isTopThree ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (isCompleted)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'COMPLETE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isCompleted ? Colors.green : _getRankColor(rank),
                        ),
                        minHeight: 4,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(progress * 100).toInt()}%',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          
          // Progress Value
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${participant.currentValue.toStringAsFixed(participant.currentValue % 1 == 0 ? 0 : 1)}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: isTopThree ? FontWeight.bold : FontWeight.w600,
                  color: isTopThree ? _getRankColor(rank) : Colors.grey[700],
                ),
              ),
              Text(
                _getUnit(),
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[500],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildViewAllButton(int totalCount) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border(
          top: BorderSide(color: Colors.grey[200]!),
        ),
      ),
      child: TextButton(
        onPressed: () {
          // TODO: Navigate to full leaderboard view
        },
        child: Text(
          'View all $totalCount participants',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(
              Icons.leaderboard,
              size: 64,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 16),
            Text(
              'No participants yet',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'The leaderboard will appear when participants join the duel',
              style: TextStyle(
                fontSize: 12,
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

  String _getUnit() {
    switch (duel.challengeType) {
      case 'distance':
        return 'km';
      case 'time':
        return 'min';
      case 'elevation':
        return 'm';
      case 'power_points':
        return 'pts';
      default:
        return '';
    }
  }
}
