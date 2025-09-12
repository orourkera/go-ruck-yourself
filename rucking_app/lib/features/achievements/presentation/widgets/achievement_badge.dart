import 'package:flutter/material.dart';
import 'package:rucking_app/features/achievements/data/models/achievement_model.dart';

class AchievementBadge extends StatelessWidget {
  final Achievement achievement;
  final bool isEarned;
  final double? progress;
  final VoidCallback? onTap;
  final double size;

  const AchievementBadge({
    super.key,
    required this.achievement,
    required this.isEarned,
    this.progress,
    this.onTap,
    this.size = 60.0,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: isEarned ? _getEarnedGradient() : null,
          color: isEarned ? null : Colors.grey.shade300,
          border: Border.all(
            color: isEarned ? _getBorderColor() : Colors.grey.shade400,
            width: 2.0,
          ),
          boxShadow: isEarned
              ? [
                  BoxShadow(
                    color: _getBorderColor().withOpacity(0.3),
                    blurRadius: 8.0,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Stack(
          children: [
            // Progress ring for unearned achievements
            if (!isEarned && progress != null && progress! > 0)
              Positioned.fill(
                child: CircularProgressIndicator(
                  value: progress! / 100,
                  strokeWidth: 3.0,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _getCategoryColor().withOpacity(0.7),
                  ),
                ),
              ),

            // Medal icon
            Center(
              child: Icon(
                _getMedalIcon(),
                size: size * 0.5,
                color: isEarned ? Colors.white : Colors.grey.shade600,
              ),
            ),

            // Tier indicator
            if (isEarned)
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: size * 0.3,
                  height: size * 0.3,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _getTierColor(),
                    border: Border.all(color: Colors.white, width: 1.0),
                  ),
                  child: Center(
                    child: Text(
                      _getTierSymbol(),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: size * 0.15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  LinearGradient _getEarnedGradient() {
    final categoryColor = _getCategoryColor();
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        categoryColor.withOpacity(0.8),
        categoryColor,
        categoryColor.withOpacity(0.9),
      ],
    );
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

  Color _getBorderColor() {
    return _getCategoryColor().withOpacity(0.8);
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

  String _getTierSymbol() {
    switch (achievement.tier.toLowerCase()) {
      case 'bronze':
        return 'B';
      case 'silver':
        return 'S';
      case 'gold':
        return 'G';
      case 'platinum':
        return 'P';
      default:
        return '?';
    }
  }

  IconData _getMedalIcon() {
    switch (achievement.category.toLowerCase()) {
      case 'distance':
        return Icons.directions_run;
      case 'weight':
        return Icons.fitness_center;
      case 'power':
        return Icons.flash_on;
      case 'pace':
        return Icons.speed;
      case 'time':
        return Icons.access_time;
      case 'consistency':
        return Icons.calendar_today;
      case 'special':
        return Icons.star;
      default:
        return Icons.emoji_events;
    }
  }
}
