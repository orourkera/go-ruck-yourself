import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/core/utils/measurement_utils.dart';

enum StatsMetric {
  distance,
  time,
  calories,
  powerPoints,
}

class RuckStatsChart extends StatefulWidget {
  final List<dynamic> timeSeriesData;
  final String timeframe;
  final bool preferMetric;

  const RuckStatsChart({
    super.key,
    required this.timeSeriesData,
    required this.timeframe,
    required this.preferMetric,
  });

  @override
  State<RuckStatsChart> createState() => _RuckStatsChartState();
}

class _RuckStatsChartState extends State<RuckStatsChart> {
  StatsMetric _selectedMetric = StatsMetric.distance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: isDark 
                ? Colors.black.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          _buildMetricSelector(),
          const SizedBox(height: 20),
          _buildChart(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    String title = 'Activity Overview';
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: AppTextStyles.titleMedium.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Icon(
          Icons.bar_chart,
          color: AppColors.primary,
          size: 24,
        ),
      ],
    );
  }

  Widget _buildMetricSelector() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: StatsMetric.values.map((metric) {
          final isSelected = _selectedMetric == metric;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedMetric = metric;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected 
                      ? AppColors.primary 
                      : isDark 
                          ? Colors.grey[800] 
                          : Colors.grey[100],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected 
                        ? AppColors.primary 
                        : isDark 
                            ? Colors.grey[600]! 
                            : Colors.grey[300]!,
                  ),
                ),
                child: Text(
                  _getMetricDisplayName(metric),
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: isSelected 
                        ? Colors.white 
                        : isDark 
                            ? Colors.grey[300] 
                            : AppColors.textDarkSecondary,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildChart() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    if (widget.timeSeriesData.isEmpty) {
      return SizedBox(
        height: 200,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.bar_chart_outlined,
                size: 48,
                color: isDark ? Colors.grey[400] : AppColors.grey,
              ),
              const SizedBox(height: 8),
              Text(
                'No data available',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: isDark ? Colors.grey[400] : AppColors.textDarkSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: _getMaxY(),
          barTouchData: _buildBarTouchData(),
          titlesData: _buildTitlesData(),
          borderData: FlBorderData(show: false),
          barGroups: _buildBarGroups(),
          gridData: FlGridData(
            show: true,
            horizontalInterval: _getMaxY() / 4,
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
                strokeWidth: 1,
              );
            },
            drawVerticalLine: false,
          ),
        ),
      ),
    );
  }

  BarTouchData _buildBarTouchData() {
    return BarTouchData(
      touchTooltipData: BarTouchTooltipData(
        tooltipBgColor: AppColors.primary.withValues(alpha: 0.9),
        tooltipRoundedRadius: 8,
        getTooltipItem: (group, groupIndex, rod, rodIndex) {
          if (groupIndex >= widget.timeSeriesData.length) return null;
          
          final data = widget.timeSeriesData[groupIndex];
          final period = data['period'] ?? 'Unknown';
          final value = _getMetricValue(data);
          final formattedValue = _formatMetricValue(value);
          
          return BarTooltipItem(
            '$period\n$formattedValue',
            AppTextStyles.bodySmall.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          );
        },
      ),
    );
  }

  FlTitlesData _buildTitlesData() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return FlTitlesData(
      show: true,
      rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          getTitlesWidget: (double value, TitleMeta meta) {
            final index = value.toInt();
            if (index < 0 || index >= widget.timeSeriesData.length) {
              return const SizedBox.shrink();
            }
            
            final data = widget.timeSeriesData[index];
            String period = data['period'] ?? '';
            
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                period,
                style: AppTextStyles.bodySmall.copyWith(
                  color: isDark ? Colors.grey[400] : AppColors.textDarkSecondary,
                  fontSize: 10,
                ),
              ),
            );
          },
        ),
      ),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 40,
          getTitlesWidget: (double value, TitleMeta meta) {
            return Text(
              _formatAxisValue(value),
              style: AppTextStyles.bodySmall.copyWith(
                color: isDark ? Colors.grey[400] : AppColors.textDarkSecondary,
                fontSize: 10,
              ),
            );
          },
        ),
      ),
    );
  }

  List<BarChartGroupData> _buildBarGroups() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return widget.timeSeriesData.asMap().entries.map((entry) {
      final index = entry.key;
      final data = entry.value;
      final value = _getMetricValue(data);
      
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: value,
            color: _getMetricColor(),
            width: _getBarWidth(),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(4),
            ),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: _getMaxY(),
              color: isDark ? Colors.grey[800] : Colors.grey[100],
            ),
          ),
        ],
      );
    }).toList();
  }

  double _getMetricValue(dynamic data) {
    switch (_selectedMetric) {
      case StatsMetric.distance:
        return (data['distance_km'] ?? 0.0).toDouble();
      case StatsMetric.time:
        return ((data['duration_seconds'] ?? 0) / 3600).toDouble(); // Convert to hours
      case StatsMetric.calories:
        return (data['calories'] ?? 0).toDouble();
      case StatsMetric.powerPoints:
        return (data['power_points'] ?? 0).toDouble();
    }
  }

  double _getMaxY() {
    if (widget.timeSeriesData.isEmpty) return 100;
    
    double maxValue = 0;
    for (final data in widget.timeSeriesData) {
      final value = _getMetricValue(data);
      if (value > maxValue) maxValue = value;
    }
    
    // Add 20% padding to the top
    return maxValue * 1.2;
  }

  Color _getMetricColor() {
    switch (_selectedMetric) {
      case StatsMetric.distance:
        return AppColors.secondary;
      case StatsMetric.time:
        return AppColors.info;
      case StatsMetric.calories:
        return AppColors.accent;
      case StatsMetric.powerPoints:
        return AppColors.primary;
    }
  }

  double _getBarWidth() {
    final dataLength = widget.timeSeriesData.length;
    if (dataLength <= 7) return 16;
    if (dataLength <= 12) return 12;
    return 8;
  }

  String _getMetricDisplayName(StatsMetric metric) {
    switch (metric) {
      case StatsMetric.distance:
        return 'Distance';
      case StatsMetric.time:
        return 'Time';
      case StatsMetric.calories:
        return 'Calories';
      case StatsMetric.powerPoints:
        return 'Power Points';
    }
  }

  String _formatMetricValue(double value) {
    switch (_selectedMetric) {
      case StatsMetric.distance:
        return MeasurementUtils.formatDistance(value, metric: widget.preferMetric);
      case StatsMetric.time:
        final hours = value.floor();
        final minutes = ((value - hours) * 60).round();
        return '${hours}h ${minutes}m';
      case StatsMetric.calories:
        return '${value.round()} cal';
      case StatsMetric.powerPoints:
        return '${value.round()} pts';
    }
  }

  String _formatAxisValue(double value) {
    switch (_selectedMetric) {
      case StatsMetric.distance:
        if (value < 1) return '${(value * 10).round() / 10}';
        return value.round().toString();
      case StatsMetric.time:
        return '${value.round()}h';
      case StatsMetric.calories:
        if (value >= 1000) return '${(value / 1000).round()}k';
        return value.round().toString();
      case StatsMetric.powerPoints:
        if (value >= 1000) return '${(value / 1000).round()}k';
        return value.round().toString();
    }
  }
}