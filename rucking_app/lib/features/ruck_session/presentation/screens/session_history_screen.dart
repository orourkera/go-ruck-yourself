import 'package:flutter/material.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

/// Screen for viewing ruck session history
class SessionHistoryScreen extends StatelessWidget {
  const SessionHistoryScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Sample data for history
    final sessions = [
      _SessionData(
        date: 'April 5, 2025',
        distance: 5.2,
        duration: '1h 10m',
        calories: 650,
      ),
      _SessionData(
        date: 'April 2, 2025',
        distance: 4.8,
        duration: '1h 05m',
        calories: 610,
      ),
      _SessionData(
        date: 'March 29, 2025',
        distance: 6.5,
        duration: '1h 30m',
        calories: 820,
      ),
      _SessionData(
        date: 'March 25, 2025',
        distance: 3.8,
        duration: '0h 50m',
        calories: 480,
      ),
      _SessionData(
        date: 'March 22, 2025',
        distance: 7.2,
        duration: '1h 45m',
        calories: 950,
      ),
      _SessionData(
        date: 'March 18, 2025',
        distance: 5.5,
        duration: '1h 15m',
        calories: 710,
      ),
      _SessionData(
        date: 'March 15, 2025',
        distance: 4.2,
        duration: '0h 55m',
        calories: 520,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session History'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () {
              // TODO: Implement filters
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('All', true),
                  _buildFilterChip('This Week', false),
                  _buildFilterChip('This Month', false),
                  _buildFilterChip('Last Month', false),
                  _buildFilterChip('Custom', false),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          
          // Sessions list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: sessions.length,
              itemBuilder: (context, index) {
                return _buildSessionCard(sessions[index]);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Builds a filter chip for the filter bar
  Widget _buildFilterChip(String label, bool isSelected) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (bool selected) {
          // TODO: Implement filter selection
        },
        selectedColor: AppColors.primary.withOpacity(0.2),
        checkmarkColor: AppColors.primary,
        labelStyle: AppTextStyles.caption.copyWith(
          color: isSelected ? AppColors.primary : AppColors.textDark,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  /// Builds a card for displaying a session
  Widget _buildSessionCard(_SessionData session) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () {
          // TODO: Navigate to session details
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with date and options
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    session.date,
                    style: AppTextStyles.subtitle1.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (String value) {
                      // TODO: Handle menu item selection
                    },
                    itemBuilder: (BuildContext context) => [
                      const PopupMenuItem<String>(
                        value: 'details',
                        child: Text('View Details'),
                      ),
                      const PopupMenuItem<String>(
                        value: 'share',
                        child: Text('Share'),
                      ),
                      const PopupMenuItem<String>(
                        value: 'delete',
                        child: Text('Delete'),
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 8),
              
              // Stats grid
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatColumn(
                    Icons.straighten,
                    '${session.distance} km',
                    'Distance',
                  ),
                  _buildStatColumn(
                    Icons.timer,
                    session.duration,
                    'Duration',
                  ),
                  _buildStatColumn(
                    Icons.local_fire_department,
                    '${session.calories}',
                    'Calories',
                  ),
                  _buildStatColumn(
                    Icons.speed,
                    '${(session.distance / (session.getDurationInHours())).toStringAsFixed(1)} km/h',
                    'Avg Speed',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds a stat column for the session card
  Widget _buildStatColumn(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(
          icon,
          color: AppColors.primary,
          size: 24,
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: AppTextStyles.subtitle2.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: AppColors.textDarkSecondary,
          ),
        ),
      ],
    );
  }
}

/// Helper class for session data
class _SessionData {
  final String date;
  final double distance;
  final String duration;
  final int calories;

  _SessionData({
    required this.date,
    required this.distance,
    required this.duration,
    required this.calories,
  });

  /// Converts duration string to hours (approximation for display)
  double getDurationInHours() {
    // Parse "1h 30m" format
    final parts = duration.split(' ');
    final hours = int.parse(parts[0].replaceAll('h', ''));
    final minutes = int.parse(parts[1].replaceAll('m', ''));
    return hours + (minutes / 60);
  }
} 