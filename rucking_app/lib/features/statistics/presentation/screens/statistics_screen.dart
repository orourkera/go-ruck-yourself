import 'package:flutter/material.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/app_error_handler.dart';
import 'package:get_it/get_it.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/core/utils/measurement_utils.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

/// Screen for displaying statistics and analytics
class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({Key? key}) : super(key: key);

  @override
  _StatisticsScreenState createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> with SingleTickerProviderStateMixin, RouteAware {
  late TabController _tabController;
  final ApiClient _apiClient = GetIt.instance<ApiClient>();
  
  bool _isLoadingWeekly = true;
  bool _isLoadingMonthly = true;
  bool _isLoadingYearly = true;
  bool _hasLoadedData = false; // Track if data has been loaded
  
  Map<String, dynamic> _weeklyStats = {};
  Map<String, dynamic> _monthlyStats = {};
  Map<String, dynamic> _yearlyStats = {};
  
  @override
  void initState() {
    super.initState();
    AppLogger.info('[STATS_SCREEN] Initializing StatisticsScreen');
    _tabController = TabController(length: 3, vsync: this);
    AppLogger.info('[STATS_SCREEN] TabController created with 3 tabs');
    // Don't fetch data immediately - use lazy loading when user actually views this tab
  }
  
  @override
  void dispose() {
    AppLogger.info('[STATS_SCREEN] Disposing StatisticsScreen');
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      final routeObserver = Navigator.of(context).widget.observers.whereType<RouteObserver<PageRoute>>().firstOrNull;
      routeObserver?.unsubscribe(this);
    }
    _tabController.dispose();
    super.dispose();
  }
  
  /// Fetch statistics data from API
  Future<void> _fetchStatistics() async {
    AppLogger.info('[STATS_SCREEN] Starting to fetch statistics data');
    
    try {
      // Fetch weekly stats
      AppLogger.info('[STATS_SCREEN] Fetching weekly stats from /stats/weekly');
      final weeklyResponse = await _apiClient.get('/stats/weekly');
      AppLogger.info('[STATS_SCREEN] Weekly stats API response: ${weeklyResponse?.runtimeType}');
      
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
      
      if (mounted) {
        AppLogger.info('[STATS_SCREEN] Processing weekly stats - keys: ${weeklyStats.keys.toList()}');
        setState(() {
          _weeklyStats = weeklyStats;
          _isLoadingWeekly = false;
        });
        AppLogger.info('[STATS_SCREEN] Weekly stats loaded successfully');
      } else {
        AppLogger.warning('[STATS_SCREEN] Widget not mounted when weekly stats returned');
      }
      
      // Fetch monthly stats
      AppLogger.info('[STATS_SCREEN] Fetching monthly stats from /stats/monthly');
      final monthlyResponse = await _apiClient.get('/stats/monthly');
      AppLogger.info('[STATS_SCREEN] Monthly stats API response: ${monthlyResponse?.runtimeType}');
      
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
      if (mounted) {
        AppLogger.info('[STATS_SCREEN] Processing monthly stats - keys: ${monthlyStats.keys.toList()}');
        setState(() {
          _monthlyStats = monthlyStats;
          _isLoadingMonthly = false;
        });
        AppLogger.info('[STATS_SCREEN] Monthly stats loaded successfully');
      } else {
        AppLogger.warning('[STATS_SCREEN] Widget not mounted when monthly stats returned');
      }
      
      // Fetch yearly stats
      AppLogger.info('[STATS_SCREEN] Fetching yearly stats from /stats/yearly');
      final yearlyResponse = await _apiClient.get('/stats/yearly');
      AppLogger.info('[STATS_SCREEN] Yearly stats API response: ${yearlyResponse?.runtimeType}');
      
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
      if (mounted) {
        AppLogger.info('[STATS_SCREEN] Processing yearly stats - keys: ${yearlyStats.keys.toList()}');
        setState(() {
          _yearlyStats = yearlyStats;
          _isLoadingYearly = false;
        });
        AppLogger.info('[STATS_SCREEN] All statistics loaded successfully!');
      } else {
        AppLogger.warning('[STATS_SCREEN] Widget not mounted when yearly stats returned');
      }
      
    } catch (e) {
      AppLogger.error('[STATS_SCREEN] Error fetching statistics: $e');
      AppLogger.error('[STATS_SCREEN] Stack trace: ${StackTrace.current}');
      
      // Enhanced error handling with Sentry
      await AppErrorHandler.handleError(
        'statistics_fetch',
        e,
        context: {
          'screen': 'statistics',
        'current_tab': _tabController.index,
      },
      sendToBackend: true,
    );
    
    if (mounted) {
      AppLogger.error('[STATS_SCREEN] Setting error states - stopping all loading indicators');
      setState(() {
        _isLoadingWeekly = false;
        _isLoadingMonthly = false;
        _isLoadingYearly = false;
      });
      AppLogger.info('[STATS_SCREEN] Error states set successfully');
    } else {
      AppLogger.warning('[STATS_SCREEN] Widget not mounted when handling error');
    }
    }
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AppLogger.info('[STATS_SCREEN] didChangeDependencies called - hasLoadedData: $_hasLoadedData');
    
    // Only fetch data when the screen is actually visited and if not already loaded
    if (!_hasLoadedData) {
      AppLogger.info('[STATS_SCREEN] Data not loaded yet, fetching statistics...');
      _fetchStatistics();
      _hasLoadedData = true;
    } else {
      AppLogger.info('[STATS_SCREEN] Data already loaded, skipping fetch');
    }
  }

  @override
  void didPopNext() {
    AppLogger.info('[STATS_SCREEN] didPopNext called - returning to statistics screen');
    // Called when returning to this screen
    _fetchStatistics();
  }
  
  @override
  Widget build(BuildContext context) {
    AppLogger.info('[STATS_SCREEN] Building StatisticsScreen - loading states: weekly=$_isLoadingWeekly, monthly=$_isLoadingMonthly, yearly=$_isLoadingYearly');
    AppLogger.info('[STATS_SCREEN] Data states: weeklyEmpty=${_weeklyStats.isEmpty}, monthlyEmpty=${_monthlyStats.isEmpty}, yearlyEmpty=${_yearlyStats.isEmpty}');
    
    // Get user's metric preference
    bool preferMetric = true;
    final authState = context.read<AuthBloc>().state;
    if (authState is Authenticated) {
      preferMetric = authState.user.preferMetric;
    }
    
    return Scaffold(
      body: Column(
        children: [
          // Tab bar directly without AppBar
          Container(
            color: AppColors.primary,
            child: TabBar(
              controller: _tabController,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              indicatorColor: AppColors.accent,
              labelStyle: AppTextStyles.titleMedium.copyWith(fontWeight: FontWeight.bold),
              unselectedLabelStyle: AppTextStyles.titleMedium,
              tabs: const [
                Tab(text: 'WEEKLY'),
                Tab(text: 'MONTHLY'),
                Tab(text: 'YEARLY'),
              ],
            ),
          ),
          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Weekly tab
                _isLoadingWeekly
                    ? Builder(builder: (context) {
                        AppLogger.info('[STATS_SCREEN] Showing weekly loading indicator');
                        return const Center(child: CircularProgressIndicator());
                      })
                    : _weeklyStats.isEmpty
                        ? Builder(builder: (context) {
                            AppLogger.info('[STATS_SCREEN] Showing weekly empty state');
                            return const _EmptyStatsWidget(timeframe: 'weekly');
                          })
                        : Builder(builder: (context) {
                            AppLogger.info('[STATS_SCREEN] Showing weekly stats content');
                            return _StatsContentWidget(
                              stats: _weeklyStats,
                              timeframe: 'weekly',
                              preferMetric: preferMetric,
                            );
                          }),
                
                // Monthly tab
                _isLoadingMonthly
                    ? Builder(builder: (context) {
                        AppLogger.info('[STATS_SCREEN] Showing monthly loading indicator');
                        return const Center(child: CircularProgressIndicator());
                      })
                    : _monthlyStats.isEmpty
                        ? Builder(builder: (context) {
                            AppLogger.info('[STATS_SCREEN] Showing monthly empty state');
                            return const _EmptyStatsWidget(timeframe: 'monthly');
                          })
                        : Builder(builder: (context) {
                            AppLogger.info('[STATS_SCREEN] Showing monthly stats content');
                            return _StatsContentWidget(
                              stats: _monthlyStats,
                              timeframe: 'monthly',
                              preferMetric: preferMetric,
                            );
                          }),
                
                // Yearly tab
                _isLoadingYearly
                    ? Builder(builder: (context) {
                        AppLogger.info('[STATS_SCREEN] Showing yearly loading indicator');
                        return const Center(child: CircularProgressIndicator());
                      })
                    : _yearlyStats.isEmpty
                        ? Builder(builder: (context) {
                            AppLogger.info('[STATS_SCREEN] Showing yearly empty state');
                            return const _EmptyStatsWidget(timeframe: 'yearly');
                          })
                        : Builder(builder: (context) {
                            AppLogger.info('[STATS_SCREEN] Showing yearly stats content');
                            return _StatsContentWidget(
                              stats: _yearlyStats,
                              timeframe: 'yearly',
                              preferMetric: preferMetric,
                            );
                          }),
              ],
            ),
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
            style: AppTextStyles.titleMedium.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.textDarkSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Complete some rucks to see your statistics',
            style: AppTextStyles.bodyMedium.copyWith(
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
  
  static const List<String> _weekdayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
  ];
  
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
    final distanceValue = MeasurementUtils.formatDistance(totalDistanceKm, metric: preferMetric);
    
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
            style: AppTextStyles.titleMedium.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  context: context,
                  icon: Icons.directions_walk,
                  value: totalRucks.toString(),
                  label: 'Total Rucks',
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildSummaryCard(
                  context: context,
                  icon: Icons.straighten,
                  value: distanceValue,
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
                  context: context,
                  icon: Icons.local_fire_department,
                  value: totalCalories.toString(),
                  label: 'Calories Burned',
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildSummaryCard(
                  context: context,
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
            _buildPerformanceSection(context, stats['performance']),
          
          const SizedBox(height: 24),
          
          // Day breakdown (for weekly)
          if (timeframe == 'weekly' && stats['daily_breakdown'] != null)
            _buildDailyBreakdownSection(stats['daily_breakdown'], context),
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
          style: AppTextStyles.titleLarge,
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
          style: AppTextStyles.titleLarge,
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
          style: AppTextStyles.titleLarge,
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
    required BuildContext context,
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
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
            color: Theme.of(context).brightness == Brightness.dark ? Color(0xFF728C69) : color,
            size: 24,
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: AppTextStyles.headlineMedium.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).brightness == Brightness.dark ? Color(0xFF728C69) : AppColors.textDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: Theme.of(context).brightness == Brightness.dark ? Color(0xFF728C69) : AppColors.textDarkSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the performance metrics section
  Widget _buildPerformanceSection(BuildContext context, Map<String, dynamic> performance) {
    final avgPaceValue = performance['avg_pace_seconds_per_km'] ?? 0;
    final paceDisplay = avgPaceValue > 0 ? MeasurementUtils.formatPace(avgPaceValue.toDouble(), metric: preferMetric) : '--';
    
    final avgDistanceKm = (performance['avg_distance_km'] ?? 0.0).toDouble();
    final avgDistanceValue = MeasurementUtils.formatDistance(avgDistanceKm, metric: preferMetric);
    
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
          style: AppTextStyles.titleMedium.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).brightness == Brightness.dark ? Color(0xFF728C69) : AppColors.textDark,
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
                  context: context,
                  label: 'Average Pace',
                  value: paceDisplay,
                  icon: Icons.speed,
                ),
                const Divider(),
                _buildPerformanceItem(
                  context: context,
                  label: 'Average Distance',
                  value: avgDistanceValue,
                  icon: Icons.straighten,
                ),
                const Divider(),
                _buildPerformanceItem(
                  context: context,
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
    required BuildContext context,
    required String label,
    required String value,
    required IconData icon,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: Theme.of(context).brightness == Brightness.dark ? Color(0xFF728C69) : AppColors.primary,
      ),
      title: Text(
        label,
        style: AppTextStyles.bodyMedium,
      ),
      trailing: Text(
        value,
        style: AppTextStyles.titleMedium.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// Builds the daily breakdown section for weekly view
  Widget _buildDailyBreakdownSection(List<dynamic> dailyBreakdown, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Daily Breakdown',
          style: AppTextStyles.titleMedium.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).brightness == Brightness.dark ? Color(0xFF728C69) : AppColors.textDark,
          ),
        ),
        const SizedBox(height: 16),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: dailyBreakdown.length,
          itemBuilder: (context, index) {
            final day = dailyBreakdown[index];
            String dayName;
            if (day['day_name'] != null && day['day_name'].toString().isNotEmpty) {
              dayName = day['day_name'];
            } else if (day['date'] != null) {
              try {
                final parsed = DateTime.tryParse(day['date']);
                dayName = parsed != null
                    ? _StatsContentWidget._weekdayNames[parsed.weekday - 1]
                    : 'Unknown';
              } catch (_) {
                dayName = 'Unknown';
              }
            } else {
              dayName = 'Unknown';
            }
            
            final sessionsCount = day['sessions_count'] ?? 0;
            final distanceKm = (day['distance_km'] ?? 0.0).toDouble();
            
            final distanceValue = MeasurementUtils.formatDistance(distanceKm, metric: preferMetric);
            
            final isDark = Theme.of(context).brightness == Brightness.dark;
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
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Color(0xFF728C69) : AppColors.textDark,
                      ),
                    ),
                    Text(
                      distanceValue,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: isDark ? Color(0xFF728C69) : AppColors.textDark,
                      ),
                    ),
                    Text(
                      '$sessionsCount ${sessionsCount == 1 ? 'ruck' : 'rucks'}',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: isDark ? Color(0xFF728C69) : AppColors.textDarkSecondary,
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
          _buildSummarySection(context),
          
          const SizedBox(height: 24),
          
          // Daily breakdown
          _buildDailyBreakdownSection(context),
          
          const SizedBox(height: 24),
          
          // Performance metrics
          _buildPerformanceSection(context),
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
          style: AppTextStyles.titleLarge,
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
  Widget _buildSummarySection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Summary',
          style: AppTextStyles.titleMedium.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).brightness == Brightness.dark ? Color(0xFF728C69) : AppColors.textDark,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                context: context,
                icon: Icons.directions_walk,
                value: '3',
                label: 'Total Rucks',
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildSummaryCard(
                context: context,
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
                context: context,
                icon: Icons.local_fire_department,
                value: '1,680',
                label: 'Calories Burned',
                color: AppColors.accent,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildSummaryCard(
                context: context,
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
    required BuildContext context,
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
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
            color: Theme.of(context).brightness == Brightness.dark ? Color(0xFF728C69) : color,
            size: 24,
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: AppTextStyles.headlineMedium.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).brightness == Brightness.dark ? Color(0xFF728C69) : AppColors.textDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: Theme.of(context).brightness == Brightness.dark ? Color(0xFF728C69) : AppColors.textDarkSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the daily breakdown section
  Widget _buildDailyBreakdownSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Daily Breakdown',
          style: AppTextStyles.titleMedium.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).brightness == Brightness.dark ? Color(0xFF728C69) : AppColors.textDark,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          height: 200,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
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
              style: AppTextStyles.bodyMedium.copyWith(
                color: Theme.of(context).brightness == Brightness.dark ? Color(0xFF728C69) : AppColors.textDarkSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Builds the performance metrics section
  Widget _buildPerformanceSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Performance',
          style: AppTextStyles.titleMedium.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).brightness == Brightness.dark ? Color(0xFF728C69) : AppColors.textDark,
          ),
        ),
        const SizedBox(height: 16),
        _buildMetricCard(
          context: context,
          label: 'Average Pace',
          value: '14.2 min/km',
          change: '+0.5 from last week',
          isPositive: false,
        ),
        const SizedBox(height: 12),
        _buildMetricCard(
          context: context,
          label: 'Average Duration',
          value: '1h 04m',
          change: '+8m from last week',
          isPositive: true,
        ),
        const SizedBox(height: 12),
        _buildMetricCard(
          context: context,
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
    required BuildContext context,
    required String label,
    required String value,
    required String change,
    required bool isPositive,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
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
                style: AppTextStyles.bodyMedium,
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: AppTextStyles.titleMedium.copyWith(
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
                    ? (Theme.of(context).brightness == Brightness.dark ? Color(0xFF728C69) : AppColors.success)
                    : (Theme.of(context).brightness == Brightness.dark ? Color(0xFF728C69) : AppColors.error),
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                change,
                style: AppTextStyles.bodySmall.copyWith(
                  color: isPositive
                      ? (Theme.of(context).brightness == Brightness.dark ? Color(0xFF728C69) : AppColors.success)
                      : (Theme.of(context).brightness == Brightness.dark ? Color(0xFF728C69) : AppColors.error),
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