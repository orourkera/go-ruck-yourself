import 'package:flutter/material.dart';
import '../../domain/entities/duel.dart';
import '../../domain/entities/duel_participant.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/user_avatar.dart';

class DuelProgressChart extends StatelessWidget {
  final Duel duel;
  final List<DuelParticipant> participants;
  final bool showCurrentUser;

  const DuelProgressChart({
    super.key,
    required this.duel,
    required this.participants,
    this.showCurrentUser = true,
  });

  @override
  Widget build(BuildContext context) {
    if (participants.isEmpty) {
      return _buildEmptyState();
    }

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            _buildTargetInfo(),
            const SizedBox(height: 16),
            _buildProgressBars(),
            if (duel.status == 'completed') ...[
              const SizedBox(height: 16),
              _buildWinnerInfo(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(
          _getChallengeIcon(),
          color: AppColors.primary,
          size: 24,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Progress Tracker',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Text(
          '${participants.length} participants',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildTargetInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.flag,
            color: AppColors.primary,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            'Target: ${duel.targetValue.toStringAsFixed(duel.targetValue % 1 == 0 ? 0 : 1)} ${_getUnit()}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBars() {
    final sortedParticipants = List<DuelParticipant>.from(participants)
      ..sort((a, b) => b.currentValue.compareTo(a.currentValue));

    return Column(
      children: sortedParticipants.asMap().entries.map((entry) {
        final index = entry.key;
        final participant = entry.value;
        final isLeader = index == 0;
        final progress = (participant.currentValue / duel.targetValue).clamp(0.0, 1.0);
        
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildParticipantProgressBar(
            participant,
            progress,
            index + 1,
            isLeader,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildParticipantProgressBar(
    DuelParticipant participant,
    double progress,
    int rank,
    bool isLeader,
  ) {
    final isCompleted = progress >= 1.0;
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(
          color: isLeader ? AppColors.accent : Colors.grey[300]!,
          width: isLeader ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
        color: isLeader ? AppColors.accent.withOpacity(0.05) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Participant Avatar with Rank Badge
              Stack(
                children: [
                  UserAvatar(
                    avatarUrl: participant.avatarUrl,
                    username: participant.username,
                    size: 36,
                  ),
                  if (rank <= 3)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: isLeader ? AppColors.accent : Colors.grey[400],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white, width: 1),
                        ),
                        child: Center(
                          child: Text(
                            rank.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  participant.username,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isLeader ? FontWeight.bold : FontWeight.w500,
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
                    'DONE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              Text(
                '${participant.currentValue.toStringAsFixed(participant.currentValue % 1 == 0 ? 0 : 1)} ${_getUnit()}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(
              isCompleted ? Colors.green : 
              isLeader ? AppColors.accent : AppColors.primary,
            ),
            minHeight: 6,
          ),
          const SizedBox(height: 4),
          Text(
            '${(progress * 100).toInt()}% complete',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWinnerInfo() {
    final winner = participants
        .where((p) => p.id == duel.winnerId)
        .firstOrNull;
    
    if (winner == null) return const SizedBox.shrink();

    return Container(
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
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber, width: 2),
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
                  '🏆 Winner!',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber,
                  ),
                ),
                Text(
                  winner.username,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Completed with ${winner.currentValue.toStringAsFixed(winner.currentValue % 1 == 0 ? 0 : 1)} ${_getUnit()}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bar_chart,
              size: 64,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 8),
            Text(
              'No participants yet',
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Progress will appear here when participants join',
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

  IconData _getChallengeIcon() {
    switch (duel.challengeType) {
      case DuelChallengeType.distance:
        return Icons.straighten;
      case DuelChallengeType.time:
        return Icons.timer;
      case DuelChallengeType.elevation:
        return Icons.terrain;
      case DuelChallengeType.powerPoints:
        return Icons.bolt;
      default:
        return Icons.sports;
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
