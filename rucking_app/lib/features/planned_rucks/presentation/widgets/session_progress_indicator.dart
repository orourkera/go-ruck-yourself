import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:rucking_app/core/models/ruck_session.dart';
import 'package:rucking_app/core/models/route.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

/// Advanced progress indicator widget with multiple visualization modes
class SessionProgressIndicator extends StatefulWidget {
  final RuckSession activeSession;
  final Route? plannedRoute;
  final ProgressIndicatorMode mode;
  final bool showMilestones;
  final bool showAnimation;
  final bool showSegmentBreakdown;
  final VoidCallback? onMilestoneReached;

  const SessionProgressIndicator({
    super.key,
    required this.activeSession,
    this.plannedRoute,
    this.mode = ProgressIndicatorMode.linear,
    this.showMilestones = true,
    this.showAnimation = true,
    this.showSegmentBreakdown = false,
    this.onMilestoneReached,
  });

  @override
  State<SessionProgressIndicator> createState() => _SessionProgressIndicatorState();
}

class _SessionProgressIndicatorState extends State<SessionProgressIndicator>
    with TickerProviderStateMixin {
  late AnimationController _progressController;
  late AnimationController _pulseController;
  late Animation<double> _progressAnimation;
  late Animation<double> _pulseAnimation;
  
  double _previousProgress = 0.0;
  List<Milestone> _milestones = [];
  int _lastReachedMilestone = -1;

  @override
  void initState() {
    super.initState();
    
    _progressController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _progressAnimation = CurvedAnimation(
      parent: _progressController,
      curve: Curves.easeOutCubic,
    );
    
    _pulseAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
    
    if (widget.showAnimation) {
      _pulseController.repeat(reverse: true);
    }
    
    _initializeMilestones();
    _updateProgress();
  }

  @override
  void dispose() {
    _progressController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(SessionProgressIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (widget.activeSession != oldWidget.activeSession ||
        widget.plannedRoute != oldWidget.plannedRoute) {
      _updateProgress();
      _checkMilestones();
    }
  }

  void _initializeMilestones() {
    _milestones.clear();
    
    if (widget.plannedRoute != null) {
      final totalDistance = widget.plannedRoute!.distance;
      
      // Add mile markers
      for (int i = 1; i < totalDistance.floor(); i++) {
        _milestones.add(Milestone(
          id: 'mile_$i',
          distance: i.toDouble(),
          title: 'Mile $i',
          type: MilestoneType.distance,
          isReached: false,
        ));
      }
      
      // Add percentage milestones
      for (int i = 25; i <= 75; i += 25) {
        final distance = totalDistance * (i / 100);
        _milestones.add(Milestone(
          id: 'percent_$i',
          distance: distance,
          title: '$i% Complete',
          type: MilestoneType.percentage,
          isReached: false,
        ));
      }
      
      // Add elevation milestones if available
      if (widget.plannedRoute!.elevationProfile.isNotEmpty) {
        final highPoint = _findHighestPoint();
        if (highPoint != null) {
          _milestones.add(Milestone(
            id: 'high_point',
            distance: highPoint.distance,
            title: 'Highest Point',
            subtitle: '${highPoint.elevation.toInt()} ft',
            type: MilestoneType.elevation,
            isReached: false,
          ));
        }
      }
      
      // Sort milestones by distance
      _milestones.sort((a, b) => a.distance.compareTo(b.distance));
    }
  }

  void _updateProgress() {
    final currentDistance = widget.activeSession.distance ?? 0.0;
    final totalDistance = widget.plannedRoute?.distance ?? currentDistance;
    final newProgress = totalDistance > 0 ? currentDistance / totalDistance : 0.0;
    
    if (widget.showAnimation && (newProgress - _previousProgress).abs() > 0.01) {
      _progressController.reset();
      _progressController.forward();
    }
    
    _previousProgress = newProgress;
  }

  void _checkMilestones() {
    final currentDistance = widget.activeSession.distance ?? 0.0;
    
    for (int i = 0; i < _milestones.length; i++) {
      final milestone = _milestones[i];
      
      if (!milestone.isReached && currentDistance >= milestone.distance) {
        setState(() {
          _milestones[i] = milestone.copyWith(isReached: true);
        });
        
        if (i > _lastReachedMilestone) {
          _lastReachedMilestone = i;
          if (widget.onMilestoneReached != null) {
            widget.onMilestoneReached!();
          }
          _showMilestoneReachedAnimation(milestone);
        }
      }
    }
  }

  void _showMilestoneReachedAnimation(Milestone milestone) {
    // Trigger celebration animation
    _pulseController.reset();
    _pulseController.forward().then((_) {
      if (widget.showAnimation) {
        _pulseController.repeat(reverse: true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.mode) {
      case ProgressIndicatorMode.circular:
        return _buildCircularProgress();
      case ProgressIndicatorMode.segmented:
        return _buildSegmentedProgress();
      case ProgressIndicatorMode.milestone:
        return _buildMilestoneProgress();
      default:
        return _buildLinearProgress();
    }
  }

  Widget _buildLinearProgress() {
    final progress = _calculateProgress();
    
    return Container(
      padding: const EdgeInsets.all(16),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                Icons.trending_up,
                color: AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Progress',
                style: AppTextStyles.subtitle1.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                '${(progress.percentage * 100).toInt()}%',
                style: AppTextStyles.subtitle1.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Progress bar with animation
          AnimatedBuilder(
            animation: widget.showAnimation ? _progressAnimation : 
                      const AlwaysStoppedAnimation(1.0),
            builder: (context, child) {
              return Stack(
                children: [
                  // Background bar
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  
                  // Progress bar
                  FractionallySizedBox(
                    widthFactor: (progress.percentage * _progressAnimation.value)
                        .clamp(0.0, 1.0),
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.primary,
                            AppColors.primary.withOpacity(0.7),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // Milestone markers
                  if (widget.showMilestones) _buildMilestoneMarkers(),
                ],
              );
            },
          ),
          
          const SizedBox(height: 12),
          
          // Progress details
          Row(
            children: [
              Expanded(
                child: Text(
                  '${progress.completedDistance.toStringAsFixed(1)} of ${progress.totalDistance.toStringAsFixed(1)} miles',
                  style: AppTextStyles.body2.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              if (progress.remainingDistance > 0)
                Text(
                  '${progress.remainingDistance.toStringAsFixed(1)} miles remaining',
                  style: AppTextStyles.body2.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCircularProgress() {
    final progress = _calculateProgress();
    
    return Container(
      padding: const EdgeInsets.all(16),
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
          // Circular progress indicator
          SizedBox(
            width: 120,
            height: 120,
            child: AnimatedBuilder(
              animation: widget.showAnimation ? _progressAnimation : 
                        const AlwaysStoppedAnimation(1.0),
              builder: (context, child) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // Background circle
                    CircularProgressIndicator(
                      value: 1.0,
                      strokeWidth: 8,
                      backgroundColor: AppColors.divider,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.divider,
                      ),
                    ),
                    
                    // Progress circle
                    CircularProgressIndicator(
                      value: (progress.percentage * _progressAnimation.value)
                          .clamp(0.0, 1.0),
                      strokeWidth: 8,
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.primary,
                      ),
                    ),
                    
                    // Pulse effect
                    if (widget.showAnimation)
                      AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) {
                          return Container(
                            width: 80 + (_pulseAnimation.value * 10),
                            height: 80 + (_pulseAnimation.value * 10),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primary.withOpacity(
                                0.1 * (1 - _pulseAnimation.value),
                              ),
                            ),
                          );
                        },
                      ),
                    
                    // Center content
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${(progress.percentage * 100).toInt()}%',
                          style: AppTextStyles.headline5.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                        Text(
                          'Complete',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildCircularStat(
                'Distance',
                '${progress.completedDistance.toStringAsFixed(1)} mi',
                Icons.straighten,
              ),
              if (progress.remainingDistance > 0)
                _buildCircularStat(
                  'Remaining',
                  '${progress.remainingDistance.toStringAsFixed(1)} mi',
                  Icons.flag,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentedProgress() {
    final progress = _calculateProgress();
    final segments = _createSegments();
    
    return Container(
      padding: const EdgeInsets.all(16),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(
            'Segment Progress',
            style: AppTextStyles.subtitle1.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Segmented progress bar
          Row(
            children: segments.map((segment) {
              return Expanded(
                child: Container(
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: segment.isCompleted 
                        ? _getSegmentColor(segment.type)
                        : AppColors.divider,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              );
            }).toList(),
          ),
          
          const SizedBox(height: 16),
          
          // Segment breakdown
          if (widget.showSegmentBreakdown) _buildSegmentBreakdown(segments),
        ],
      ),
    );
  }

  Widget _buildMilestoneProgress() {
    return Container(
      padding: const EdgeInsets.all(16),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(
            'Milestones',
            style: AppTextStyles.subtitle1.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Milestone timeline
          SizedBox(
            height: 200,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _milestones.length,
              itemBuilder: (context, index) {
                final milestone = _milestones[index];
                return _buildMilestoneItem(milestone, index);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMilestoneMarkers() {
    if (widget.plannedRoute == null) return const SizedBox.shrink();
    
    final totalDistance = widget.plannedRoute!.distance;
    
    return Positioned.fill(
      child: Stack(
        children: _milestones.map((milestone) {
          final position = milestone.distance / totalDistance;
          
          return Positioned(
            left: position * MediaQuery.of(context).size.width * 0.8, // Approximate width
            top: -4,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: milestone.isReached 
                    ? _getMilestoneColor(milestone.type)
                    : AppColors.divider,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: 2,
                ),
              ),
              child: Icon(
                _getMilestoneIcon(milestone.type),
                size: 8,
                color: Colors.white,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCircularStat(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(
          icon,
          size: 16,
          color: AppColors.textSecondary,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTextStyles.body2.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildSegmentBreakdown(List<ProgressSegment> segments) {
    return Column(
      children: segments.map((segment) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: segment.isCompleted 
                      ? _getSegmentColor(segment.type)
                      : AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  segment.label,
                  style: AppTextStyles.body2.copyWith(
                    color: segment.isCompleted 
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                ),
              ),
              if (segment.isCompleted)
                Icon(
                  Icons.check,
                  size: 16,
                  color: _getSegmentColor(segment.type),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMilestoneItem(Milestone milestone, int index) {
    return Container(
      width: 80,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          // Milestone marker
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: milestone.isReached 
                  ? _getMilestoneColor(milestone.type)
                  : AppColors.divider,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white,
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              _getMilestoneIcon(milestone.type),
              color: Colors.white,
              size: 20,
            ),
          ),
          
          const SizedBox(height: 8),
          
          // Milestone title
          Text(
            milestone.title,
            style: AppTextStyles.caption.copyWith(
              fontWeight: FontWeight.bold,
              color: milestone.isReached 
                  ? AppColors.textPrimary
                  : AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          
          if (milestone.subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              milestone.subtitle!,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          
          const SizedBox(height: 8),
          
          // Connection line
          if (index < _milestones.length - 1)
            Container(
              height: 2,
              width: 60,
              color: milestone.isReached && index < _lastReachedMilestone
                  ? AppColors.primary
                  : AppColors.divider,
            ),
        ],
      ),
    );
  }

  // Helper methods

  ProgressData _calculateProgress() {
    final currentDistance = widget.activeSession.distance ?? 0.0;
    final totalDistance = widget.plannedRoute?.distance ?? currentDistance;
    final percentage = totalDistance > 0 ? currentDistance / totalDistance : 0.0;
    
    return ProgressData(
      percentage: percentage.clamp(0.0, 1.0),
      completedDistance: currentDistance,
      totalDistance: totalDistance,
      remainingDistance: (totalDistance - currentDistance).clamp(0.0, totalDistance),
    );
  }

  List<ProgressSegment> _createSegments() {
    final currentDistance = widget.activeSession.distance ?? 0.0;
    final totalDistance = widget.plannedRoute?.distance ?? currentDistance;
    const segmentCount = 10;
    const segmentSize = 1.0 / segmentCount;
    
    return List.generate(segmentCount, (index) {
      final segmentStart = index * segmentSize * totalDistance;
      final segmentEnd = (index + 1) * segmentSize * totalDistance;
      
      return ProgressSegment(
        label: 'Segment ${index + 1}',
        startDistance: segmentStart,
        endDistance: segmentEnd,
        type: SegmentType.distance,
        isCompleted: currentDistance >= segmentEnd,
      );
    });
  }

  ElevationPoint? _findHighestPoint() {
    if (widget.plannedRoute?.elevationProfile.isEmpty != false) return null;
    
    return widget.plannedRoute!.elevationProfile.reduce((a, b) => 
        a.elevation > b.elevation ? a : b
    );
  }

  Color _getMilestoneColor(MilestoneType type) {
    switch (type) {
      case MilestoneType.distance:
        return AppColors.primary;
      case MilestoneType.percentage:
        return AppColors.success;
      case MilestoneType.elevation:
        return AppColors.warning;
      case MilestoneType.poi:
        return AppColors.info;
    }
  }

  IconData _getMilestoneIcon(MilestoneType type) {
    switch (type) {
      case MilestoneType.distance:
        return Icons.straighten;
      case MilestoneType.percentage:
        return Icons.percent;
      case MilestoneType.elevation:
        return Icons.terrain;
      case MilestoneType.poi:
        return Icons.place;
    }
  }

  Color _getSegmentColor(SegmentType type) {
    switch (type) {
      case SegmentType.distance:
        return AppColors.primary;
      case SegmentType.elevation:
        return AppColors.warning;
      case SegmentType.time:
        return AppColors.info;
    }
  }
}

enum ProgressIndicatorMode {
  linear,
  circular,
  segmented,
  milestone,
}

enum MilestoneType {
  distance,
  percentage,
  elevation,
  poi,
}

enum SegmentType {
  distance,
  elevation,
  time,
}

class ProgressData {
  final double percentage;
  final double completedDistance;
  final double totalDistance;
  final double remainingDistance;

  ProgressData({
    required this.percentage,
    required this.completedDistance,
    required this.totalDistance,
    required this.remainingDistance,
  });
}

class Milestone {
  final String id;
  final double distance;
  final String title;
  final String? subtitle;
  final MilestoneType type;
  final bool isReached;

  Milestone({
    required this.id,
    required this.distance,
    required this.title,
    this.subtitle,
    required this.type,
    required this.isReached,
  });

  Milestone copyWith({
    String? id,
    double? distance,
    String? title,
    String? subtitle,
    MilestoneType? type,
    bool? isReached,
  }) {
    return Milestone(
      id: id ?? this.id,
      distance: distance ?? this.distance,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      type: type ?? this.type,
      isReached: isReached ?? this.isReached,
    );
  }
}

class ProgressSegment {
  final String label;
  final double startDistance;
  final double endDistance;
  final SegmentType type;
  final bool isCompleted;

  ProgressSegment({
    required this.label,
    required this.startDistance,
    required this.endDistance,
    required this.type,
    required this.isCompleted,
  });
}
