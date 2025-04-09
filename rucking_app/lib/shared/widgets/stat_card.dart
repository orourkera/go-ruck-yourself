import 'package:flutter/material.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

/// A card widget for displaying stat metrics in the active session screen
class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String? secondaryValue;
  final IconData icon;
  final Color color;

  const StatCard({
    Key? key,
    required this.title,
    required this.value,
    this.secondaryValue,
    required this.icon,
    required this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Title and icon
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: AppTextStyles.body2.copyWith(
                    color: Colors.grey[700],
                  ),
                ),
                Icon(
                  icon,
                  color: color,
                  size: 20,
                ),
              ],
            ),
            
            // Value
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                value,
                style: AppTextStyles.headline6.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
            
            // Secondary value (if provided)
            if (secondaryValue != null)
              Text(
                secondaryValue!,
                style: AppTextStyles.body2.copyWith(
                  color: Colors.grey[600],
                ),
              ),
          ],
        ),
      ),
    );
  }
} 