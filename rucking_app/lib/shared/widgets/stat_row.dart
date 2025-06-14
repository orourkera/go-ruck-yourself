import 'package:flutter/material.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

/// Reusable widget for displaying stat rows with icon, label, and value
class StatRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final double iconSize;
  final Color? iconColor;
  final bool showLabel;
  final CrossAxisAlignment alignment;

  const StatRow({
    Key? key,
    required this.icon,
    required this.label,
    required this.value,
    this.iconSize = 20,
    this.iconColor,
    this.showLabel = true,
    this.alignment = CrossAxisAlignment.start,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: alignment,
      children: [
        Icon(
          icon,
          size: iconSize,
          color: iconColor ?? Theme.of(context).primaryColor,
        ),
        SizedBox(width: iconSize > 16 ? 8 : 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showLabel)
                Text(
                  label,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              Text(
                value,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
