import 'package:flutter/material.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

/// Widget for selecting the method to import a route
class ImportMethodSelector extends StatelessWidget {
  final String? selectedMethod;
  final Function(String) onMethodSelected;

  const ImportMethodSelector({
    super.key,
    required this.selectedMethod,
    required this.onMethodSelected,
  });

  @override
  Widget build(BuildContext context) {
    final methods = [
      {
        'key': 'file',
        'title': 'GPX File',
        'subtitle': 'Import from GPX file',
        'icon': Icons.upload_file,
      },
      {
        'key': 'url',
        'title': 'AllTrails URL',
        'subtitle': 'Import from AllTrails link',
        'icon': Icons.link,
      },
      {
        'key': 'search',
        'title': 'Search Routes',
        'subtitle': 'Find routes in our database',
        'icon': Icons.search,
      },
    ];

    return Card(
      elevation: 2,
      color: AppColors.surfaceLight,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Import Method',
              style: AppTextStyles.titleLarge.copyWith(
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 16),
            ...methods.map((method) => _buildMethodOption(
                  context,
                  method['key'] as String,
                  method['title'] as String,
                  method['subtitle'] as String,
                  method['icon'] as IconData,
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildMethodOption(
    BuildContext context,
    String key,
    String title,
    String subtitle,
    IconData icon,
  ) {
    final isSelected = selectedMethod == key;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onMethodSelected(key),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(
                color: isSelected ? AppColors.primary : AppColors.dividerLight,
                width: isSelected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
              color: isSelected
                  ? AppColors.primary.withOpacity(0.1)
                  : Colors.transparent,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : AppColors.greyLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    color: isSelected ? Colors.white : AppColors.greyDark,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textDark,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textDarkSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Icon(
                    Icons.check_circle,
                    color: AppColors.primary,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
