import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:rucking_app/features/ruck_session/domain/models/heart_rate_sample.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

class HeartRateGraph extends StatelessWidget {
  final List<HeartRateSample> samples;
  final double height;
  final bool showLabels;
  final bool showTooltips;

  const HeartRateGraph({
    Key? key,
    required this.samples,
    this.height = 150.0,
    this.showLabels = true,
    this.showTooltips = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (samples.isEmpty) {
      AppLogger.info('HeartRateGraph: No samples to display');
      return SizedBox(height: height);
    }
    AppLogger.info('HeartRateGraph: Building graph with ${samples.length} samples');
    return SizedBox(
      height: height,
      child: LineChart(_buildHeartRateChartData()),
    );
  }

  LineChartData _buildHeartRateChartData() {
    // Calculate min/max heart rates for Y-axis
    final List<int> heartRates = samples.map((s) => s.bpm).toList();
    final int minHr = heartRates.reduce((a, b) => a < b ? a : b);
    final int maxHr = heartRates.reduce((a, b) => a > b ? a : b);
    
    // Normalize timestamps to start from 0 for better x-axis display
    final firstTimestamp = samples.isNotEmpty 
        ? samples.first.timestamp.millisecondsSinceEpoch 
        : 0;
    
    // Create chart spots
    final spots = samples.map((sample) {
      // Convert to minutes from start for x-axis
      final minutesFromStart = (sample.timestamp.millisecondsSinceEpoch - firstTimestamp) / (1000 * 60);
      return FlSpot(minutesFromStart, sample.bpm.toDouble());
    }).toList();
    
    // Define gradient colors for the line and fill
    final gradientColors = [
      AppColors.error,            // Red for heart rate
      AppColors.error.withOpacity(0.7),
      AppColors.error.withOpacity(0.3),
    ];
    
    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: 20,  // HR interval of 20 bpm
        getDrawingHorizontalLine: (value) {
          return FlLine(
            color: Colors.grey.withOpacity(0.15),
            strokeWidth: 1,
            dashArray: [5, 5],
          );
        },
      ),
      titlesData: FlTitlesData(
        show: showLabels,
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: showLabels,
            reservedSize: 22,
            interval: 5,  // Every 5 minutes
            getTitlesWidget: (value, meta) {
              if (value % 5 != 0) return const SizedBox.shrink();
              return Text(
                '${value.toInt()}m',
                style: TextStyle(fontSize: 9, color: Colors.grey[600]),
              );
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: showLabels,
            reservedSize: 30,
            interval: 20, // Show HR in increments of 20
            getTitlesWidget: (value, meta) {
              if (value % 20 != 0) return const SizedBox.shrink();
              return Text(
                '${value.toInt()}',
                style: TextStyle(fontSize: 9, color: Colors.grey[600]),
              );
            },
          ),
        ),
      ),
      borderData: FlBorderData(
        show: true,
        border: Border(
          bottom: BorderSide(color: Colors.grey[300]!, width: 1),
          left: BorderSide(color: Colors.grey[300]!, width: 1),
        ),
      ),
      lineTouchData: LineTouchData(
        enabled: showTooltips,
        touchTooltipData: LineTouchTooltipData(
          tooltipBgColor: AppColors.slateGrey.withOpacity(0.8),
          getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
            return touchedBarSpots.map((barSpot) {
              final minutes = barSpot.x.toInt();
              final seconds = ((barSpot.x - minutes) * 60).toInt();
              return LineTooltipItem(
                '${barSpot.y.toInt()} bpm\n$minutes:${seconds.toString().padLeft(2, '0')}',
                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              );
            }).toList();
          },
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: AppColors.error,
          gradient: LinearGradient(
            colors: [gradientColors[0], gradientColors[1]],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          barWidth: 4,
          isStrokeCapRound: true,
          dotData: FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              colors: gradientColors.map((color) => color.withOpacity(0.3)).toList(),
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ],
      minY: (minHr - 10).toDouble(),  // Add some padding below
      maxY: (maxHr + 10).toDouble(),  // Add some padding above
    );
  }
}
