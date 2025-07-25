import 'package:flutter/material.dart';
import 'package:rucking_app/core/models/planned_ruck.dart';
import 'package:rucking_app/core/theme/app_colors.dart';
import 'package:rucking_app/core/theme/app_text_styles.dart';

/// Widget for displaying and selecting status filter chips
class StatusFilterChips extends StatelessWidget {
  final PlannedRuckStatus? selectedStatus;
  final ValueChanged<PlannedRuckStatus?> onStatusSelected;

  const StatusFilterChips({
    super.key,
    this.selectedStatus,
    required this.onStatusSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            // All filter chip
            _buildFilterChip(
              context: context,
              label: 'All',
              isSelected: selectedStatus == null,
              onTap: () => onStatusSelected(null),
              color: AppColors.textSecondary,
              icon: Icons.list_alt,
            ),
            const SizedBox(width: 8),

            // Status-based filter chips
            ...PlannedRuckStatus.values.map((status) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _buildFilterChip(
                  context: context,
                  label: _getStatusLabel(status),
                  isSelected: selectedStatus == status,
                  onTap: () => onStatusSelected(status),
                  color: _getStatusColor(status),
                  icon: _getStatusIcon(status),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required BuildContext context,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required Color color,
    required IconData icon,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : color.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : color,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTextStyles.caption.copyWith(
                color: isSelected ? Colors.white : color,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getStatusLabel(PlannedRuckStatus status) {
    switch (status) {
      case PlannedRuckStatus.planned:
        return 'Planned';
      case PlannedRuckStatus.inProgress:
        return 'In Progress';
      case PlannedRuckStatus.paused:
        return 'Paused';
      case PlannedRuckStatus.completed:
        return 'Completed';
      case PlannedRuckStatus.cancelled:
        return 'Cancelled';
      case PlannedRuckStatus.missed:
        return 'Missed';
    }
  }

  Color _getStatusColor(PlannedRuckStatus status) {
    switch (status) {
      case PlannedRuckStatus.planned:
        return AppColors.primary;
      case PlannedRuckStatus.inProgress:
        return AppColors.info;
      case PlannedRuckStatus.paused:
        return AppColors.warning;
      case PlannedRuckStatus.completed:
        return AppColors.success;
      case PlannedRuckStatus.cancelled:
        return AppColors.textSecondary;
      case PlannedRuckStatus.missed:
        return AppColors.error;
    }
  }

  IconData _getStatusIcon(PlannedRuckStatus status) {
    switch (status) {
      case PlannedRuckStatus.planned:
        return Icons.schedule;
      case PlannedRuckStatus.inProgress:
        return Icons.play_arrow;
      case PlannedRuckStatus.paused:
        return Icons.pause;
      case PlannedRuckStatus.completed:
        return Icons.check_circle;
      case PlannedRuckStatus.cancelled:
        return Icons.cancel;
      case PlannedRuckStatus.missed:
        return Icons.warning;
    }
  }
}

/// Advanced filter chips with additional options
class AdvancedStatusFilterChips extends StatefulWidget {
  final PlannedRuckStatus? selectedStatus;
  final ValueChanged<PlannedRuckStatus?> onStatusSelected;
  final ValueChanged<DateRange?>? onDateRangeSelected;
  final DateRange? selectedDateRange;
  final bool showDateFilter;

  const AdvancedStatusFilterChips({
    super.key,
    this.selectedStatus,
    required this.onStatusSelected,
    this.onDateRangeSelected,
    this.selectedDateRange,
    this.showDateFilter = false,
  });

  @override
  State<AdvancedStatusFilterChips> createState() => _AdvancedStatusFilterChipsState();
}

class _AdvancedStatusFilterChipsState extends State<AdvancedStatusFilterChips> {
  bool _showMoreFilters = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Primary status filters
        StatusFilterChips(
          selectedStatus: widget.selectedStatus,
          onStatusSelected: widget.onStatusSelected,
        ),

        // More filters button
        if (widget.showDateFilter)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _showMoreFilters = !_showMoreFilters;
                    });
                  },
                  icon: Icon(
                    _showMoreFilters ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                  ),
                  label: Text(
                    _showMoreFilters ? 'Less Filters' : 'More Filters',
                    style: AppTextStyles.caption,
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    minimumSize: const Size(0, 32),
                  ),
                ),
                const Spacer(),
                if (_hasActiveFilters())
                  TextButton(
                    onPressed: _clearAllFilters,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.error,
                      minimumSize: const Size(0, 32),
                    ),
                    child: const Text('Clear All'),
                  ),
              ],
            ),
          ),

        // Additional filters
        if (_showMoreFilters && widget.showDateFilter)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface.withOpacity(0.5),
              border: Border(
                top: BorderSide(
                  color: AppColors.divider,
                  width: 0.5,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Date Range',
                  style: AppTextStyles.subtitle2.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    _buildDateRangeChip('Today', _getTodayRange()),
                    _buildDateRangeChip('This Week', _getThisWeekRange()),
                    _buildDateRangeChip('This Month', _getThisMonthRange()),
                    _buildDateRangeChip('Custom', null, isCustom: true),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildDateRangeChip(String label, DateRange? range, {bool isCustom = false}) {
    final isSelected = widget.selectedDateRange == range;
    
    return GestureDetector(
      onTap: () {
        if (isCustom) {
          _showCustomDatePicker();
        } else {
          widget.onDateRangeSelected?.call(range);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.divider,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: isSelected ? Colors.white : AppColors.textSecondary,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  DateRange _getTodayRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return DateRange(start: today, end: today.add(const Duration(days: 1)));
  }

  DateRange _getThisWeekRange() {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));
    return DateRange(start: startOfWeek, end: endOfWeek);
  }

  DateRange _getThisMonthRange() {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 0);
    return DateRange(start: startOfMonth, end: endOfMonth);
  }

  bool _hasActiveFilters() {
    return widget.selectedStatus != null || widget.selectedDateRange != null;
  }

  void _clearAllFilters() {
    widget.onStatusSelected(null);
    widget.onDateRangeSelected?.call(null);
  }

  Future<void> _showCustomDatePicker() async {
    final dateRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: widget.selectedDateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: AppColors.primary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (dateRange != null) {
      widget.onDateRangeSelected?.call(dateRange);
    }
  }
}
