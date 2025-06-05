import 'package:flutter/material.dart';
import '../../domain/entities/duel_invitation.dart';
import '../../../../shared/theme/app_colors.dart';

class DuelInvitationCard extends StatelessWidget {
  final DuelInvitation invitation;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final VoidCallback? onViewDuel;
  final bool isResponding;

  const DuelInvitationCard({
    super.key,
    required this.invitation,
    this.onAccept,
    this.onDecline,
    this.onViewDuel,
    this.isResponding = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onViewDuel,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 12),
              _buildDuelInfo(),
              const SizedBox(height: 12),
              _buildTimestamp(),
              if (invitation.status == 'pending') ...[
                const SizedBox(height: 16),
                _buildActionButtons(),
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
        const Spacer(),
        Icon(
          Icons.chevron_right,
          color: Colors.grey[400],
        ),
      ],
    );
  }

  Widget _buildDuelInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          invitation.duelTitle ?? 'Untitled Duel',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              Icons.person,
              size: 16,
              color: Colors.grey[600],
            ),
            const SizedBox(width: 4),
            Text(
              'Invited by ${invitation.inviterUsername ?? 'Unknown'}',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
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
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTimestamp() {
    return Row(
      children: [
        Icon(
          Icons.access_time,
          size: 14,
          color: Colors.grey[500],
        ),
        const SizedBox(width: 4),
        Text(
          _getTimeAgoText(),
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[500],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: isResponding ? null : onDecline,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
            ),
            child: isResponding
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                    ),
                  )
                : const Text('Decline'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: isResponding ? null : onAccept,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
            ),
            child: isResponding
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text('Accept'),
          ),
        ),
      ],
    );
  }

  Color _getStatusColor() {
    switch (invitation.status) {
      case 'pending':
        return Colors.orange;
      case 'accepted':
        return Colors.green;
      case 'declined':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText() {
    switch (invitation.status) {
      case 'pending':
        return 'Pending';
      case 'accepted':
        return 'Accepted';
      case 'declined':
        return 'Declined';
      default:
        return 'Unknown';
    }
  }

  IconData _getChallengeIcon() {
    switch (invitation.challengeType) {
      case 'distance':
        return Icons.straighten;
      case 'time':
        return Icons.timer;
      case 'elevation':
        return Icons.terrain;
      case 'power_points':
        return Icons.bolt;
      default:
        return Icons.sports;
    }
  }

  String _getChallengeDescription() {
    final unit = _getUnit();
    if (invitation.targetValue == null) return 'No target set';
    final value = invitation.targetValue!;
    return 'Reach ${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)} $unit';
  }

  String _getUnit() {
    switch (invitation.challengeType) {
      case 'distance':
        return 'km';
      case 'time':
        return 'minutes';
      case 'elevation':
        return 'm';
      case 'power_points':
        return 'points';
      default:
        return '';
    }
  }

  String _getTimeAgoText() {
    final now = DateTime.now();
    final difference = now.difference(invitation.createdAt);

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
