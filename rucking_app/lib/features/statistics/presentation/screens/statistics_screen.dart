import 'package:flutter/material.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:get_it/get_it.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';

/// Screen for displaying statistics and analytics
class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({Key? key}) : super(key: key);

  @override
  _StatisticsScreenState createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ApiClient _apiClient = GetIt.instance<ApiClient>();
  
  bool _isLoadingWeekly = true;
  bool _isLoadingMonthly = true;
  bool _isLoadingYearly = true;
  
  Map<String, dynamic> _weeklyStats = {};
  Map<String, dynamic> _monthlyStats = {};
  Map<String, dynamic> _yearlyStats = {};
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchStatistics();
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  /// Fetch statistics data from API
  Future<void> _fetchStatistics() async {
    try {
      // Fetch weekly stats
      final weeklyResponse = await _apiClient.get('/statistics/weekly');
      
      // Process weekly stats
      Map<String, dynamic> weeklyStats = {};
      if (weeklyResponse is Map) {
        if (weeklyResponse.containsKey('data')) {
          weeklyStats = weeklyResponse['data'] is Map ? 
              Map<String, dynamic>.from(weeklyResponse['data']) : {};
        } else {
          weeklyStats = Map<String, dynamic>.from(weeklyResponse);
        }
      }
      
      setState(() {
        _weeklyStats = weeklyStats;
        _isLoadingWeekly = false;
      });
      
      // Fetch monthly stats
      final monthlyResponse = await _apiClient.get('/statistics/monthly');
      
      // Process monthly stats
      Map<String, dynamic> monthlyStats = {};
      if (monthlyResponse is Map) {
        if (monthlyResponse.containsKey('data')) {
          monthlyStats = monthlyResponse['data'] is Map ? 
              Map<String, dynamic>.from(monthlyResponse['data']) : {};
        } else {
          monthlyStats = Map<String, dynamic>.from(monthlyResponse);
        }
      }
      
      // Update state with monthly stats
      setState(() {
        _monthlyStats = monthlyStats;
        _isLoadingMonthly = false;
      });
      
      // Fetch yearly stats
      final yearlyResponse = await _apiClient.get('/statistics/yearly');
      
      // Process yearly stats
      Map<String, dynamic> yearlyStats = {};
      if (yearlyResponse is Map) {
        if (yearlyResponse.containsKey('data')) {
          yearlyStats = yearlyResponse['data'] is Map ? 
              Map<String, dynamic>.from(yearlyResponse['data']) : {};
        } else {
          yearlyStats = Map<String, dynamic>.from(yearlyResponse);
        }
      }
      
      // Update state with yearly stats
      setState(() {
        _yearlyStats = yearlyStats;
        _isLoadingYearly = false;
      });
      
    } catch (e) {
      debugPrint('Error fetching statistics: $e');
      setState(() {
        _isLoadingWeekly = false;
        _isLoadingMonthly = false;
        _isLoadingYearly = false;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    // Get user's metric preference
    bool preferMetric = true;
    final authState = context.read<AuthBloc>().state;
    if (authState is Authenticated) {
      preferMetric = authState.user.preferMetric;
    }
    
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
        children: [
          // Weekly tab
          _isLoadingWeekly
              ? const Center(child: CircularProgressIndicator())
              : _weeklyStats.isEmpty
                  ? const _EmptyStatsWidget(timeframe: 'weekly')
                  : _StatsContentWidget(
                      stats: _weeklyStats,
                      timeframe: 'weekly',
                      preferMetric: preferMetric,
                    ),
          
          // Monthly tab
          _isLoadingMonthly
              ? const Center(child: CircularProgressIndicator())
              : _monthlyStats.isEmpty
                  ? const _EmptyStatsWidget(timeframe: 'monthly')
                  : _StatsContentWidget(
                      stats: _monthlyStats,
                      timeframe: 'monthly',
                      preferMetric: preferMetric,
                    ),
          
          // Yearly tab
          _isLoadingYearly
              ? const Center(child: CircularProgressIndicator())
              : _yearlyStats.isEmpty
                  ? const _EmptyStatsWidget(timeframe: 'yearly')
                  : _StatsContentWidget(
                      stats: _yearlyStats,
                      timeframe: 'yearly',
                      preferMetric: preferMetric,
                    ),
        ],
      ),
    );
  }
}

/// Empty state widget for statistics
class _EmptyStatsWidget extends StatelessWidget {
  final String timeframe;
  
  const _EmptyStatsWidget({Key? key, required this.timeframe}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.bar_chart_outlined,
            size: 64,
            color: AppColors.grey,
          ),
          const SizedBox(height: 16),
          Text(
            'No ${timeframe} stats yet',
            style: AppTextStyles.subtitle1.copyWith(
              color: AppColors.textDarkSecondary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Complete some rucks to see your statistics',
            style: AppTextStyles.body2.copyWith(
              color: AppColors.textDarkSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Widget for displaying statistics content
class _StatsContentWidget extends StatelessWidget {
  final Map<String, dynamic> stats;
  final String timeframe;
  final bool preferMetric;
  
  const _StatsContentWidget({
    Key? key, 
    required this.stats, 
    required this.timeframe,
    required this.preferMetric,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Extract relevant stats
    final totalRucks = stats['total_sessions'] ?? 0;
    final totalDistanceKm = (stats['total_distance_km'] ?? 0.0).toDouble();
    final totalCalories = stats['total_calories'] ?? 0;
    final totalDurationSecs = stats['total_duration_seconds'] ?? 0;
    
    // Format stats
    final distanceValue = preferMetric
        ? totalDistanceKm.toStringAsFixed(1)
        : (totalDistanceKm * 0.621371).toStringAsFixed(1);
    final distanceUnit = preferMetric ? 'km' : 'mi';
    
    // Format duration
    final duration = Duration(seconds: totalDurationSecs);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final durationText = '${hours}h ${minutes}m';
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Period selector
          timeframe == 'weekly'
              ? _buildDateSelector(stats['date_range'] ?? 'This Week')
              : timeframe == 'monthly'
                  ? _buildMonthSelector(stats['date_range'] ?? 'This Month')
                  : _buildYearSelector(stats['date_range'] ?? 'This Year'),
          
          const SizedBox(height: 24),
          
          // Summary cards
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
                  value: totalRucks.toString(),
                  label: 'Total Rucks',
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildSummaryCard(
                  icon: Icons.straighten,
                  value: '$distanceValue $distanceUnit',
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
                  value: totalCalories.toString(),
                  label: 'Calories Burned',
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildSummaryCard(
                  icon: Icons.timer,
                  value: durationText,
                  label: 'Total Time',
                  color: AppColors.info,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Performance metrics
          if (stats['performance'] != null)
            _buildPerformanceSection(stats['performance']),
          
          const SizedBox(height: 24),
          
          // Day breakdown (for weekly)
          if (timeframe == 'weekly' && stats['daily_breakdown'] != null)
            _buildDailyBreakdownSection(stats['daily_breakdown']),
        ],
      ),
    );
  }

  /// Builds the date selector widget for weekly view
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

  /// Builds the month selector widget
  Widget _buildMonthSelector(String dateRange) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () {
            // Navigate to previous month
          },
        ),
        Text(
          dateRange,
          style: AppTextStyles.headline6,
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: () {
            // Navigate to next month
          },
        ),
      ],
    );
  }

  /// Builds the year selector widget
  Widget _buildYearSelector(String dateRange) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () {
            // Navigate to previous year
          },
        ),
        Text(
          dateRange,
          style: AppTextStyles.headline6,
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: () {
            // Navigate to next year
          },
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

  /// Builds the performance metrics section
  Widget _buildPerformanceSection(Map<String, dynamic> performance) {
    final avgPaceValue = performance['avg_pace_seconds_per_km'] ?? 0;
    final avgPaceMinutes = (avgPaceValue / 60).floor();
    final avgPaceSeconds = (avgPaceValue % 60).round();
    final formattedPace = preferMetric
        ? '${avgPaceMinutes}:${avgPaceSeconds.toString().padLeft(2, '0')} /km'
        : '${avgPaceMinutes}:${avgPaceSeconds.toString().padLeft(2, '0')} /mi';
        
    final avgDistanceKm = (performance['avg_distance_km'] ?? 0.0).toDouble();
    final avgDistanceValue = preferMetric
        ? avgDistanceKm.toStringAsFixed(1)
        : (avgDistanceKm * 0.621371).toStringAsFixed(1);
    final distanceUnit = preferMetric ? 'km' : 'mi';
    
    final avgDurationSecs = performance['avg_duration_seconds'] ?? 0;
    final avgDuration = Duration(seconds: avgDurationSecs);
    final hours = avgDuration.inHours;
    final minutes = avgDuration.inMinutes % 60;
    final avgDurationText = hours > 0
        ? '${hours}h ${minutes}m'
        : '${minutes}m';
    
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
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildPerformanceItem(
                  label: 'Average Pace',
                  value: formattedPace,
                  icon: Icons.speed,
                ),
                const Divider(),
                _buildPerformanceItem(
                  label: 'Average Distance',
                  value: '$avgDistanceValue $distanceUnit',
                  icon: Icons.straighten,
                ),
                const Divider(),
                _buildPerformanceItem(
                  label: 'Average Duration',
                  value: avgDurationText,
                  icon: Icons.timer,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Builds a performance item
  Widget _buildPerformanceItem({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: AppColors.primary,
      ),
      title: Text(
        label,
        style: AppTextStyles.body2,
      ),
      trailing: Text(
        value,
        style: AppTextStyles.subtitle1.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// Builds the daily breakdown section for weekly view
  Widget _buildDailyBreakdownSection(List<dynamic> dailyBreakdown) {
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
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: dailyBreakdown.length,
          itemBuilder: (context, index) {
            final day = dailyBreakdown[index];
            final dayName = day['day_name'] ?? 'Unknown';
            final sessionsCount = day['sessions_count'] ?? 0;
            final distanceKm = (day['distance_km'] ?? 0.0).toDouble();
            
            final distanceValue = preferMetric
                ? distanceKm.toStringAsFixed(1)
                : (distanceKm * 0.621371).toStringAsFixed(1);
            final distanceUnit = preferMetric ? 'km' : 'mi';
            
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      dayName,
                      style: AppTextStyles.body1.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '$distanceValue $distanceUnit',
                      style: AppTextStyles.body1,
                    ),
                    Text(
                      '$sessionsCount ${sessionsCount == 1 ? 'ruck' : 'rucks'}',
                      style: AppTextStyles.body2.copyWith(
                        color: AppColors.textDarkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
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