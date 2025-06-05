import 'package:flutter/material.dart';
import '../../domain/entities/duel.dart';
import '../../domain/entities/duel_participant.dart';
import '../../../../shared/theme/app_colors.dart';

class DuelCard extends StatelessWidget {
  final Duel duel;
  final List<DuelParticipant> participants;
  final VoidCallback? onTap;
  final VoidCallback? onJoin;
  final bool showJoinButton;

  const DuelCard({
    super.key,
    required this.duel,
    required this.participants,
    this.onTap,
    this.onJoin,
    this.showJoinButton = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 12),
              _buildChallengeInfo(),
              const SizedBox(height: 12),
              _buildProgressBar(),
              const SizedBox(height: 12),
              _buildFooter(context),
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _getStatusColor(),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _getStatusText(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (!duel.isPublic)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.orange,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Private',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        const Spacer(),
        Text(
          '${participants.length}/${duel.maxParticipants}',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
          ),
        ),
        const SizedBox(width: 4),
        Icon(
          Icons.people,
          size: 16,
          color: Colors.grey[600],
        ),
      ],
    );
  }

  Widget _buildChallengeInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          duel.title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              _getChallengeIcon(),
              size: 16,
              color: AppColors.primary,
            ),
            const SizedBox(width: 4),
            Text(
              _getChallengeDescription(),
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 14,
              ),
            ),
          ],
        ),
        if (_shouldShowLocation()) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.location_on,
                size: 16,
                color: Colors.grey[500],
              ),
              const SizedBox(width: 4),
              Text(
                _getLocationText(),
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildProgressBar() {
    final progress = _calculateProgress();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Progress',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            Text(
              '${(progress * 100).toInt()}%',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: progress,
          backgroundColor: Colors.grey[200],
          valueColor: AlwaysStoppedAnimation<Color>(
            progress >= 1.0 ? Colors.green : AppColors.accent,
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _getTimeInfo(),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              if (duel.winnerId != null)
                Text(
                  'Winner: ${_getWinnerText()}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.green,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
        if (_shouldShowJoinButton()) ...[
          const SizedBox(width: 12),
          SizedBox(
            height: 32,
            child: ElevatedButton(
              onPressed: showJoinButton ? () => onJoin?.call() : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: showJoinButton
                  ? const Text(
                      'Join',
                      style: TextStyle(fontSize: 12),
                    )
                  : const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
            ),
          ),
        ],
      ],
    );
  }

  Color _getStatusColor() {
    switch (duel.status) {
      case DuelStatus.pending:
        return Colors.orange;
      case DuelStatus.active:
        return Colors.blue;
      case DuelStatus.completed:
        return Colors.green;
      case DuelStatus.cancelled:
        return Colors.red;
    }
  }

  String _getStatusText() {
    switch (duel.status) {
      case DuelStatus.pending:
        return 'Pending';
      case DuelStatus.active:
        return 'Active';
      case DuelStatus.completed:
        return 'Completed';
      case DuelStatus.cancelled:
        return 'Cancelled';
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
    }
  }

  String _getChallengeDescription() {
    final typeText = duel.challengeTypeDisplayName.toLowerCase();
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
        return 'm';
      case DuelChallengeType.powerPoints:
        return 'power points';
    }
  }

  String _getLocationText() {
    final parts = <String>[];
    if (duel.creatorCity != null && duel.creatorCity != 'Unknown') parts.add(duel.creatorCity!);
    if (duel.creatorState != null && duel.creatorState != 'Unknown') parts.add(duel.creatorState!);
    return parts.join(', ');
  }

  double _calculateProgress() {
    if (participants.isEmpty) return 0.0;
    
    final maxProgress = participants
        .map((DuelParticipant p) => p.currentValue / duel.targetValue)
        .reduce((a, b) => a > b ? a : b);
    
    return maxProgress.clamp(0.0, 1.0);
  }

  String _getTimeInfo() {
    final now = DateTime.now();
    
    if (duel.endsAt != null) {
      final timeLeft = duel.endsAt!.difference(now);
      if (timeLeft.isNegative) {
        return 'Ended';
      } else if (timeLeft.inDays > 0) {
        return '${timeLeft.inDays}d ${timeLeft.inHours % 24}h left';
      } else if (timeLeft.inHours > 0) {
        return '${timeLeft.inHours}h ${timeLeft.inMinutes % 60}m left';
      } else {
        return '${timeLeft.inMinutes}m left';
      }
    }
    
    return '${duel.timeframeHours}h duration';
  }

  String _getWinnerText() {
    // TODO: Get winner name from participants or user service
    return 'Champion';
  }

  bool _shouldShowJoinButton() {
    return onJoin != null && 
           (duel.status == DuelStatus.pending || duel.status == DuelStatus.active) &&
           participants.length < duel.maxParticipants;
  }

  bool _shouldShowLocation() {
    return (duel.creatorCity != null && duel.creatorCity != 'Unknown') || (duel.creatorState != null && duel.creatorState != 'Unknown');
  }
}
