import 'package:flutter/material.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

/// Form widget for creating a planned ruck when importing a route
class PlannedRuckCreationForm extends StatefulWidget {
  final bool createPlannedRuck;
  final DateTime? plannedDate;
  final String? notes;
  final ValueChanged<bool> onCreatePlannedRuckChanged;
  final ValueChanged<DateTime?> onPlannedDateChanged;
  final ValueChanged<String?> onNotesChanged;

  const PlannedRuckCreationForm({
    super.key,
    required this.createPlannedRuck,
    this.plannedDate,
    this.notes,
    required this.onCreatePlannedRuckChanged,
    required this.onPlannedDateChanged,
    required this.onNotesChanged,
  });

  @override
  State<PlannedRuckCreationForm> createState() => _PlannedRuckCreationFormState();
}

class _PlannedRuckCreationFormState extends State<PlannedRuckCreationForm>
    with SingleTickerProviderStateMixin {
  late TextEditingController _notesController;
  late AnimationController _animationController;
  late Animation<double> _expansionAnimation;

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController(text: widget.notes);
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _expansionAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );

    if (widget.createPlannedRuck) {
      _animationController.forward();
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.createPlannedRuck 
              ? AppColors.primary.withOpacity(0.3)
              : AppColors.divider,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with toggle
          InkWell(
            onTap: () => widget.onCreatePlannedRuckChanged(!widget.createPlannedRuck),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 20,
                    color: widget.createPlannedRuck 
                        ? AppColors.primary 
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Create Planned Ruck',
                      style: AppTextStyles.subtitle1.copyWith(
                        fontWeight: FontWeight.bold,
                        color: widget.createPlannedRuck 
                            ? AppColors.primary 
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Switch(
                    value: widget.createPlannedRuck,
                    onChanged: widget.onCreatePlannedRuckChanged,
                    activeColor: AppColors.primary,
                  ),
                ],
              ),
            ),
          ),

          // Expandable form content
          SizeTransition(
            sizeFactor: _expansionAnimation,
            child: Container(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  
                  // Date selector
                  Text('Planned Date', style: AppTextStyles.subtitle2),
                  const SizedBox(height: 8),
                  _buildDateSelector(),
                  
                  const SizedBox(height: 16),
                  
                  // Notes field
                  Text('Notes', style: AppTextStyles.subtitle2),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      hintText: 'Add notes...',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                    onChanged: widget.onNotesChanged,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSelector() {
    return ElevatedButton(
      onPressed: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: widget.plannedDate ?? DateTime.now(),
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (date != null) {
          widget.onPlannedDateChanged(date);
        }
      },
      child: Text(widget.plannedDate?.toString() ?? 'Select Date'),
    );
  }
}
