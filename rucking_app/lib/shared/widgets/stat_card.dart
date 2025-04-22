import 'package:flutter/material.dart';
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
    // Split value into numeric part and unit part
    String numericPart = value;
    String unitPart = '';
    
    // Look for common patterns like '10 km', '5:30', '+10.5 m'
    final spaceIndex = value.indexOf(' ');
    if (spaceIndex > 0) {
      numericPart = value.substring(0, spaceIndex);
      unitPart = value.substring(spaceIndex);
    }
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
            
            // Main content area with value
            Expanded(
              child: Center(
                child: Text(
                  numericPart,
                  style: AppTextStyles.headline4.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            
            // Unit part at the bottom
            if (unitPart.isNotEmpty)
              Text(
                unitPart,
                style: AppTextStyles.body2.copyWith(
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            
            // Secondary value (if provided)
            if (secondaryValue != null)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  secondaryValue!,
                  style: AppTextStyles.body2.copyWith(
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
} 