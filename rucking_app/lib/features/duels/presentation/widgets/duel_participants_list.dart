import 'package:flutter/material.dart';
import '../../domain/entities/duel.dart';
import '../../domain/entities/duel_participant.dart';
import '../../../../shared/theme/app_colors.dart';

class DuelParticipantsList extends StatelessWidget {
  final Duel duel;
  final List<DuelParticipant> participants;

  const DuelParticipantsList({
    super.key,
    required this.duel,
    required this.participants,
  });

  @override
  Widget build(BuildContext context) {
    if (participants.isEmpty) {
      return _buildEmptyState();
    }

    final sortedParticipants = List<DuelParticipant>.from(participants)
      ..sort((a, b) {
        // Handle nullable joinedAt dates
        if (a.joinedAt == null && b.joinedAt == null) return 0;
        if (a.joinedAt == null) return 1; // nulls last
        if (b.joinedAt == null) return -1; // nulls last
        return a.joinedAt!.compareTo(b.joinedAt!);
      });

    return RefreshIndicator(
      onRefresh: () async {
        // TODO: Refresh participants list
      },
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: sortedParticipants.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final participant = sortedParticipants[index];
          return _buildParticipantCard(participant, index);
        },
      ),
    );
  }

  Widget _buildParticipantCard(DuelParticipant participant, int index) {
    final progress = (participant.currentValue / duel.targetValue).clamp(0.0, 1.0);
    final isCompleted = progress >= 1.0;
    final isWinner = participant.id == duel.winnerId;
    
    return Card(
      elevation: isWinner ? 4 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isWinner ? BorderSide(color: Colors.amber, width: 2) : BorderSide.none,
      ),
      child: Container(
        decoration: isWinner
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.amber.withOpacity(0.1),
                    Colors.orange.withOpacity(0.05),
                  ],
                ),
              )
            : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildParticipantHeader(participant, isWinner),
              const SizedBox(height: 12),
              _buildProgressSection(participant, progress, isCompleted),
              const SizedBox(height: 12),
              _buildJoinedInfo(participant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildParticipantHeader(DuelParticipant participant, bool isWinner) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: isWinner ? Colors.amber : AppColors.primary,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Center(
            child: isWinner
                ? const Icon(
                    Icons.emoji_events,
                    color: Colors.white,
                    size: 24,
                  )
                : Text(
                    participant.username.isNotEmpty 
                        ? participant.username[0].toUpperCase()
                        : 'U',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 12),
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
                        fontSize: 16,
                        fontWeight: isWinner ? FontWeight.bold : FontWeight.w600,
                      ),
                    ),
                  ),
                  if (isWinner)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amber,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'WINNER',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              Text(
                _getParticipantSubtitle(participant),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProgressSection(DuelParticipant participant, double progress, bool isCompleted) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Progress',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
            Row(
              children: [
                Text(
                  '${participant.currentValue.toStringAsFixed(participant.currentValue % 1 == 0 ? 0 : 1)} / ${duel.targetValue.toStringAsFixed(duel.targetValue % 1 == 0 ? 0 : 1)} ${_getUnit()}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
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
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: progress,
          backgroundColor: Colors.grey[200],
          valueColor: AlwaysStoppedAnimation<Color>(
            isCompleted ? Colors.green : AppColors.accent,
          ),
          minHeight: 6,
        ),
        const SizedBox(height: 4),
        Text(
          '${(progress * 100).toInt()}% complete',
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[500],
          ),
        ),
      ],
    );
  }

  Widget _buildJoinedInfo(DuelParticipant participant) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.access_time,
            size: 14,
            color: Colors.grey[500],
          ),
          const SizedBox(width: 4),
          Text(
            participant.joinedAt != null 
                ? 'Joined ${_getJoinedTimeText(participant.joinedAt!)}'
                : 'Joined recently',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
            ),
          ),
          const Spacer(),
          Icon(
            Icons.update,
            size: 14,
            color: Colors.grey[500],
          ),
          const SizedBox(width: 4),
          Text(
            'Updated ${_getJoinedTimeText(participant.updatedAt)}',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
            ),
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
              Icons.group_off,
              size: 80,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 16),
            Text(
              'No participants yet',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Be the first to join this duel!',
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

  String _getParticipantSubtitle(DuelParticipant participant) {
    if (participant.id == duel.creatorId) {
      return 'Duel Creator';
    }
    return 'Participant';
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

  String _getJoinedTimeText(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}
