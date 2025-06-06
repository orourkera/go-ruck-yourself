import 'package:flutter/material.dart';
import '../../domain/entities/duel.dart';
import '../../domain/entities/duel_participant.dart';
import '../../../../shared/theme/app_colors.dart';

class DuelInfoCard extends StatelessWidget {
  final Duel duel;
  final List<DuelParticipant> participants;
  final String currentUserId;
  final VoidCallback? onJoin;
  final VoidCallback? onStartDuel;
  final bool isJoining;
  final bool isStarting;
  final bool showJoinButton;
  final bool showStartButton;

  const DuelInfoCard({
    super.key,
    required this.duel,
    required this.participants,
    required this.currentUserId,
    this.onJoin,
    this.onStartDuel,
    this.isJoining = false,
    this.isStarting = false,
    this.showJoinButton = false,
    this.showStartButton = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.secondary,
                AppColors.secondary.withOpacity(0.8),
              ],
            ),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              _buildTitle(),
              const SizedBox(height: 12),
              _buildChallengeDetails(),
              const SizedBox(height: 16),
              _buildStats(),
              if (onStartDuel != null && showStartButton) ...[                
                const SizedBox(height: 16),
                _buildStartButton(),
              ],
              if (onJoin != null && showJoinButton) ...[
                const SizedBox(height: 16),
                _buildJoinButton(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.9),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _getStatusText(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const Spacer(),
        if (!duel.isPublic)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.9),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Private',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTitle() {
    return Text(
      duel.title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 24,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildChallengeDetails() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                _getChallengeIcon(),
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _getChallengeDescription(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.schedule,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                _getTimeframeText(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          if (_shouldShowLocation()) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.location_on,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  _getLocationText(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStats() {
    return Row(
      children: [
        Expanded(
          child: _buildStatItem(
            'Participants',
            '${participants.length}/${duel.maxParticipants}',
            Icons.people,
          ),
        ),
        Container(
          width: 1,
          height: 40,
          color: Colors.white.withOpacity(0.3),
        ),
        Expanded(
          child: _buildStatItem(
            'Progress',
            '${(_calculateTopProgress() * 100).toInt()}%',
            Icons.trending_up,
          ),
        ),
        if (duel.winnerId != null) ...[
          Container(
            width: 1,
            height: 40,
            color: Colors.white.withOpacity(0.3),
          ),
          Expanded(
            child: _buildStatItem(
              'Winner',
              'Champion',
              Icons.emoji_events,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(
          icon,
          color: Colors.white,
          size: 20,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildJoinButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isJoining ? null : onJoin,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: isJoining
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Text(
                'Join Duel',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }
  
  Widget _buildStartButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isStarting ? null : onStartDuel,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: isStarting
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Text(
                'Start Duel',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  String _getStatusText() {
    switch (duel.status) {
      case DuelStatus.pending:
        return 'Starting Soon';
      case DuelStatus.active:
        return 'In Progress';
      case DuelStatus.completed:
        return 'Completed';
      case DuelStatus.cancelled:
        return 'Cancelled';
      default:
        // Debug log to understand what status value we're getting
        print('DEBUG: Unknown duel status: ${duel.status}');
        return 'Pending';
    }
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

  String _getChallengeDescription() {
    final unit = _getUnit();
    return 'Reach ${duel.targetValue.toStringAsFixed(duel.targetValue % 1 == 0 ? 0 : 1)} $unit';
  }

  String _getUnit() {
    switch (duel.challengeType) {
      case DuelChallengeType.distance:
        return 'km';
      case DuelChallengeType.time:
        return 'minutes';
      case DuelChallengeType.elevation:
        return 'meters';
      case DuelChallengeType.powerPoints:
        return 'power points';
      default:
        return '';
    }
  }

  String _getTimeframeText() {
    if (duel.timeframeHours < 24) {
      return '${duel.timeframeHours} hours';
    } else {
      final days = duel.timeframeHours ~/ 24;
      final hours = duel.timeframeHours % 24;
      if (hours == 0) {
        return '$days days';
      } else {
        return '$days days, $hours hours';
      }
    }
  }

  String _getLocationText() {
    final parts = <String>[];
    if (duel.creatorCity != null && duel.creatorCity != 'Unknown') parts.add(duel.creatorCity!);
    if (duel.creatorState != null && duel.creatorState != 'Unknown') parts.add(duel.creatorState!);
    return parts.join(', ');
  }

  bool _shouldShowLocation() {
    return (duel.creatorCity != null && duel.creatorCity != 'Unknown') || (duel.creatorState != null && duel.creatorState != 'Unknown');
  }

  double _calculateTopProgress() {
    if (participants.isEmpty) return 0.0;
    
    final maxProgress = participants
        .map((DuelParticipant p) => p.currentValue / duel.targetValue)
        .reduce((a, b) => a > b ? a : b);
    
    return maxProgress.clamp(0.0, 1.0);
  }
}
