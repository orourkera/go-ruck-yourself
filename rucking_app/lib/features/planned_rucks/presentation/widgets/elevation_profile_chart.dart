import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:rucking_app/core/models/route.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

/// Interactive elevation profile chart widget
class ElevationProfileChart extends StatefulWidget {
  final List<ElevationPoint> elevationData;
  final Route route;
  final double? height;
  final bool showDetailedTooltips;
  final bool showGradientAreas;
  final bool isInteractive;
  final ValueChanged<ElevationPoint?>? onPointSelected;

  const ElevationProfileChart({
    super.key,
    required this.elevationData,
    required this.route,
    this.height,
    this.showDetailedTooltips = true,
    this.showGradientAreas = true,
    this.isInteractive = true,
    this.onPointSelected,
  });

  @override
  State<ElevationProfileChart> createState() => _ElevationProfileChartState();
}

class _ElevationProfileChartState extends State<ElevationProfileChart>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;
  
  int? _selectedIndex;
  bool _showFullProfile = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOutCubic,
    );
    
    // Start animation after a short delay
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _animationController.forward();
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.elevationData.isEmpty) {
      return _buildEmptyState();
    }

    return Container(
      height: widget.height ?? 200,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Chart header with stats
          _buildChartHeader(),
          
          // Main chart
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 20, 16),
              child: AnimatedBuilder(
                animation: _animation,
                builder: (context, child) {
                  return LineChart(
                    _buildChartData(),
                    swapAnimationDuration: const Duration(milliseconds: 300),
                  );
                },
              ),
            ),
          ),
          
          // Chart footer with controls
          if (widget.isInteractive) _buildChartFooter(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      height: widget.height ?? 200,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.divider,
          style: BorderStyle.solid,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.show_chart,
              size: 48,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 8),
            Text(
              'No elevation data available',
              style: AppTextStyles.body2.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartHeader() {
    final stats = _calculateElevationStats();
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.05),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(12),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildStatItem(
              'Min Elevation',
              '${stats.minElevation.toInt()} ft',
              Icons.trending_down,
              AppColors.info,
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: AppColors.divider,
          ),
          Expanded(
            child: _buildStatItem(
              'Max Elevation',
              '${stats.maxElevation.toInt()} ft',
              Icons.trending_up,
              AppColors.success,
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: AppColors.divider,
          ),
          Expanded(
            child: _buildStatItem(
              'Total Gain',
              '${stats.totalGain.toInt()} ft',
              Icons.moving,
              AppColors.warning,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(
          icon,
          size: 20,
          color: color,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTextStyles.subtitle2.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: AppColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildChartFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(12),
        ),
      ),
      child: Row(
        children: [
          // Distance marker
          Expanded(
            child: Text(
              '0 mi',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          
          // View toggle
          TextButton.icon(
            onPressed: () {
              setState(() {
                _showFullProfile = !_showFullProfile;
              });
            },
            icon: Icon(
              _showFullProfile ? Icons.compress : Icons.expand,
              size: 16,
            ),
            label: Text(
              _showFullProfile ? 'Simplified' : 'Detailed',
              style: AppTextStyles.caption,
            ),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
          
          // End distance marker
          Expanded(
            child: Text(
              widget.route.formattedDistance,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  LineChartData _buildChartData() {
    final spots = _getChartSpots();
    final gradientColors = _getGradientColors();
    
    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        horizontalInterval: _getHorizontalInterval(),
        verticalInterval: _getVerticalInterval(),
        getDrawingHorizontalLine: (value) {
          return FlLine(
            color: AppColors.divider.withOpacity(0.3),
            strokeWidth: 1,
            dashArray: [5, 5],
          );
        },
        getDrawingVerticalLine: (value) {
          return FlLine(
            color: AppColors.divider.withOpacity(0.2),
            strokeWidth: 1,
            dashArray: [3, 3],
          );
        },
      ),
      titlesData: FlTitlesData(
        show: true,
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            interval: _getVerticalInterval(),
            getTitlesWidget: (value, meta) {
              return _buildBottomTitle(value);
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: _getHorizontalInterval(),
            reservedSize: 50,
            getTitlesWidget: (value, meta) {
              return _buildLeftTitle(value);
            },
          ),
        ),
      ),
      borderData: FlBorderData(
        show: true,
        border: Border(
          bottom: BorderSide(
            color: AppColors.divider,
            width: 1,
          ),
          left: BorderSide(
            color: AppColors.divider,
            width: 1,
          ),
        ),
      ),
      minX: 0,
      maxX: widget.route.distance,
      minY: _getMinY(),
      maxY: _getMaxY(),
      lineBarsData: [
        LineChartBarData(
          spots: spots.map((spot) {
            return FlSpot(
              spot.x,
              spot.y * _animation.value + _getMinY() * (1 - _animation.value),
            );
          }).toList(),
          isCurved: true,
          curveSmoothness: 0.3,
          color: AppColors.primary,
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: FlDotData(
            show: _selectedIndex != null,
            getDotPainter: (spot, percent, barData, index) {
              if (index == _selectedIndex) {
                return FlDotCirclePainter(
                  radius: 6,
                  color: AppColors.primary,
                  strokeWidth: 3,
                  strokeColor: Colors.white,
                );
              }
              return FlDotCirclePainter(
                radius: 0,
                color: Colors.transparent,
              );
            },
          ),
          belowBarData: widget.showGradientAreas
              ? BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: gradientColors,
                  ),
                )
              : BarAreaData(show: false),
        ),
      ],
      lineTouchData: widget.isInteractive
          ? LineTouchData(
              enabled: true,
              touchTooltipData: _buildTooltipData(),
              touchCallback: _handleTouch,
              getTouchedSpotIndicator: (barData, spotIndexes) {
                return spotIndexes.map((index) {
                  return TouchedSpotIndicatorData(
                    FlLine(
                      color: AppColors.primary.withOpacity(0.5),
                      strokeWidth: 2,
                      dashArray: [3, 3],
                    ),
                    FlDotData(
                      getDotPainter: (spot, percent, barData, index) {
                        return FlDotCirclePainter(
                          radius: 8,
                          color: AppColors.primary,
                          strokeWidth: 3,
                          strokeColor: Colors.white,
                        );
                      },
                    ),
                  );
                }).toList();
              },
            )
          : LineTouchData(enabled: false),
    );
  }

  List<FlSpot> _getChartSpots() {
    if (_showFullProfile || widget.elevationData.length <= 50) {
      return widget.elevationData.map((point) {
        return FlSpot(point.distance, point.elevation);
      }).toList();
    }
    
    // Simplify the profile for better performance
    final simplified = <FlSpot>[];
    final step = widget.elevationData.length / 50;
    
    for (int i = 0; i < widget.elevationData.length; i += step.ceil()) {
      final point = widget.elevationData[i];
      simplified.add(FlSpot(point.distance, point.elevation));
    }
    
    // Always include the last point
    if (simplified.last.x != widget.elevationData.last.distance) {
      final lastPoint = widget.elevationData.last;
      simplified.add(FlSpot(lastPoint.distance, lastPoint.elevation));
    }
    
    return simplified;
  }

  List<Color> _getGradientColors() {
    return [
      AppColors.primary.withOpacity(0.4),
      AppColors.primary.withOpacity(0.1),
      AppColors.primary.withOpacity(0.05),
    ];
  }

  LineTouchTooltipData _buildTooltipData() {
    return LineTouchTooltipData(
      tooltipBgColor: AppColors.surface.withOpacity(0.95),
      tooltipRoundedRadius: 8,
      tooltipPadding: const EdgeInsets.all(12),
      tooltipMargin: 8,
      getTooltipItems: (touchedSpots) {
        if (!widget.showDetailedTooltips || touchedSpots.isEmpty) {
          return [];
        }
        
        final spot = touchedSpots.first;
        final distance = spot.x;
        final elevation = spot.y;
        
        // Find the actual elevation point for more details
        ElevationPoint? elevationPoint;
        try {
          elevationPoint = widget.elevationData.firstWhere(
            (point) => (point.distance - distance).abs() < 0.01,
          );
        } catch (e) {
          // Point not found, use basic info
        }
        
        return [
          LineTooltipItem(
            '${distance.toStringAsFixed(1)} mi\n${elevation.toInt()} ft',
            AppTextStyles.body2.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
            ),
            children: [
              if (elevationPoint?.grade != null)
                TextSpan(
                  text: '\nGrade: ${elevationPoint!.grade!.toStringAsFixed(1)}%',
                  style: AppTextStyles.caption.copyWith(
                    color: _getGradeColor(elevationPoint.grade!),
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ];
      },
    );
  }

  Widget _buildBottomTitle(double value) {
    if (value == 0) {
      return Text(
        '0',
        style: AppTextStyles.caption.copyWith(
          color: AppColors.textSecondary,
        ),
      );
    }
    
    if (value == widget.route.distance) {
      return Text(
        value.toStringAsFixed(1),
        style: AppTextStyles.caption.copyWith(
          color: AppColors.textSecondary,
        ),
      );
    }
    
    // Show intermediate values at reasonable intervals
    final interval = _getVerticalInterval();
    if (value % interval == 0) {
      return Text(
        value.toStringAsFixed(value < 10 ? 1 : 0),
        style: AppTextStyles.caption.copyWith(
          color: AppColors.textSecondary,
        ),
      );
    }
    
    return const SizedBox.shrink();
  }

  Widget _buildLeftTitle(double value) {
    if (value % _getHorizontalInterval() == 0) {
      return Text(
        '${value.toInt()}',
        style: AppTextStyles.caption.copyWith(
          color: AppColors.textSecondary,
        ),
      );
    }
    return const SizedBox.shrink();
  }

  // Helper methods

  ElevationStats _calculateElevationStats() {
    double minElevation = widget.elevationData.first.elevation;
    double maxElevation = widget.elevationData.first.elevation;
    double totalGain = 0.0;
    double previousElevation = widget.elevationData.first.elevation;
    
    for (final point in widget.elevationData) {
      if (point.elevation < minElevation) minElevation = point.elevation;
      if (point.elevation > maxElevation) maxElevation = point.elevation;
      
      if (point.elevation > previousElevation) {
        totalGain += point.elevation - previousElevation;
      }
      previousElevation = point.elevation;
    }
    
    return ElevationStats(
      minElevation: minElevation,
      maxElevation: maxElevation,
      totalGain: totalGain,
    );
  }

  double _getMinY() {
    final stats = _calculateElevationStats();
    final padding = (stats.maxElevation - stats.minElevation) * 0.1;
    return (stats.minElevation - padding).floorToDouble();
  }

  double _getMaxY() {
    final stats = _calculateElevationStats();
    final padding = (stats.maxElevation - stats.minElevation) * 0.1;
    return (stats.maxElevation + padding).ceilToDouble();
  }

  double _getHorizontalInterval() {
    final range = _getMaxY() - _getMinY();
    if (range > 2000) return 500;
    if (range > 1000) return 250;
    if (range > 500) return 100;
    if (range > 200) return 50;
    return 25;
  }

  double _getVerticalInterval() {
    final distance = widget.route.distance;
    if (distance > 20) return distance / 4;
    if (distance > 10) return distance / 5;
    if (distance > 5) return 1;
    return 0.5;
  }

  Color _getGradeColor(double grade) {
    if (grade.abs() < 2) return AppColors.success;
    if (grade.abs() < 5) return AppColors.warning;
    return AppColors.error;
  }

  void _handleTouch(FlTouchEvent event, LineTouchResponse? response) {
    if (!widget.isInteractive) return;
    
    if (response?.lineBarSpots?.isNotEmpty == true) {
      final spot = response!.lineBarSpots!.first;
      final distance = spot.x;
      
      // Find the closest elevation point
      ElevationPoint? closestPoint;
      double closestDistance = double.infinity;
      
      for (int i = 0; i < widget.elevationData.length; i++) {
        final point = widget.elevationData[i];
        final diff = (point.distance - distance).abs();
        
        if (diff < closestDistance) {
          closestDistance = diff;
          closestPoint = point;
          setState(() {
            _selectedIndex = i;
          });
        }
      }
      
      if (widget.onPointSelected != null && closestPoint != null) {
        widget.onPointSelected!(closestPoint);
      }
    } else {
      setState(() {
        _selectedIndex = null;
      });
      
      if (widget.onPointSelected != null) {
        widget.onPointSelected!(null);
      }
    }
  }
}

class ElevationStats {
  final double minElevation;
  final double maxElevation;
  final double totalGain;

  ElevationStats({
    required this.minElevation,
    required this.maxElevation,
    required this.totalGain,
  });
}
