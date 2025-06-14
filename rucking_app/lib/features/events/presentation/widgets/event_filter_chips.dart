import 'package:flutter/material.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

class EventFilterChips extends StatelessWidget {
  final String? selectedStatus;
  final String? selectedClubId;
  final bool? includeParticipating;
  final Function(String? status, String? clubId, bool? includeParticipating) onFilterChanged;

  const EventFilterChips({
    Key? key,
    this.selectedStatus,
    this.selectedClubId,
    this.includeParticipating,
    required this.onFilterChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _buildFilterChip(
            context,
            label: 'All',
            isSelected: selectedStatus == null && includeParticipating == null,
            onTap: () => onFilterChanged(null, null, null),
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            context,
            label: 'Upcoming',
            isSelected: selectedStatus == 'active',
            onTap: () => onFilterChanged('active', null, null),
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            context,
            label: 'My Events',
            isSelected: includeParticipating == true,
            onTap: () => onFilterChanged(null, null, true),
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            context,
            label: 'Club Events',
            isSelected: selectedClubId != null,
            onTap: () => onFilterChanged(null, 'any', null),
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            context,
            label: 'Completed',
            isSelected: selectedStatus == 'completed',
            onTap: () => onFilterChanged('completed', null, null),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(
    BuildContext context, {
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected 
              ? Theme.of(context).primaryColor 
              : Colors.transparent,
          border: Border.all(
            color: isSelected 
                ? Theme.of(context).primaryColor 
                : Colors.grey.withOpacity(0.3),
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: AppTextStyles.labelMedium.copyWith(
            color: isSelected 
                ? Colors.white 
                : Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black87,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
