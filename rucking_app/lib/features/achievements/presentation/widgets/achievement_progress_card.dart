import 'package:flutter/material.dart';
import 'package:rucking_app/features/achievements/data/models/achievement_model.dart';
import 'package:rucking_app/features/achievements/presentation/widgets/achievement_badge.dart';

class AchievementProgressCard extends StatelessWidget {
  final Achievement achievement;
  final AchievementProgress? progress;
  final bool isEarned;
  final VoidCallback? onTap;

  const AchievementProgressCard({
    super.key,
    required this.achievement,
    this.progress,
    required this.isEarned,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progressPercentage = progress?.progressPercentage ?? 0.0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      elevation: isEarned ? 4.0 : 2.0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12.0),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              // Achievement badge
              AchievementBadge(
                achievement: achievement,
                isEarned: isEarned,
                progress: progressPercentage,
                size: 50.0,
              ),

              const SizedBox(width: 16.0),

              // Achievement details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Achievement name
                    Text(
                      achievement.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isEarned
                            ? _getCategoryColor()
                            : theme.textTheme.titleMedium?.color,
                      ),
                    ),

                    const SizedBox(height: 4.0),

                    // Achievement description
                    Text(
                      achievement.description,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color:
                            theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    const SizedBox(height: 8.0),

                    // Progress bar or completed indicator
                    if (isEarned)
                      _buildCompletedIndicator(theme)
                    else if (progress != null)
                      _buildProgressIndicator(theme)
                    else
                      _buildLockedIndicator(theme),
                  ],
                ),
              ),

              // Tier indicator
              if (isEarned) _buildTierChip(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompletedIndicator(ThemeData theme) {
    return Row(
      children: [
        Icon(
          Icons.check_circle,
          color: _getCategoryColor(),
          size: 16.0,
        ),
        const SizedBox(width: 4.0),
        Text(
          'Completed',
          style: theme.textTheme.bodySmall?.copyWith(
            color: _getCategoryColor(),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildProgressIndicator(ThemeData theme) {
    final progressPercentage = progress!.progressPercentage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Progress',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
              ),
            ),
            Text(
              '${progressPercentage.toStringAsFixed(1)}%',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: _getCategoryColor(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4.0),
        LinearProgressIndicator(
          value: progressPercentage / 100,
          backgroundColor: Colors.grey.shade300,
          valueColor: AlwaysStoppedAnimation<Color>(_getCategoryColor()),
          minHeight: 6.0,
        ),
        const SizedBox(height: 4.0),
        Text(
          _getProgressText(),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildLockedIndicator(ThemeData theme) {
    return Row(
      children: [
        Icon(
          Icons.lock_outline,
          color: Colors.grey.shade500,
          size: 16.0,
        ),
        const SizedBox(width: 4.0),
        Text(
          'Locked',
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.grey.shade500,
          ),
        ),
      ],
    );
  }

  Widget _buildTierChip(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: _getTierColor(),
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Text(
        achievement.tier.toUpperCase(),
        style: theme.textTheme.bodySmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 10.0,
        ),
      ),
    );
  }

  String _getProgressText() {
    if (progress == null) return '';

    final current = progress!.currentValue;
    final target = progress!.targetValue;

    // Format based on achievement type
    switch (achievement.category.toLowerCase()) {
      case 'distance':
        return '${current.toStringAsFixed(1)} / ${target.toStringAsFixed(1)} km';
      case 'weight':
        return '${current.toStringAsFixed(1)} / ${target.toStringAsFixed(1)} kg';
      case 'time':
        return '${_formatDuration(current)} / ${_formatDuration(target)}';
      case 'pace':
        return '${_formatPace(current)} / ${_formatPace(target)}';
      default:
        return '${current.toStringAsFixed(0)} / ${target.toStringAsFixed(0)}';
    }
  }

  String _formatDuration(double seconds) {
    final duration = Duration(seconds: seconds.toInt());
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
    } else {
      return '${duration.inMinutes}m';
    }
  }

  String _formatPace(double secPerKm) {
    final minutes = secPerKm ~/ 60;
    final seconds = (secPerKm % 60).toInt();
    return '${minutes}:${seconds.toString().padLeft(2, '0')}/km';
  }

  Color _getCategoryColor() {
    switch (achievement.category.toLowerCase()) {
      case 'distance':
        return Colors.blue;
      case 'weight':
        return Colors.red;
      case 'power':
        return Colors.orange;
      case 'pace':
        return Colors.green;
      case 'time':
        return Colors.purple;
      case 'consistency':
        return Colors.teal;
      case 'special':
        return Colors.pink;
      default:
        return Colors.grey;
    }
  }

  Color _getTierColor() {
    switch (achievement.tier.toLowerCase()) {
      case 'bronze':
        return const Color(0xFFCD7F32);
      case 'silver':
        return const Color(0xFFC0C0C0);
      case 'gold':
        return const Color(0xFFFFD700);
      case 'platinum':
        return const Color(0xFFE5E4E2);
      default:
        return Colors.grey;
    }
  }
}
