import 'package:flutter/material.dart';
import '../../../../shared/theme/app_colors.dart';

class DuelFilterSheet extends StatefulWidget {
  final Function(String? status, String? challengeType, String? location) onApplyFilters;
  final VoidCallback onClearFilters;

  const DuelFilterSheet({
    super.key,
    required this.onApplyFilters,
    required this.onClearFilters,
  });

  @override
  State<DuelFilterSheet> createState() => _DuelFilterSheetState();
}

class _DuelFilterSheetState extends State<DuelFilterSheet> {
  String? _selectedStatus;
  String? _selectedChallengeType;
  final _locationController = TextEditingController();

  @override
  void dispose() {
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              children: [
                // Handle
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                
                // Header
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Filter Duels',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton(
                        onPressed: widget.onClearFilters,
                        child: const Text('Clear All'),
                      ),
                    ],
                  ),
                ),
                
                const Divider(height: 1),
                
                // Filter Options
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildStatusFilter(),
                      const SizedBox(height: 24),
                      _buildChallengeTypeFilter(),
                      const SizedBox(height: 24),
                      _buildLocationFilter(),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
                
                // Action Buttons
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    border: Border(
                      top: BorderSide(color: Colors.grey[200]!),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _applyFilters,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Apply Filters'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusFilter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Status',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildFilterChip(
              label: 'All',
              isSelected: _selectedStatus == null,
              onSelected: () => setState(() => _selectedStatus = null),
            ),
            _buildFilterChip(
              label: 'Pending',
              isSelected: _selectedStatus == 'pending',
              onSelected: () => setState(() => _selectedStatus = 'pending'),
            ),
            _buildFilterChip(
              label: 'Active',
              isSelected: _selectedStatus == 'active',
              onSelected: () => setState(() => _selectedStatus = 'active'),
            ),
            _buildFilterChip(
              label: 'Completed',
              isSelected: _selectedStatus == 'completed',
              onSelected: () => setState(() => _selectedStatus = 'completed'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildChallengeTypeFilter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Challenge Type',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildFilterChip(
              label: 'All',
              isSelected: _selectedChallengeType == null,
              onSelected: () => setState(() => _selectedChallengeType = null),
            ),
            _buildFilterChip(
              label: 'Distance',
              isSelected: _selectedChallengeType == 'distance',
              onSelected: () => setState(() => _selectedChallengeType = 'distance'),
            ),
            _buildFilterChip(
              label: 'Time',
              isSelected: _selectedChallengeType == 'time',
              onSelected: () => setState(() => _selectedChallengeType = 'time'),
            ),
            _buildFilterChip(
              label: 'Elevation',
              isSelected: _selectedChallengeType == 'elevation',
              onSelected: () => setState(() => _selectedChallengeType = 'elevation'),
            ),
            _buildFilterChip(
              label: 'Power Points',
              isSelected: _selectedChallengeType == 'power_points',
              onSelected: () => setState(() => _selectedChallengeType = 'power_points'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLocationFilter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Location',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _locationController,
          decoration: const InputDecoration(
            hintText: 'Enter city or state...',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.location_on),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onSelected,
  }) {
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onSelected(),
      selectedColor: AppColors.accent.withOpacity(0.2),
      checkmarkColor: AppColors.accent,
      backgroundColor: Colors.grey[100],
      labelStyle: TextStyle(
        color: isSelected ? AppColors.accent : Colors.grey[700],
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }

  void _applyFilters() {
    final location = _locationController.text.trim();
    widget.onApplyFilters(
      _selectedStatus,
      _selectedChallengeType,
      location.isEmpty ? null : location,
    );
  }
}
