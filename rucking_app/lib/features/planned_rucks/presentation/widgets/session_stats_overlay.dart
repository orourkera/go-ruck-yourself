import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:rucking_app/core/models/ruck_session.dart';
import 'package:rucking_app/core/models/route.dart';
import 'package:rucking_app/core/theme/app_colors.dart';
import 'package:rucking_app/core/theme/app_text_styles.dart';

/// Comprehensive real-time stats overlay for active sessions
class SessionStatsOverlay extends StatefulWidget {
  final RuckSession activeSession;
  final Route? plannedRoute;
  final StatsDisplayMode displayMode;
  final bool showLiveUpdates;
  final bool showComparisons;
  final bool showPredictions;
  final bool allowCustomization;
  final List<StatType>? customStatTypes;
  final ValueChanged<StatsDisplayMode>? onDisplayModeChanged;

  const SessionStatsOverlay({
    super.key,
    required this.activeSession,
    this.plannedRoute,
    this.displayMode = StatsDisplayMode.essential,
    this.showLiveUpdates = true,
    this.showComparisons = true,
    this.showPredictions = false,
    this.allowCustomization = false,
    this.customStatTypes,
    this.onDisplayModeChanged,
  });

  @override
  State<SessionStatsOverlay> createState() => _SessionStatsOverlayState();
}

class _SessionStatsOverlayState extends State<SessionStatsOverlay>
    with TickerProviderStateMixin {
  late AnimationController _updateController;
  late AnimationController _slideController;
  late Animation<double> _slideAnimation;
  late Animation<Color?> _updateAnimation;
  
  bool _isExpanded = false;
  StatsDisplayMode _currentMode = StatsDisplayMode.essential;
  Map<StatType, StatData> _currentStats = {};
  Map<StatType, StatData> _previousStats = {};

  @override
  void initState() {
    super.initState();
    
    _currentMode = widget.displayMode;
    
    _updateController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _slideAnimation = CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeInOut,
    );
    
    _updateAnimation = ColorTween(
      begin: Colors.transparent,
      end: AppColors.primary.withOpacity(0.1),
    ).animate(CurvedAnimation(
      parent: _updateController,
      curve: Curves.easeInOut,
    ));
    
    _calculateStats();
    
    // Auto-update stats every second if live updates are enabled
    if (widget.showLiveUpdates) {
      _startLiveUpdates();
    }
  }

  @override
  void dispose() {
    _updateController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(SessionStatsOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (widget.activeSession != oldWidget.activeSession) {
      _updateStats();
    }
    
    if (widget.displayMode != oldWidget.displayMode) {
      setState(() {
        _currentMode = widget.displayMode;
      });
    }
  }

  void _startLiveUpdates() {
    // This would typically be handled by a stream or timer
    // For now, we'll simulate with periodic updates
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && widget.showLiveUpdates) {
        _updateStats();
        _startLiveUpdates();
      }
    });
  }

  void _updateStats() {
    _previousStats = Map.from(_currentStats);
    _calculateStats();
    
    // Trigger update animation if values changed
    if (_hasStatsChanged()) {
      _updateController.forward().then((_) {
        _updateController.reverse();
      });
    }
  }

  void _calculateStats() {
    final session = widget.activeSession;
    final route = widget.plannedRoute;
    
    _currentStats = {
      // Time stats
      StatType.elapsedTime: StatData(
        value: _formatDuration(session.elapsedTime ?? Duration.zero),
        numericValue: (session.elapsedTime?.inSeconds ?? 0).toDouble(),
        unit: '',
        trend: _calculateTrend(StatType.elapsedTime),
        comparison: widget.showComparisons ? _getComparison(StatType.elapsedTime) : null,
      ),
      
      // Distance stats
      StatType.distance: StatData(
        value: '${(session.distance ?? 0.0).toStringAsFixed(2)}',
        numericValue: session.distance ?? 0.0,
        unit: 'mi',
        trend: _calculateTrend(StatType.distance),
        comparison: widget.showComparisons ? _getComparison(StatType.distance) : null,
      ),
      
      // Pace stats
      StatType.currentPace: StatData(
        value: _calculateCurrentPace(),
        numericValue: _calculateCurrentPaceNumeric(),
        unit: '/mi',
        trend: _calculateTrend(StatType.currentPace),
        comparison: widget.showComparisons ? _getComparison(StatType.currentPace) : null,
      ),
      
      StatType.averagePace: StatData(
        value: _calculateAveragePace(),
        numericValue: _calculateAveragePaceNumeric(),
        unit: '/mi',
        trend: _calculateTrend(StatType.averagePace),
        comparison: widget.showComparisons ? _getComparison(StatType.averagePace) : null,
      ),
      
      // Elevation stats
      if (session.elevationGain != null)
        StatType.elevationGain: StatData(
          value: '${session.elevationGain!.toInt()}',
          numericValue: session.elevationGain!,
          unit: 'ft',
          trend: _calculateTrend(StatType.elevationGain),
          comparison: widget.showComparisons ? _getComparison(StatType.elevationGain) : null,
        ),
      
      // Calories (estimated)
      StatType.calories: StatData(
        value: '${_estimateCalories().toInt()}',
        numericValue: _estimateCalories(),
        unit: 'cal',
        trend: _calculateTrend(StatType.calories),
        comparison: widget.showComparisons ? _getComparison(StatType.calories) : null,
      ),
      
      // Progress stats
      if (route != null)
        StatType.progress: StatData(
          value: '${(_calculateProgress() * 100).toInt()}',
          numericValue: _calculateProgress() * 100,
          unit: '%',
          trend: _calculateTrend(StatType.progress),
          comparison: widget.showComparisons ? _getComparison(StatType.progress) : null,
        ),
      
      // ETA (if route available)
      if (route != null && widget.showPredictions)
        StatType.eta: StatData(
          value: _calculateETA(),
          numericValue: 0.0, // ETA is time-based
          unit: '',
          trend: StatTrend.neutral,
          comparison: null,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _slideAnimation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface.withOpacity(0.95),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with mode selector
              _buildHeader(),
              
              // Main stats display
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                child: _buildStatsContent(),
              ),
              
              // Expanded details
              if (_isExpanded) _buildExpandedDetails(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
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
          Icon(
            Icons.analytics,
            color: AppColors.primary,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            'Live Stats',
            style: AppTextStyles.subtitle1.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          
          const Spacer(),
          
          // Mode selector
          if (widget.allowCustomization)
            PopupMenuButton<StatsDisplayMode>(
              icon: Icon(
                Icons.view_module,
                color: AppColors.primary,
                size: 20,
              ),
              onSelected: (mode) {
                setState(() {
                  _currentMode = mode;
                });
                widget.onDisplayModeChanged?.call(mode);
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: StatsDisplayMode.minimal,
                  child: Text('Minimal'),
                ),
                const PopupMenuItem(
                  value: StatsDisplayMode.essential,
                  child: Text('Essential'),
                ),
                const PopupMenuItem(
                  value: StatsDisplayMode.detailed,
                  child: Text('Detailed'),
                ),
                const PopupMenuItem(
                  value: StatsDisplayMode.comprehensive,
                  child: Text('All Stats'),
                ),
              ],
            ),
          
          // Expand/collapse button
          IconButton(
            onPressed: _toggleExpanded,
            icon: AnimatedRotation(
              turns: _isExpanded ? 0.5 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                Icons.expand_more,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsContent() {
    final statsToShow = _getStatsForMode(_currentMode);
    
    return AnimatedBuilder(
      animation: _updateAnimation,
      builder: (context, child) {
        return Container(
          color: _updateAnimation.value,
          padding: const EdgeInsets.all(16),
          child: _buildStatsGrid(statsToShow),
        );
      },
    );
  }

  Widget _buildStatsGrid(List<StatType> statTypes) {
    final columns = _getColumnCount();
    
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        childAspectRatio: 1.2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: statTypes.length,
      itemBuilder: (context, index) {
        final statType = statTypes[index];
        final statData = _currentStats[statType];
        
        if (statData == null) return const SizedBox.shrink();
        
        return _buildStatCard(statType, statData);
      },
    );
  }

  Widget _buildStatCard(StatType type, StatData data) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.divider,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stat icon and trend
          Row(
            children: [
              Icon(
                _getStatIcon(type),
                color: _getStatColor(type),
                size: 16,
              ),
              const Spacer(),
              if (data.trend != StatTrend.neutral)
                Icon(
                  _getTrendIcon(data.trend),
                  color: _getTrendColor(data.trend),
                  size: 14,
                ),
            ],
          ),
          
          const SizedBox(height: 8),
          
          // Stat value
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(
                        data.value,
                        style: AppTextStyles.headline6.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _getStatColor(type),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (data.unit.isNotEmpty) ...[
                      const SizedBox(width: 2),
                      Text(
                        data.unit,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
                
                const SizedBox(height: 2),
                
                Text(
                  _getStatLabel(type),
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          
          // Comparison (if available)
          if (data.comparison != null) ...[
            const SizedBox(height: 4),
            Text(
              data.comparison!,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.info,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExpandedDetails() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Session Details',
            style: AppTextStyles.subtitle2.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Additional details
          _buildDetailRow('Session ID', widget.activeSession.id ?? 'N/A'),
          _buildDetailRow('Started', _formatStartTime()),
          _buildDetailRow('Status', widget.activeSession.status.value),
          
          if (widget.plannedRoute != null) ...[
            _buildDetailRow('Route', widget.plannedRoute!.name),
            _buildDetailRow('Total Distance', '${widget.plannedRoute!.distance.toStringAsFixed(1)} mi'),
          ],
          
          // Performance metrics
          const SizedBox(height: 12),
          
          Text(
            'Performance',
            style: AppTextStyles.subtitle2.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          
          const SizedBox(height: 8),
          
          _buildPerformanceMetrics(),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: AppTextStyles.body2.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.body2.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceMetrics() {
    final efficiency = _calculateEfficiency();
    final consistency = _calculateConsistency();
    
    return Column(
      children: [
        _buildMetricBar('Efficiency', efficiency, AppColors.success),
        const SizedBox(height: 8),
        _buildMetricBar('Consistency', consistency, AppColors.primary),
      ],
    );
  }

  Widget _buildMetricBar(String label, double value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: AppTextStyles.caption,
            ),
            const Spacer(),
            Text(
              '${(value * 100).toInt()}%',
              style: AppTextStyles.caption.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: value,
          backgroundColor: AppColors.divider,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      ],
    );
  }

  // Helper methods

  List<StatType> _getStatsForMode(StatsDisplayMode mode) {
    if (widget.customStatTypes != null) {
      return widget.customStatTypes!;
    }
    
    switch (mode) {
      case StatsDisplayMode.minimal:
        return [StatType.elapsedTime, StatType.distance];
      case StatsDisplayMode.essential:
        return [
          StatType.elapsedTime,
          StatType.distance,
          StatType.currentPace,
          StatType.progress,
        ];
      case StatsDisplayMode.detailed:
        return [
          StatType.elapsedTime,
          StatType.distance,
          StatType.currentPace,
          StatType.averagePace,
          StatType.elevationGain,
          StatType.progress,
        ].where((type) => _currentStats.containsKey(type)).toList();
      case StatsDisplayMode.comprehensive:
        return _currentStats.keys.toList();
    }
  }

  int _getColumnCount() {
    switch (_currentMode) {
      case StatsDisplayMode.minimal:
        return 2;
      case StatsDisplayMode.essential:
        return 2;
      case StatsDisplayMode.detailed:
        return 3;
      case StatsDisplayMode.comprehensive:
        return 3;
    }
  }

  IconData _getStatIcon(StatType type) {
    switch (type) {
      case StatType.elapsedTime:
        return Icons.access_time;
      case StatType.distance:
        return Icons.straighten;
      case StatType.currentPace:
        return Icons.speed;
      case StatType.averagePace:
        return Icons.trending_flat;
      case StatType.elevationGain:
        return Icons.trending_up;
      case StatType.calories:
        return Icons.local_fire_department;
      case StatType.progress:
        return Icons.percent;
      case StatType.eta:
        return Icons.schedule;
    }
  }

  String _getStatLabel(StatType type) {
    switch (type) {
      case StatType.elapsedTime:
        return 'Time';
      case StatType.distance:
        return 'Distance';
      case StatType.currentPace:
        return 'Current Pace';
      case StatType.averagePace:
        return 'Avg Pace';
      case StatType.elevationGain:
        return 'Elevation';
      case StatType.calories:
        return 'Calories';
      case StatType.progress:
        return 'Progress';
      case StatType.eta:
        return 'ETA';
    }
  }

  Color _getStatColor(StatType type) {
    switch (type) {
      case StatType.elapsedTime:
        return AppColors.primary;
      case StatType.distance:
        return AppColors.success;
      case StatType.currentPace:
        return AppColors.warning;
      case StatType.averagePace:
        return AppColors.info;
      case StatType.elevationGain:
        return AppColors.warning;
      case StatType.calories:
        return AppColors.error;
      case StatType.progress:
        return AppColors.primary;
      case StatType.eta:
        return AppColors.info;
    }
  }

  IconData _getTrendIcon(StatTrend trend) {
    switch (trend) {
      case StatTrend.up:
        return Icons.trending_up;
      case StatTrend.down:
        return Icons.trending_down;
      case StatTrend.neutral:
        return Icons.trending_flat;
    }
  }

  Color _getTrendColor(StatTrend trend) {
    switch (trend) {
      case StatTrend.up:
        return AppColors.success;
      case StatTrend.down:
        return AppColors.error;
      case StatTrend.neutral:
        return AppColors.textSecondary;
    }
  }

  // Calculation methods

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '${hours}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes}:${seconds.toString().padLeft(2, '0')}';
  }

  String _calculateCurrentPace() {
    // This would calculate based on recent movement
    // Simplified for demo
    final distance = widget.activeSession.distance ?? 0.0;
    final duration = widget.activeSession.elapsedTime ?? Duration.zero;
    
    if (distance <= 0 || duration.inSeconds <= 0) return '--:--';
    
    final paceSeconds = duration.inSeconds / distance;
    final minutes = (paceSeconds / 60).floor();
    final seconds = (paceSeconds % 60).floor();
    
    return '${minutes}:${seconds.toString().padLeft(2, '0')}';
  }

  double _calculateCurrentPaceNumeric() {
    final distance = widget.activeSession.distance ?? 0.0;
    final duration = widget.activeSession.elapsedTime ?? Duration.zero;
    
    if (distance <= 0 || duration.inSeconds <= 0) return 0.0;
    
    return duration.inSeconds / distance;
  }

  String _calculateAveragePace() {
    final distance = widget.activeSession.distance ?? 0.0;
    final duration = widget.activeSession.elapsedTime ?? Duration.zero;
    
    if (distance <= 0 || duration.inSeconds <= 0) return '--:--';
    
    final paceSeconds = duration.inSeconds / distance;
    final minutes = (paceSeconds / 60).floor();
    final seconds = (paceSeconds % 60).floor();
    
    return '${minutes}:${seconds.toString().padLeft(2, '0')}';
  }

  double _calculateAveragePaceNumeric() {
    final distance = widget.activeSession.distance ?? 0.0;
    final duration = widget.activeSession.elapsedTime ?? Duration.zero;
    
    if (distance <= 0 || duration.inSeconds <= 0) return 0.0;
    
    return duration.inSeconds / distance;
  }

  double _estimateCalories() {
    // Simplified calorie calculation
    final distance = widget.activeSession.distance ?? 0.0;
    final duration = widget.activeSession.elapsedTime ?? Duration.zero;
    const baseCaloriesPerMile = 100.0; // Approximate for rucking
    
    return distance * baseCaloriesPerMile;
  }

  double _calculateProgress() {
    if (widget.plannedRoute == null) return 0.0;
    
    final completed = widget.activeSession.distance ?? 0.0;
    final total = widget.plannedRoute!.distance;
    
    return total > 0 ? completed / total : 0.0;
  }

  String _calculateETA() {
    // Simplified ETA calculation
    if (widget.plannedRoute == null) return '--:--';
    
    final remaining = widget.plannedRoute!.distance - (widget.activeSession.distance ?? 0.0);
    final currentPaceNumeric = _calculateCurrentPaceNumeric();
    
    if (remaining <= 0 || currentPaceNumeric <= 0) return 'Arrived';
    
    final etaSeconds = remaining * currentPaceNumeric;
    final eta = DateTime.now().add(Duration(seconds: etaSeconds.round()));
    
    return '${eta.hour}:${eta.minute.toString().padLeft(2, '0')}';
  }

  StatTrend _calculateTrend(StatType statType) {
    final current = _currentStats[statType];
    final previous = _previousStats[statType];
    
    if (current == null || previous == null) return StatTrend.neutral;
    
    final diff = current.numericValue - previous.numericValue;
    const threshold = 0.01; // Minimum change to register as trend
    
    if (diff > threshold) return StatTrend.up;
    if (diff < -threshold) return StatTrend.down;
    return StatTrend.neutral;
  }

  String? _getComparison(StatType statType) {
    // This would compare against planned route, personal bests, etc.
    // Simplified for demo
    if (widget.plannedRoute == null) return null;
    
    switch (statType) {
      case StatType.currentPace:
        return 'vs target';
      case StatType.progress:
        return 'on track';
      default:
        return null;
    }
  }

  bool _hasStatsChanged() {
    for (final entry in _currentStats.entries) {
      final previous = _previousStats[entry.key];
      if (previous == null || entry.value.numericValue != previous.numericValue) {
        return true;
      }
    }
    return false;
  }

  String _formatStartTime() {
    final startTime = widget.activeSession.startTime;
    if (startTime == null) return 'Unknown';
    
    final now = DateTime.now();
    final difference = now.difference(startTime);
    
    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inMinutes}m ago';
    }
  }

  double _calculateEfficiency() {
    // Simplified efficiency calculation
    final planned = widget.plannedRoute?.distance ?? 0.0;
    final actual = widget.activeSession.distance ?? 0.0;
    
    if (planned <= 0) return 0.8; // Default efficiency
    
    return math.min(1.0, actual / planned);
  }

  double _calculateConsistency() {
    // This would analyze pace variation over time
    // Simplified for demo
    return 0.75; // Default consistency
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
    
    if (_isExpanded) {
      _slideController.forward();
    } else {
      _slideController.reverse();
    }
  }
}

enum StatsDisplayMode {
  minimal,
  essential,
  detailed,
  comprehensive,
}

enum StatType {
  elapsedTime,
  distance,
  currentPace,
  averagePace,
  elevationGain,
  calories,
  progress,
  eta,
}

enum StatTrend {
  up,
  down,
  neutral,
}

class StatData {
  final String value;
  final double numericValue;
  final String unit;
  final StatTrend trend;
  final String? comparison;

  StatData({
    required this.value,
    required this.numericValue,
    required this.unit,
    required this.trend,
    this.comparison,
  });
}
