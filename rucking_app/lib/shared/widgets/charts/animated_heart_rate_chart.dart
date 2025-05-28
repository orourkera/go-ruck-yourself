// Standard library imports
import 'dart:math' as math;

// Flutter and third-party imports
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

// Project-specific imports
import 'package:rucking_app/features/ruck_session/domain/models/heart_rate_sample.dart';

/// An animated heart rate chart that smoothly renders heart rate data
class AnimatedHeartRateChart extends StatefulWidget {
  final List<HeartRateSample> heartRateSamples;
  final int? avgHeartRate;
  final int? maxHeartRate;
  final int? minHeartRate;
  final Color Function(BuildContext) getLadyModeColor;
  final Duration? totalDuration;

  const AnimatedHeartRateChart({
    super.key,
    required this.heartRateSamples,
    this.avgHeartRate,
    this.maxHeartRate,
    this.minHeartRate,
    required this.getLadyModeColor,
    this.totalDuration,
  });

  @override
  State<AnimatedHeartRateChart> createState() => _AnimatedHeartRateChartState();
}

class _AnimatedHeartRateChartState extends State<AnimatedHeartRateChart> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOutQuad);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => LineChart(_buildChartData(_animation.value)),
    );
  }

  LineChartData _buildChartData(double animationValue) {
    // The check in build() method should ideally prevent this from being called with empty samples,
    // but as a safeguard, return empty data if it somehow still is.
    if (widget.heartRateSamples.isEmpty) return LineChartData();

    final pointsToShow = (widget.heartRateSamples.length * animationValue).round().clamp(1, widget.heartRateSamples.length);
    final visibleSamples = widget.heartRateSamples.sublist(0, pointsToShow);
    final firstTimestamp = widget.heartRateSamples.first.timestamp.millisecondsSinceEpoch.toDouble();
        
    final spots = visibleSamples.map((sample) {
      final timeOffset = (sample.timestamp.millisecondsSinceEpoch - firstTimestamp) / (1000 * 60);
      return FlSpot(timeOffset, sample.bpm.toDouble());
    }).toList();
    
    // Always use the total session duration for x-axis if available
    // This ensures the graph always extends to the end time of the session
    final double totalMinutes = widget.totalDuration != null
        ? widget.totalDuration!.inMinutes.toDouble()
        : spots.isNotEmpty ? spots.last.x + 5 : 10.0;
        
    // Always use the total duration as the max X, not just the last data point
    // This ensures the graph extends to the full session duration even if heart rate data ends earlier
    final double safeMaxX = totalMinutes;
    // Ensure min and max Y values are proper doubles
    final double safeMinY = ((widget.minHeartRate != null) ? widget.minHeartRate!.toDouble() : 60.0) - 10.0;
    final double safeMaxY = ((widget.maxHeartRate != null) ? widget.maxHeartRate!.toDouble() : 180.0) + 10.0;

    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        horizontalInterval: 30,
        // Reduce vertical grid lines to match our new x-axis labels
        verticalInterval: safeMaxX > 5 ? (safeMaxX / 4).roundToDouble().clamp(5.0, 30.0) : 5,
        getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey.shade300, strokeWidth: 1),
        getDrawingVerticalLine: (_) => FlLine(color: Colors.grey.shade300, strokeWidth: 1),
      ),
      titlesData: FlTitlesData(
        show: true,
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 22,
            // Significantly reduce the number of x-axis labels by using a larger interval
            // For a typical session, show only start, 1/4, 1/2, 3/4, and end points
            interval: safeMaxX > 5 ? (safeMaxX / 4).roundToDouble().clamp(5.0, 30.0) : 5,
            getTitlesWidget: (value, meta) {
              // Only show labels at 0, 25%, 50%, 75% and 100% of the duration
              // Skip other labels to reduce clutter
              if (safeMaxX > 10) {
                final percentOfTotal = (value / safeMaxX);
                if (percentOfTotal < 0.05 || 
                    (percentOfTotal > 0.23 && percentOfTotal < 0.27) || 
                    (percentOfTotal > 0.48 && percentOfTotal < 0.52) || 
                    (percentOfTotal > 0.73 && percentOfTotal < 0.77) ||
                    percentOfTotal > 0.95) {
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    child: Text('${value.round()}m', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                  );
                }
                return const SizedBox.shrink();
              }
              
              return SideTitleWidget(
                axisSide: meta.axisSide,
                child: Text('${value.round()}m', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
              );
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            interval: 30,
            getTitlesWidget: (value, meta) => SideTitleWidget(
              axisSide: meta.axisSide,
              child: Text('${value.toInt()}', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
            ),
          ),
        ),
      ),
      borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey.shade300)),
      minX: 0,
      maxX: safeMaxX,
      minY: safeMinY,
      maxY: safeMaxY,
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          curveSmoothness: 0.25,
          color: widget.getLadyModeColor(context),
          barWidth: 3.5,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: true, color: widget.getLadyModeColor(context).withOpacity(0.2)),
        ),
      ],
      extraLinesData: ExtraLinesData(
        horizontalLines: [
          if (widget.maxHeartRate != null)
            HorizontalLine(
              y: widget.maxHeartRate!.toDouble(),
              color: Colors.red.withOpacity(0.6),
              strokeWidth: 1,
              dashArray: [5, 5],
              label: HorizontalLineLabel(
                show: true,
                alignment: Alignment.topRight,
                padding: const EdgeInsets.only(right: 5, bottom: 5),
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 10),
                labelResolver: (_) => 'Max: ${widget.maxHeartRate} bpm',
              ),
            ),
        ],
      ),
    );
  }
}
