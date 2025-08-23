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
  final List<({int min, int max, Color color, String name})>? zones;

  const AnimatedHeartRateChart({
    super.key,
    required this.heartRateSamples,
    this.avgHeartRate,
    this.maxHeartRate,
    this.minHeartRate,
    required this.getLadyModeColor,
    this.totalDuration,
    this.zones,
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
    final lastTimestamp = widget.heartRateSamples.last.timestamp.millisecondsSinceEpoch.toDouble();
        
    final spots = visibleSamples.map((sample) {
      final timeOffset = (sample.timestamp.millisecondsSinceEpoch - firstTimestamp) / (1000 * 60);
      return FlSpot(timeOffset, sample.bpm.toDouble());
    }).toList();
    
    // Calculate the actual time range of heart rate data
    final double actualDataRangeMinutes = (lastTimestamp - firstTimestamp) / (1000 * 60);
    
    // Use the actual heart rate data range for x-axis with small buffer
    final double safeMaxX = actualDataRangeMinutes + 2.0;
        
    // Ensure min and max Y values are proper doubles
    final double safeMinY = ((widget.minHeartRate != null) ? widget.minHeartRate!.toDouble() : 60.0) - 10.0;
    final double safeMaxY = ((widget.maxHeartRate != null) ? widget.maxHeartRate!.toDouble() : 180.0) + 10.0;

    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        horizontalInterval: 30,
        // Set appropriate vertical grid intervals based on session duration
        verticalInterval: safeMaxX > 30 ? 10.0 : safeMaxX > 15 ? 5.0 : 2.5,
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
            // Set appropriate intervals based on session duration
            interval: safeMaxX > 30 ? 10.0 : safeMaxX > 15 ? 5.0 : 2.5,
            getTitlesWidget: (value, meta) {
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
                alignment: Alignment.topLeft,
                padding: const EdgeInsets.only(left: 10, bottom: 5),
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 10),
                labelResolver: (_) => 'Max: ${widget.maxHeartRate} bpm',
              ),
            ),
          // Zone boundary lines and labels
          if (widget.zones != null)
            ...widget.zones!.expand((z) => [
              HorizontalLine(y: z.min.toDouble(), color: z.color.withOpacity(0.12), strokeWidth: 2),
              HorizontalLine(
                y: z.max.toDouble(),
                color: z.color.withOpacity(0.12),
                strokeWidth: 2,
                label: HorizontalLineLabel(
                  show: true,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 6),
                  style: TextStyle(color: z.color.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.w600),
                  labelResolver: (_) => z.name,
                ),
              ),
            ]),
        ],
      ),
    );
  }
}
