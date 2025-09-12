import 'package:flutter/material.dart';

/// Well butter my grits! This header shows all them column titles with sorting
class LeaderboardHeader extends StatelessWidget {
  final String sortBy;
  final bool ascending;
  final Function(String, bool) onSort;
  final VoidCallback onPowerPointsTap;
  final ScrollController? horizontalScrollController;

  const LeaderboardHeader({
    Key? key,
    required this.sortBy,
    required this.ascending,
    required this.onSort,
    required this.onPowerPointsTap,
    this.horizontalScrollController,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          bottom: BorderSide(
            color: Colors.grey.withOpacity(0.2),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // FIXED COLUMNS
          // Rank column
          SizedBox(
            width: 40,
            child: Text('#',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold, color: Colors.grey.shade600),
                textAlign: TextAlign.center),
          ),

          // User column (not sortable)
          SizedBox(
            width: 150,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('USER',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.grey.shade600)),
            ),
          ),

          // SCROLLABLE STATS
          Flexible(
            child: SingleChildScrollView(
              controller: horizontalScrollController,
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: Row(
                children: [
                  _buildPowerPointsColumn(context),
                  _buildSortableColumn(context, 'RUCKS', 'totalRucks',
                      width: 80),
                  _buildSortableColumn(context, 'DISTANCE', 'distanceKm',
                      width: 100),
                  _buildSortableColumn(
                      context, 'ELEVATION', 'elevationGainMeters',
                      width: 100),
                  _buildSortableColumn(context, 'CALORIES', 'caloriesBurned',
                      width: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build a sortable column header prettier than a Sunday hat
  Widget _buildSortableColumn(
    BuildContext context,
    String title,
    String field, {
    double width = 60.0,
  }) {
    final isActive = sortBy == field;
    final textColor =
        isActive ? Theme.of(context).primaryColor : Colors.grey.shade600;

    return SizedBox(
      width: width,
      child: GestureDetector(
        onTap: () {
          // If same column, toggle direction; otherwise, default to descending
          final newAscending = isActive ? !ascending : false;
          onSort(field, newAscending);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: textColor,
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              _buildSortIcon(context, isActive, ascending),
            ],
          ),
        ),
      ),
    );
  }

  /// Build the special Power Points column with tap to explain
  Widget _buildPowerPointsColumn(BuildContext context) {
    final isActive = sortBy == 'powerPoints';
    final textColor =
        isActive ? Theme.of(context).primaryColor : Colors.grey.shade600;

    return SizedBox(
      width: 100,
      child: GestureDetector(
        onTap: () {
          // If same column, toggle direction; otherwise, default to descending
          final newAscending = isActive ? !ascending : false;
          onSort('powerPoints', newAscending);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Main title with sort
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      'POWER',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: textColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 4),
                  _buildSortIcon(context, isActive, ascending),
                ],
              ),

              // Second line with explanation tap
              GestureDetector(
                onTap: onPowerPointsTap,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: Colors.amber.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'POINTS',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                          color: Colors.amber.shade700,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.help_outline,
                        size: 12,
                        color: Colors.amber.shade700,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build sort icon that shows direction
  Widget _buildSortIcon(BuildContext context, bool isActive, bool ascending) {
    if (!isActive) {
      return Icon(
        Icons.unfold_more,
        size: 16,
        color: Colors.grey.shade400,
      );
    }

    return Icon(
      ascending ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
      size: 16,
      color: Theme.of(context).primaryColor,
    );
  }
}
