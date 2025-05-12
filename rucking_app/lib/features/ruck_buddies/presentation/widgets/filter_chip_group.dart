import 'package:flutter/material.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

class FilterChipGroup extends StatelessWidget {
  final String selectedFilter;
  final Function(String) onFilterSelected;

  const FilterChipGroup({
    Key? key,
    required this.selectedFilter,
    required this.onFilterSelected,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildFilterChip('closest', 'Closest', Icons.location_on),
          const SizedBox(width: 8),
          _buildFilterChip('calories', 'Most Calories', Icons.local_fire_department),
          const SizedBox(width: 8),
          _buildFilterChip('distance', 'Furthest', Icons.straighten),
          const SizedBox(width: 8),
          _buildFilterChip('duration', 'Longest', Icons.timer),
          const SizedBox(width: 8),
          _buildFilterChip('elevation', 'Most Elevation', Icons.terrain),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String value, String label, IconData icon) {
    final bool isSelected = selectedFilter == value;
    
    return FilterChip(
      avatar: Icon(
        icon,
        color: isSelected ? Colors.white : AppColors.secondary,
        size: 18,
      ),
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.white : Colors.black87,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      selectedColor: AppColors.secondary,
      backgroundColor: Colors.grey[200],
      onSelected: (_) => onFilterSelected(value),
      showCheckmark: false,
      elevation: isSelected ? 2 : 0,
    );
  }
}
