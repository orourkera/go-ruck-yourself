import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            _buildFilterChip('following', 'My Buddies', Icons.people),
            const SizedBox(width: 8),
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
      ),
    );
  }

  Widget _buildFilterChip(String value, String label, IconData icon) {
    final bool isSelected = selectedFilter == value;
    
    // Check for lady mode
    return Builder(
      builder: (context) {
        // Check for lady mode in AuthBloc
        bool isLadyMode = false;
        try {
          final authBloc = BlocProvider.of<AuthBloc>(context);
          if (authBloc.state is Authenticated) {
            isLadyMode = (authBloc.state as Authenticated).user.gender == 'female';
          }
        } catch (e) {
          // Default to standard mode if error
        }
        
        // Use lady color for female users
        final Color accentColor = isLadyMode ? AppColors.ladyPrimary : AppColors.secondary;
        
        return FilterChip(
          avatar: Icon(
            icon,
            color: isSelected ? Colors.white : accentColor,
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
          selectedColor: accentColor,
          backgroundColor: Colors.grey[200],
          onSelected: (_) => onFilterSelected(value),
          showCheckmark: false,
          elevation: isSelected ? 2 : 0,
        );
      },
    );
  }
}
