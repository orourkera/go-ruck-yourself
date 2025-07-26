import 'package:flutter/material.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

/// Widget for displaying route difficulty as a styled badge
class DifficultyBadge extends StatelessWidget {
  final String difficulty;
  final bool compact;

  const DifficultyBadge({
    super.key,
    required this.difficulty,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = _getDifficultyColor(difficulty);
    final backgroundColor = color.withOpacity(0.1);
    
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(compact ? 4 : 6),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Text(
        difficulty.toUpperCase(),
        style: AppTextStyles.bodySmall.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Color _getDifficultyColor(String difficulty) {
    switch (difficulty.toLowerCase()) {
      case 'easy':
        return AppColors.success;
      case 'moderate':
      case 'medium':
        return AppColors.warning;
      case 'hard':
      case 'difficult':
        return AppColors.error;
      case 'expert':
      case 'extreme':
        return AppColors.errorDark;
      default:
        return AppColors.greyDark;
    }
  }
}

/// Utility function to get difficulty display text
String getDifficultyDisplayText(String? difficulty) {
  if (difficulty == null || difficulty.isEmpty) {
    return 'Unknown';
  }
  
  switch (difficulty.toLowerCase()) {
    case 'easy':
      return 'Easy';
    case 'moderate':
    case 'medium':
      return 'Moderate';
    case 'hard':
    case 'difficult':
      return 'Hard';
    case 'expert':
      return 'Expert';
    case 'extreme':
      return 'Extreme';
    default:
      return difficulty;
  }
}
