import 'package:flutter/material.dart';
import 'package:rucking_app/features/achievements/data/models/achievement_model.dart';
import 'package:rucking_app/features/achievements/presentation/widgets/achievement_badge.dart';
import 'package:rucking_app/features/achievements/presentation/widgets/achievement_unlock_popup.dart';

class SessionAchievementNotification extends StatelessWidget {
  final List<Achievement> newAchievements;
  final VoidCallback? onDismiss;
  final VoidCallback? onViewDetails;

  const SessionAchievementNotification({
    super.key,
    required this.newAchievements,
    this.onDismiss,
    this.onViewDetails,
  });

  @override
  Widget build(BuildContext context) {
    if (newAchievements.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final achievement = newAchievements.first;
    final hasMultiple = newAchievements.length > 1;

    return Card(
      margin: const EdgeInsets.all(16.0),
      elevation: 4.0,
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 400,
          maxHeight: 500,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12.0),
          gradient: LinearGradient(
            colors: [
              _getCategoryColor(achievement).withOpacity(0.1),
              _getCategoryColor(achievement).withOpacity(0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    Icons.celebration,
                    color: _getCategoryColor(achievement),
                    size: 24,
                  ),
                  const SizedBox(width: 8.0),
                  Expanded(
                    child: Text(
                      hasMultiple 
                          ? 'New Achievements Unlocked!' 
                          : 'Achievement Unlocked!',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: _getCategoryColor(achievement),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: onDismiss,
                    icon: const Icon(Icons.close),
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              
              const SizedBox(height: 16.0),
              
              // Achievement display
              if (hasMultiple)
                _buildMultipleAchievements(theme)
              else
                _buildSingleAchievement(theme, achievement),
              
              const SizedBox(height: 16.0),
              
              // Action buttons
              Row(
                children: [
                  if (hasMultiple)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _showAllAchievements(context),
                        child: Text('View All (${newAchievements.length})'),
                      ),
                    )
                  else
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onViewDetails,
                        child: const Text('View Details'),
                      ),
                    ),
                  
                  const SizedBox(width: 12.0),
                  
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _showAllAchievements(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _getCategoryColor(achievement),
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Celebrate!'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSingleAchievement(ThemeData theme, Achievement achievement) {
    return Row(
      children: [
        AchievementBadge(
          achievement: achievement,
          isEarned: true,
          size: 60,
        ),
        const SizedBox(width: 16.0),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                achievement.name,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4.0),
              Text(
                achievement.description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8.0),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                decoration: BoxDecoration(
                  color: _getTierColor(achievement),
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
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMultipleAchievements(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'You unlocked ${newAchievements.length} achievements in this session!',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 12.0),
        Container(
          height: 80,
          width: double.infinity,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(newAchievements.length, (index) {
              final achievement = newAchievements[index];
              return Padding(
                padding: const EdgeInsets.only(right: 12.0),
                child: Column(
                  children: [
                    AchievementBadge(
                      achievement: achievement,
                      isEarned: true,
                      size: 50,
                    ),
                    const SizedBox(height: 4.0),
                    SizedBox(
                      width: 60,
                      child: Text(
                        achievement.name,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 10,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }),
            ),
          ),
        ),
      ],
    );
  }

  void _showAllAchievements(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AchievementUnlockPopup(
        newAchievements: newAchievements,
        onDismiss: onDismiss,
      ),
    );
  }

  Color _getCategoryColor(Achievement achievement) {
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

  Color _getTierColor(Achievement achievement) {
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
