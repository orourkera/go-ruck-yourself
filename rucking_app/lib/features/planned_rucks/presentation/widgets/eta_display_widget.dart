import 'package:flutter/material.dart';
import 'package:rucking_app/core/models/ruck_session.dart';
import 'package:rucking_app/core/models/route.dart';
import 'package:rucking_app/core/theme/app_colors.dart';
import 'package:rucking_app/core/theme/app_text_styles.dart';

/// Smart ETA display widget with multiple calculation methods
class ETADisplayWidget extends StatefulWidget {
  final RuckSession activeSession;
  final Route? plannedRoute;
  final bool showDetailedBreakdown;
  final bool showConfidenceIndicator;
  final bool showAlternativeETAs;
  final ETACalculationMethod calculationMethod;

  const ETADisplayWidget({
    super.key,
    required this.activeSession,
    this.plannedRoute,
    this.showDetailedBreakdown = false,
    this.showConfidenceIndicator = true,
    this.showAlternativeETAs = false,
    this.calculationMethod = ETACalculationMethod.adaptive,
  });

  @override
  State<ETADisplayWidget> createState() => _ETADisplayWidgetState();
}

class _ETADisplayWidgetState extends State<ETADisplayWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  
  ETAData? _currentETA;
  List<ETAData> _alternativeETAs = [];

  @override
  void initState() {
    super.initState();
    
    _pulseController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
    
    _pulseController.repeat(reverse: true);
    _calculateETAs();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ETADisplayWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (widget.activeSession != oldWidget.activeSession ||
        widget.plannedRoute != oldWidget.plannedRoute) {
      _calculateETAs();
    }
  }

  void _calculateETAs() {
    _currentETA = _calculateETA(widget.calculationMethod);
    
    if (widget.showAlternativeETAs) {
      _alternativeETAs = [
        if (widget.calculationMethod != ETACalculationMethod.currentPace)
          _calculateETA(ETACalculationMethod.currentPace),
        if (widget.calculationMethod != ETACalculationMethod.averagePace)
          _calculateETA(ETACalculationMethod.averagePace),
        if (widget.calculationMethod != ETACalculationMethod.movingAverage)
          _calculateETA(ETACalculationMethod.movingAverage),
      ].whereType<ETAData>().toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentETA == null) {
      return _buildNoDataState();
    }

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
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          _buildHeader(),
          
          const SizedBox(height: 16),
          
          // Main ETA display
          _buildMainETA(),
          
          // Confidence indicator
          if (widget.showConfidenceIndicator) ...[
            const SizedBox(height: 12),
            _buildConfidenceIndicator(),
          ],
          
          // Detailed breakdown
          if (widget.showDetailedBreakdown) ...[
            const SizedBox(height: 16),
            _buildDetailedBreakdown(),
          ],
          
          // Alternative ETAs
          if (widget.showAlternativeETAs && _alternativeETAs.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildAlternativeETAs(),
          ],
        ],
      ),
    );
  }

  Widget _buildNoDataState() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Icon(
            Icons.schedule,
            color: AppColors.textSecondary,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            'ETA calculating...',
            style: AppTextStyles.body2.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _pulseAnimation.value,
              child: Icon(
                Icons.schedule,
                color: _getETAStatusColor(),
                size: 24,
              ),
            );
          },
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Estimated Time of Arrival',
            style: AppTextStyles.subtitle1.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        
        // Calculation method indicator
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _getCalculationMethodLabel(),
            style: AppTextStyles.caption.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMainETA() {
    final eta = _currentETA!;
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _getETAStatusColor().withOpacity(0.1),
            _getETAStatusColor().withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _getETAStatusColor().withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // Primary ETA time
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _formatTime(eta.estimatedArrivalTime),
                style: AppTextStyles.headline3.copyWith(
                  fontWeight: FontWeight.bold,
                  color: _getETAStatusColor(),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatDate(eta.estimatedArrivalTime),
                style: AppTextStyles.body2.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 8),
          
          // Time remaining
          Text(
            'in ${_formatDuration(eta.timeRemaining)}',
            style: AppTextStyles.subtitle1.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Distance and pace info
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildETAStatItem(
                'Remaining',
                '${eta.distanceRemaining.toStringAsFixed(1)} mi',
                Icons.straighten,
              ),
              Container(width: 1, height: 30, color: AppColors.divider),
              _buildETAStatItem(
                'Avg Pace',
                '${eta.averagePace.toStringAsFixed(1)} mph',
                Icons.speed,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildETAStatItem(String label, String value, IconData icon) {
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

  Widget _buildConfidenceIndicator() {
    final confidence = _currentETA!.confidence;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Confidence: ',
              style: AppTextStyles.body2.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            Text(
              _getConfidenceLabel(confidence),
              style: AppTextStyles.body2.copyWith(
                color: _getConfidenceColor(confidence),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: confidence,
          backgroundColor: AppColors.divider,
          valueColor: AlwaysStoppedAnimation<Color>(
            _getConfidenceColor(confidence),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailedBreakdown() {
    final eta = _currentETA!;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ETA Breakdown',
          style: AppTextStyles.subtitle2.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        
        _buildBreakdownItem(
          'Current Position',
          '${eta.completedDistance.toStringAsFixed(1)} mi completed',
          Icons.location_on,
        ),
        
        _buildBreakdownItem(
          'Current Pace',
          '${eta.currentPace.toStringAsFixed(1)} mph',
          Icons.speed,
        ),
        
        _buildBreakdownItem(
          'Time Elapsed',
          _formatDuration(eta.elapsedTime),
          Icons.access_time,
        ),
        
        if (eta.elevationRemaining > 0)
          _buildBreakdownItem(
            'Elevation Remaining',
            '${eta.elevationRemaining.toInt()} ft',
            Icons.trending_up,
          ),
      ],
    );
  }

  Widget _buildBreakdownItem(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.body2.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: AppTextStyles.body2.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlternativeETAs() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Alternative Estimates',
          style: AppTextStyles.subtitle2.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        
        ..._alternativeETAs.map((eta) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getMethodLabel(eta.calculationMethod),
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        _formatTime(eta.estimatedArrivalTime),
                        style: AppTextStyles.body2.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                
                Text(
                  _formatDuration(eta.timeRemaining),
                  style: AppTextStyles.body2.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // Helper methods

  ETAData? _calculateETA(ETACalculationMethod method) {
    final session = widget.activeSession;
    final route = widget.plannedRoute;
    
    if (session.distance == null || session.elapsedTime == null) {
      return null;
    }
    
    final completedDistance = session.distance!;
    final elapsedTime = session.elapsedTime!;
    final totalDistance = route?.distance ?? completedDistance;
    final distanceRemaining = totalDistance - completedDistance;
    
    if (distanceRemaining <= 0) {
      return ETAData(
        estimatedArrivalTime: DateTime.now(),
        timeRemaining: Duration.zero,
        confidence: 1.0,
        calculationMethod: method,
        completedDistance: completedDistance,
        distanceRemaining: 0,
        currentPace: 0,
        averagePace: completedDistance / (elapsedTime.inHours),
        elapsedTime: elapsedTime,
        elevationRemaining: 0,
      );
    }
    
    double paceForCalculation;
    double confidence;
    
    switch (method) {
      case ETACalculationMethod.currentPace:
        paceForCalculation = _calculateCurrentPace();
        confidence = _calculateCurrentPaceConfidence();
        break;
        
      case ETACalculationMethod.averagePace:
        paceForCalculation = completedDistance / elapsedTime.inHours;
        confidence = _calculateAveragePaceConfidence();
        break;
        
      case ETACalculationMethod.movingAverage:
        paceForCalculation = _calculateMovingAveragePace();
        confidence = _calculateMovingAverageConfidence();
        break;
        
      case ETACalculationMethod.adaptive:
        paceForCalculation = _calculateAdaptivePace();
        confidence = _calculateAdaptiveConfidence();
        break;
    }
    
    final hoursRemaining = distanceRemaining / paceForCalculation;
    final timeRemaining = Duration(
      milliseconds: (hoursRemaining * 3600 * 1000).round(),
    );
    
    return ETAData(
      estimatedArrivalTime: DateTime.now().add(timeRemaining),
      timeRemaining: timeRemaining,
      confidence: confidence.clamp(0.0, 1.0),
      calculationMethod: method,
      completedDistance: completedDistance,
      distanceRemaining: distanceRemaining,
      currentPace: _calculateCurrentPace(),
      averagePace: completedDistance / elapsedTime.inHours,
      elapsedTime: elapsedTime,
      elevationRemaining: _calculateElevationRemaining(),
    );
  }

  double _calculateCurrentPace() {
    // Use last 5 minutes of data for current pace
    // This is a simplified calculation - in real implementation,
    // you'd use recent location points
    final session = widget.activeSession;
    if (session.distance == null || session.elapsedTime == null) return 0.0;
    
    return session.distance! / session.elapsedTime!.inHours;
  }

  double _calculateMovingAveragePace() {
    // Use weighted average of recent pace data
    // This is simplified - real implementation would use sliding window
    final currentPace = _calculateCurrentPace();
    final session = widget.activeSession;
    final averagePace = session.distance! / session.elapsedTime!.inHours;
    
    return (currentPace * 0.7) + (averagePace * 0.3);
  }

  double _calculateAdaptivePace() {
    // Adaptive algorithm that considers terrain, fatigue, etc.
    final movingAverage = _calculateMovingAveragePace();
    final route = widget.plannedRoute;
    
    // Apply terrain adjustments if we have elevation data
    if (route?.elevationProfile.isNotEmpty == true) {
      final elevationRemaining = _calculateElevationRemaining();
      final elevationFactor = 1.0 - (elevationRemaining / 1000 * 0.1); // 10% slower per 1000ft
      return movingAverage * elevationFactor.clamp(0.5, 1.0);
    }
    
    return movingAverage;
  }

  double _calculateElevationRemaining() {
    final route = widget.plannedRoute;
    if (route?.elevationProfile.isEmpty != false) return 0.0;
    
    // This is simplified - would need current position on route
    final completedRatio = (widget.activeSession.distance ?? 0) / route!.distance;
    final totalElevationGain = route.elevationGain ?? 0;
    
    return totalElevationGain * (1.0 - completedRatio).clamp(0.0, 1.0);
  }

  double _calculateCurrentPaceConfidence() {
    // Lower confidence for current pace due to volatility
    return 0.6;
  }

  double _calculateAveragePaceConfidence() {
    // Higher confidence for average pace over longer distances
    final completedDistance = widget.activeSession.distance ?? 0;
    return (completedDistance / 5.0).clamp(0.3, 0.9); // Max confidence at 5+ miles
  }

  double _calculateMovingAverageConfidence() {
    return 0.8;
  }

  double _calculateAdaptiveConfidence() {
    return 0.85;
  }

  String _getCalculationMethodLabel() {
    switch (widget.calculationMethod) {
      case ETACalculationMethod.currentPace:
        return 'Current';
      case ETACalculationMethod.averagePace:
        return 'Average';
      case ETACalculationMethod.movingAverage:
        return 'Trending';
      case ETACalculationMethod.adaptive:
        return 'Smart';
    }
  }

  String _getMethodLabel(ETACalculationMethod method) {
    switch (method) {
      case ETACalculationMethod.currentPace:
        return 'Current Pace';
      case ETACalculationMethod.averagePace:
        return 'Average Pace';
      case ETACalculationMethod.movingAverage:
        return 'Moving Average';
      case ETACalculationMethod.adaptive:
        return 'Adaptive';
    }
  }

  Color _getETAStatusColor() {
    final confidence = _currentETA?.confidence ?? 0.0;
    if (confidence > 0.8) return AppColors.success;
    if (confidence > 0.6) return AppColors.warning;
    return AppColors.info;
  }

  String _getConfidenceLabel(double confidence) {
    if (confidence > 0.8) return 'High';
    if (confidence > 0.6) return 'Medium';
    if (confidence > 0.3) return 'Low';
    return 'Very Low';
  }

  Color _getConfidenceColor(double confidence) {
    if (confidence > 0.8) return AppColors.success;
    if (confidence > 0.6) return AppColors.warning;
    return AppColors.error;
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    
    return '$displayHour:$minute $period';
  }

  String _formatDate(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final etaDate = DateTime(dateTime.year, dateTime.month, dateTime.day);
    
    if (etaDate == today) return 'Today';
    if (etaDate == today.add(const Duration(days: 1))) return 'Tomorrow';
    
    return '${dateTime.month}/${dateTime.day}';
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }
}

enum ETACalculationMethod {
  currentPace,
  averagePace,
  movingAverage,
  adaptive,
}

class ETAData {
  final DateTime estimatedArrivalTime;
  final Duration timeRemaining;
  final double confidence;
  final ETACalculationMethod calculationMethod;
  final double completedDistance;
  final double distanceRemaining;
  final double currentPace;
  final double averagePace;
  final Duration elapsedTime;
  final double elevationRemaining;

  ETAData({
    required this.estimatedArrivalTime,
    required this.timeRemaining,
    required this.confidence,
    required this.calculationMethod,
    required this.completedDistance,
    required this.distanceRemaining,
    required this.currentPace,
    required this.averagePace,
    required this.elapsedTime,
    required this.elevationRemaining,
  });
}
