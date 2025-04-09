import 'package:flutter/material.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

/// Screen for displaying statistics and analytics
class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({Key? key}) : super(key: key);

  @override
  _StatisticsScreenState createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistics'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'WEEKLY'),
            Tab(text: 'MONTHLY'),
            Tab(text: 'YEARLY'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _WeeklyStatsTab(),
          _MonthlyStatsTab(),
          _YearlyStatsTab(),
        ],
      ),
    );
  }
}

/// Weekly statistics tab
class _WeeklyStatsTab extends StatelessWidget {
  const _WeeklyStatsTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date range selector
          _buildDateSelector('Apr 7 - Apr 13, 2025'),
          
          const SizedBox(height: 24),
          
          // Summary cards
          _buildSummarySection(),
          
          const SizedBox(height: 24),
          
          // Daily breakdown
          _buildDailyBreakdownSection(),
          
          const SizedBox(height: 24),
          
          // Performance metrics
          _buildPerformanceSection(),
        ],
      ),
    );
  }

  /// Builds the date selector widget
  Widget _buildDateSelector(String dateRange) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () {
            // Navigate to previous week
          },
        ),
        Text(
          dateRange,
          style: AppTextStyles.headline6,
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: () {
            // Navigate to next week
          },
        ),
      ],
    );
  }

  /// Builds the summary cards section
  Widget _buildSummarySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Summary',
          style: AppTextStyles.subtitle1.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                icon: Icons.directions_walk,
                value: '3',
                label: 'Total Rucks',
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildSummaryCard(
                icon: Icons.straighten,
                value: '13.5 km',
                label: 'Total Distance',
                color: AppColors.secondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                icon: Icons.local_fire_department,
                value: '1,680',
                label: 'Calories Burned',
                color: AppColors.accent,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildSummaryCard(
                icon: Icons.timer,
                value: '3:12:00',
                label: 'Total Time',
                color: AppColors.info,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Builds a summary card
  Widget _buildSummaryCard({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: color,
            size: 24,
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: AppTextStyles.headline5.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textDarkSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the daily breakdown section
  Widget _buildDailyBreakdownSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Daily Breakdown',
          style: AppTextStyles.subtitle1.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          height: 200,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          // Placeholder for chart
          child: Center(
            child: Text(
              'Bar Chart: Daily Distance',
              style: AppTextStyles.body2.copyWith(
                color: AppColors.textDarkSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Builds the performance metrics section
  Widget _buildPerformanceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Performance',
          style: AppTextStyles.subtitle1.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        _buildMetricCard(
          label: 'Average Pace',
          value: '14.2 min/km',
          change: '+0.5 from last week',
          isPositive: false,
        ),
        const SizedBox(height: 12),
        _buildMetricCard(
          label: 'Average Duration',
          value: '1h 04m',
          change: '+8m from last week',
          isPositive: true,
        ),
        const SizedBox(height: 12),
        _buildMetricCard(
          label: 'Average Distance',
          value: '4.5 km',
          change: '+0.3 km from last week',
          isPositive: true,
        ),
      ],
    );
  }

  /// Builds a performance metric card
  Widget _buildMetricCard({
    required String label,
    required String value,
    required String change,
    required bool isPositive,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTextStyles.subtitle2.copyWith(
                  color: AppColors.textDarkSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: AppTextStyles.subtitle1.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Icon(
                isPositive
                    ? Icons.arrow_upward
                    : Icons.arrow_downward,
                color: isPositive
                    ? AppColors.success
                    : AppColors.error,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                change,
                style: AppTextStyles.caption.copyWith(
                  color: isPositive
                      ? AppColors.success
                      : AppColors.error,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Monthly statistics tab (placeholder)
class _MonthlyStatsTab extends StatelessWidget {
  const _MonthlyStatsTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Monthly Statistics'),
    );
  }
}

/// Yearly statistics tab (placeholder)
class _YearlyStatsTab extends StatelessWidget {
  const _YearlyStatsTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Yearly Statistics'),
    );
  }
} 