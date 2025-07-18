import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:rucking_app/core/models/location_point.dart';
import 'package:rucking_app/core/utils/measurement_utils.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_session.dart';
import 'package:rucking_app/features/ruck_session/domain/models/heart_rate_sample.dart';
import 'package:rucking_app/features/ruck_session/domain/models/session_split.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/map/robust_tile_layer.dart';
import 'package:rucking_app/shared/widgets/styled_snackbar.dart';

/// Screen for editing session data with timeline scrubber
class SessionEditingScreen extends StatefulWidget {
  final RuckSession originalSession;
  
  const SessionEditingScreen({
    Key? key,
    required this.originalSession,
  }) : super(key: key);
  
  @override
  State<SessionEditingScreen> createState() => _SessionEditingScreenState();
}

class _SessionEditingScreenState extends State<SessionEditingScreen> 
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  
  // Timeline scrubber state
  double _timelinePosition = 1.0; // 1.0 = end of session, 0.0 = start
  bool _isDragging = false;
  
  // Calculated session data at current timeline position
  RuckSession? _previewSession;
  List<LocationPoint> _originalLocationPoints = [];
  List<HeartRateSample> _originalHeartRateSamples = [];
  List<SessionSplit> _originalSplits = [];
  
  // Map state
  MapController? _mapController;
  
  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    
    _initializeSessionData();
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _initializeSessionData() {
    try {
      // Parse location points from the original session
      _originalLocationPoints = _parseLocationPoints(
        widget.originalSession.locationPoints ?? [],
      );
      
      // Get heart rate samples
      _originalHeartRateSamples = widget.originalSession.heartRateSamples ?? [];
      
      // Get splits
      _originalSplits = widget.originalSession.splits ?? [];
      
      // Initialize preview with original session
      _previewSession = widget.originalSession;
      
      AppLogger.info('[SESSION_EDITING] Initialized with ${_originalLocationPoints.length} location points');
    } catch (e) {
      AppLogger.error('[SESSION_EDITING] Error initializing session data', exception: e);
    }
  }

  void _updateTimelinePosition(double position) {
    print(' [SESSION_EDITING] Slider moved to position: $position');
    setState(() {
      _timelinePosition = position.clamp(0.0, 1.0);
      print(' [SESSION_EDITING] Calling _calculatePreviewSession() with timeline position: $_timelinePosition');
      _calculatePreviewSession();
    });
  }

  /// Convert raw location data to LocationPoint objects
  List<LocationPoint> _parseLocationPoints(List<dynamic> rawLocationPoints) {
    final points = <LocationPoint>[];
    
    for (final point in rawLocationPoints) {
      if (point is LocationPoint) {
        // Already a LocationPoint instance – add directly
        points.add(point);
      } else if (point is Map<String, dynamic>) {
        try {
          // Handle both Map format and already-parsed LocationPoint format
          if (point.containsKey('latitude') && point.containsKey('longitude')) {
            points.add(LocationPoint(
              latitude: (point['latitude'] as num).toDouble(),
              longitude: (point['longitude'] as num).toDouble(),
              elevation: (point['elevation'] as num?)?.toDouble() ?? 0.0,
              timestamp: point['timestamp'] is String 
                  ? DateTime.parse(point['timestamp'])
                  : point['timestamp'] as DateTime? ?? DateTime.now(),
              accuracy: (point['accuracy'] as num?)?.toDouble() ?? 0.0,
              speed: (point['speed'] as num?)?.toDouble(),
            ));
          } else if (point.containsKey('lat') && point.containsKey('lng')) {
            // Legacy format with 'lat'/'lng' keys	
            final timestampRaw = point['timestamp'] ?? point['ts'];
            DateTime ts;
            if (timestampRaw is String) {
              ts = DateTime.tryParse(timestampRaw) ?? widget.originalSession.startTime;
            } else if (timestampRaw is int) {
              // Assume milliseconds since epoch
              ts = DateTime.fromMillisecondsSinceEpoch(timestampRaw);
            } else {
              ts = widget.originalSession.startTime;
            }
            points.add(LocationPoint(
              latitude: (point['lat'] as num).toDouble(),
              longitude: (point['lng'] as num).toDouble(),
              elevation: (point['elevation'] as num?)?.toDouble() ?? 0.0,
              timestamp: ts,
              accuracy: (point['accuracy'] as num?)?.toDouble() ?? 0.0,
              speed: (point['speed'] as num?)?.toDouble(),
            ));
          }
        } catch (e) {
          AppLogger.warning('[SESSION_EDITING] Error parsing location point: $e');
          // Skip invalid points
        }
      } else if (point is LocationPoint) {
        // Already a LocationPoint object
        points.add(point);
      }
    }
    
    return points;
  }

  void _calculatePreviewSession() {
    AppLogger.debug('[SESSION_EDITING] _calculatePreviewSession called with timeline position: $_timelinePosition');
    try {
      if (_originalLocationPoints.isEmpty) {
        AppLogger.debug('[SESSION_EDITING] No original location points, using original session');
        _previewSession = widget.originalSession;
        return;
      }

      // Calculate the cutoff point based on timeline position
      final totalDuration = widget.originalSession.duration;
      final cutoffDuration = Duration(
        milliseconds: (totalDuration.inMilliseconds * _timelinePosition).round(),
      );
      final cutoffTime = widget.originalSession.startTime.add(cutoffDuration);

      // Check if location points have valid timestamps (not all the same)
      final hasValidTimestamps = _originalLocationPoints.length >= 2 &&
          !_originalLocationPoints.every((point) => 
              point.timestamp.isAtSameMomentAs(_originalLocationPoints.first.timestamp));
      
      List<LocationPoint> filteredLocationPoints;
      
      if (hasValidTimestamps) {
        // Use time-based filtering when timestamps are valid
        filteredLocationPoints = _originalLocationPoints
            .where((point) => 
                point.timestamp.isBefore(cutoffTime) || 
                point.timestamp.isAtSameMomentAs(cutoffTime))
            .toList();
        print(' [SESSION_EDITING] Using time-based filtering');
      } else {
        // Fallback: Use position-based filtering when timestamps are invalid
        int pointsToKeep;
        if (_timelinePosition >= 1.0) {
          // Ensure we keep ALL points when at the end
          pointsToKeep = _originalLocationPoints.length;
        } else {
          // Use ceiling to ensure we don't under-filter
          pointsToKeep = (_originalLocationPoints.length * _timelinePosition).ceil();
        }
        filteredLocationPoints = _originalLocationPoints.take(pointsToKeep).toList();
        print(' [SESSION_EDITING] Using position-based filtering (invalid timestamps)');
        print(' [SESSION_EDITING] Keeping ${pointsToKeep} out of ${_originalLocationPoints.length} points');
      }
        
      // Debug timestamp filtering
      print(' [SESSION_EDITING] === TIMESTAMP DEBUG ===');
      print(' [SESSION_EDITING] Session start: ${widget.originalSession.startTime}');
      print(' [SESSION_EDITING] Session end: ${widget.originalSession.endTime}');
      print(' [SESSION_EDITING] Cutoff time: $cutoffTime');
      print(' [SESSION_EDITING] Valid timestamps: $hasValidTimestamps');
      if (_originalLocationPoints.isNotEmpty) {
        print(' [SESSION_EDITING] First location point: ${_originalLocationPoints.first.timestamp}');
        print(' [SESSION_EDITING] Last location point: ${_originalLocationPoints.last.timestamp}');
        print(' [SESSION_EDITING] Cutoff is before last point: ${cutoffTime.isBefore(_originalLocationPoints.last.timestamp)}');
        print(' [SESSION_EDITING] Time diff session vs locations: ${_originalLocationPoints.first.timestamp.difference(widget.originalSession.startTime).inSeconds}s');
      }  

      AppLogger.debug('[SESSION_EDITING] Original location points: ${_originalLocationPoints.length}, Filtered: ${filteredLocationPoints.length}, Timeline pos: $_timelinePosition, Cutoff time: $cutoffTime');
      AppLogger.debug('[SESSION_EDITING] Session start: ${widget.originalSession.startTime}, Session end: ${widget.originalSession.endTime}, Total duration: ${totalDuration.inSeconds}s');
      AppLogger.debug('[SESSION_EDITING] First point timestamp: ${_originalLocationPoints.first.timestamp}, Last point timestamp: ${_originalLocationPoints.last.timestamp}');
      AppLogger.debug('[SESSION_EDITING] Cutoff duration: ${cutoffDuration.inSeconds}s, Points filtered out: ${_originalLocationPoints.length - filteredLocationPoints.length}');

      // Filter heart rate samples up to cutoff time
      final filteredHeartRateSamples = _originalHeartRateSamples
          .where((sample) => sample.timestamp.isBefore(cutoffTime) || 
                           sample.timestamp.isAtSameMomentAs(cutoffTime))
          .toList();

      // Filter splits up to cutoff time
      final filteredSplits = _originalSplits
          .where((split) => split.timestamp.isBefore(cutoffTime) || 
                          split.timestamp.isAtSameMomentAs(cutoffTime))
          .toList();

      // Recalculate session metrics
      final originalDistance = _calculateDistance(_originalLocationPoints);
      final newDistance = _calculateDistance(filteredLocationPoints);
      
      // Debug distance calculation with print statements
      print(' [SESSION_EDITING] === DISTANCE CALCULATION DEBUG ===');
      print(' [SESSION_EDITING] Timeline position: $_timelinePosition (${(_timelinePosition * 100).toStringAsFixed(1)}%)');
      print(' [SESSION_EDITING] Original points: ${_originalLocationPoints.length}, Original distance: ${originalDistance.toStringAsFixed(3)}km');
      print(' [SESSION_EDITING] Filtered points: ${filteredLocationPoints.length}, Filtered distance: ${newDistance.toStringAsFixed(3)}km');
      print(' [SESSION_EDITING] Points filtered out: ${_originalLocationPoints.length - filteredLocationPoints.length}');
      print(' [SESSION_EDITING] Expected time reduction: ${(100 - (_timelinePosition * 100)).toStringAsFixed(1)}%');
      print(' [SESSION_EDITING] Actual distance reduction: ${((originalDistance - newDistance) / originalDistance * 100).toStringAsFixed(1)}%');
      print(' [SESSION_EDITING] Distance difference: ${(originalDistance - newDistance).toStringAsFixed(3)}km');
      
      AppLogger.debug('[SESSION_EDITING] Calculated distance: ${newDistance.toStringAsFixed(3)}km from ${filteredLocationPoints.length} points');
      final newElevationGain = _calculateElevationGain(filteredLocationPoints);
      final newElevationLoss = _calculateElevationLoss(filteredLocationPoints);
      
      // Scale calories proportionally instead of recalculating
      final newCalories = (widget.originalSession.caloriesBurned * _timelinePosition).round();
      print(' [SESSION_EDITING] Calorie scaling: ${widget.originalSession.caloriesBurned} * $_timelinePosition = $newCalories');
      AppLogger.debug('[SESSION_EDITING] Calories calculation: original=${widget.originalSession.caloriesBurned}, new=${newCalories}, cutoff duration=${cutoffDuration.inMinutes}min vs original=${totalDuration.inMinutes}min');
      
      AppLogger.debug('[SESSION_EDITING] Timeline position: $_timelinePosition, Original duration: ${widget.originalSession.duration.inMinutes}min, Cutoff duration: ${cutoffDuration.inMinutes}min, Original calories: ${widget.originalSession.caloriesBurned}, New calories: $newCalories');
      final newAveragePace = _calculateAveragePace(newDistance, cutoffDuration);
      final newHeartRateStats = _calculateHeartRateStats(filteredHeartRateSamples);

      // Create preview session
      _previewSession = widget.originalSession.copyWith(
        endTime: cutoffTime,
        duration: cutoffDuration,
        distance: newDistance,
        elevationGain: newElevationGain,
        elevationLoss: newElevationLoss,
        caloriesBurned: newCalories,
        averagePace: newAveragePace,
        heartRateSamples: filteredHeartRateSamples,
        avgHeartRate: newHeartRateStats['avg'],
        maxHeartRate: newHeartRateStats['max'],
        minHeartRate: newHeartRateStats['min'],
        splits: filteredSplits,
      );

      AppLogger.debug('[SESSION_EDITING] Updated preview: ${filteredLocationPoints.length} points, ${newDistance.toStringAsFixed(2)}km');
    } catch (e) {
      AppLogger.error('[SESSION_EDITING] Error calculating preview session', exception: e);
    }
  }

  double _calculateDistance(List<LocationPoint> points) {
    if (points.length < 2) return 0.0;
    
    double totalDistance = 0.0;
    for (int i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      totalDistance += _haversineDistance(prev, curr);
    }
    return totalDistance / 1000.0; // Convert to kilometers
  }

  double _haversineDistance(LocationPoint p1, LocationPoint p2) {
    const double earthRadius = 6371000; // Earth's radius in meters
    final double lat1Rad = p1.latitude * math.pi / 180;
    final double lat2Rad = p2.latitude * math.pi / 180;
    final double deltaLatRad = (p2.latitude - p1.latitude) * math.pi / 180;
    final double deltaLonRad = (p2.longitude - p1.longitude) * math.pi / 180;

    final double a = math.sin(deltaLatRad / 2) * math.sin(deltaLatRad / 2) +
        math.cos(lat1Rad) * math.cos(lat2Rad) *
        math.sin(deltaLonRad / 2) * math.sin(deltaLonRad / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }

  double _calculateElevationGain(List<LocationPoint> points) {
    if (points.length < 2) return 0.0;
    
    double totalGain = 0.0;
    for (int i = 1; i < points.length; i++) {
      final elevationDiff = points[i].elevation - points[i - 1].elevation;
      if (elevationDiff > 0) {
        totalGain += elevationDiff;
      }
    }
    return totalGain;
  }

  double _calculateElevationLoss(List<LocationPoint> points) {
    if (points.length < 2) return 0.0;
    
    double totalLoss = 0.0;
    for (int i = 1; i < points.length; i++) {
      final elevationDiff = points[i].elevation - points[i - 1].elevation;
      if (elevationDiff < 0) {
        totalLoss += elevationDiff.abs();
      }
    }
    return totalLoss;
  }

  int _calculateCalories(Duration duration, double ruckWeightKg) {
    // Basic calorie calculation: 400 calories per hour + weight factor
    const double baseCaloriesPerHour = 400.0;
    final double weightFactor = ruckWeightKg / 20.0; // Weight factor
    final double durationHours = duration.inMilliseconds / (1000 * 60 * 60);
    return ((baseCaloriesPerHour + (weightFactor * 50)) * durationHours).round();
  }

  double _calculateAveragePace(double distanceKm, Duration duration) {
    if (distanceKm <= 0) return 0.0;
    return duration.inSeconds / distanceKm; // Seconds per km
  }

  Map<String, int?> _calculateHeartRateStats(List<HeartRateSample> samples) {
    if (samples.isEmpty) return {'avg': null, 'max': null, 'min': null};
    
    int? totalHeartRate;
    int? maxHeartRate;
    int? minHeartRate;
    
    if (samples.isNotEmpty) {
      final heartRates = samples.map((s) => s.bpm).toList();
      totalHeartRate = heartRates.reduce((a, b) => a + b);
      maxHeartRate = heartRates.reduce((a, b) => a > b ? a : b);
      minHeartRate = heartRates.reduce((a, b) => a < b ? a : b);
    }
    
    return {
      'avg': totalHeartRate != null ? (totalHeartRate / samples.length).round() : null,
      'max': maxHeartRate,
      'min': minHeartRate,
    };
  }

  void _saveEditedSession() async {
    if (_previewSession == null) return;
    
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
      
      // TODO: Implement session update API call
      // context.read<SessionBloc>().add(UpdateSession(_previewSession!));
      
      // For now, just simulate success
      await Future.delayed(const Duration(seconds: 1));
      
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        
        StyledSnackBar.showSuccess(
          context: context,
          message: 'Session updated successfully!',
          animationStyle: SnackBarAnimationStyle.slideUpBounce,
        );
        
        // Navigate back to session detail with updated session
        Navigator.of(context).pop(_previewSession);
      }
    } catch (e) {
      AppLogger.error('[SESSION_EDITING] Error saving edited session', exception: e);
      
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        
        StyledSnackBar.showError(
          context: context,
          message: 'Failed to update session: ${e.toString()}',
          animationStyle: SnackBarAnimationStyle.slideFromTop,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final preferMetric = context.read<AuthBloc>().state is Authenticated 
        ? (context.read<AuthBloc>().state as Authenticated).user.preferMetric
        : true;
    
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Edit Session'),
        backgroundColor: Colors.black,
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: _saveEditedSession,
            icon: Icon(Icons.save, color: AppColors.primary),
            label: Text(
              'Save',
              style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Column(
          children: [
            // Route map with timeline visualization
            Expanded(
              flex: 3,
              child: _buildRouteMap(),
            ),
            
            // Timeline scrubber
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.grey.shade900,
              child: _buildTimelineScrubber(),
            ),
            
            // Metrics comparison
            Expanded(
              flex: 2,
              child: _buildMetricsComparison(preferMetric),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteMap() {
    if (_originalLocationPoints.isEmpty) {
      return const Center(
        child: Text(
          'No route data available',
          style: TextStyle(color: Colors.white),
        ),
      );
    }
    
    // Calculate which points to show based on timeline position
    final cutoffIndex = (_originalLocationPoints.length * _timelinePosition).round();
    final visiblePoints = _originalLocationPoints.take(cutoffIndex).toList();
    final hiddenPoints = _originalLocationPoints.skip(cutoffIndex).toList();
    
    // Convert to LatLng for map
    final visibleLatLng = visiblePoints.map((p) => LatLng(p.latitude, p.longitude)).toList();
    final hiddenLatLng = hiddenPoints.map((p) => LatLng(p.latitude, p.longitude)).toList();
    
    // Calculate map bounds
    final allLatLng = _originalLocationPoints.map((p) => LatLng(p.latitude, p.longitude)).toList();
    final bounds = _calculateBounds(allLatLng);
    
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: bounds.center,
        initialZoom: _calculateZoom(bounds),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all,
        ),
      ),
      children: [
        SafeTileLayer(
          style: 'stamen_terrain',
          retinaMode: MediaQuery.of(context).devicePixelRatio > 1.0,
        ),
        PolylineLayer(
          polylines: [
            // Visible (kept) portion - bright orange
            if (visibleLatLng.isNotEmpty)
              Polyline(
                points: visibleLatLng,
                color: AppColors.secondary,
                strokeWidth: 6,
              ),
            // Hidden (removed) portion - dark gray
            if (hiddenLatLng.isNotEmpty)
              Polyline(
                points: hiddenLatLng,
                color: Colors.grey.shade700,
                strokeWidth: 4,
              ),
          ],
        ),
        MarkerLayer(
          markers: [
            // Start marker
            if (visibleLatLng.isNotEmpty)
              Marker(
                point: visibleLatLng.first,
                child: const Icon(
                  Icons.play_arrow,
                  color: Colors.green,
                  size: 30,
                ),
              ),
            // End marker (current timeline position)
            if (visibleLatLng.isNotEmpty)
              Marker(
                point: visibleLatLng.last,
                child: Icon(
                  Icons.stop,
                  color: AppColors.primary,
                  size: 30,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildTimelineScrubber() {
    final totalDuration = widget.originalSession.duration;
    final currentDuration = Duration(
      milliseconds: (totalDuration.inMilliseconds * _timelinePosition).round(),
    );
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Session Timeline',
              style: AppTextStyles.bodyMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Position: ${_formatDuration(currentDuration)} / ${_formatDuration(totalDuration)}',
              style: AppTextStyles.bodySmall.copyWith(color: Colors.grey.shade400),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        // Timeline slider
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppColors.primary,
            inactiveTrackColor: Colors.grey.shade700,
            thumbColor: AppColors.primary,
            overlayColor: AppColors.primary.withOpacity(0.3),
            trackHeight: 8,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
          ),
          child: Slider(
            value: _timelinePosition,
            onChanged: (value) => _updateTimelinePosition(value),
            onChangeStart: (value) => setState(() => _isDragging = true),
            onChangeEnd: (value) => setState(() => _isDragging = false),
          ),
        ),
        
        // Timeline labels
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Start',
              style: AppTextStyles.bodySmall.copyWith(color: Colors.grey.shade400),
            ),
            Text(
              'Original End',
              style: AppTextStyles.bodySmall.copyWith(color: Colors.grey.shade400),
            ),
          ],
        ),
        
        const SizedBox(height: 8),
        
        // Rewind instruction
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade800,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                color: AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Drag the slider to rewind your session. Everything after the selected point will be removed.',
                  style: AppTextStyles.bodySmall.copyWith(color: Colors.grey.shade300),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricsComparison(bool preferMetric) {
    final original = widget.originalSession;
    final preview = _previewSession ?? original;
    
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey.shade900,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Before vs After',
            style: AppTextStyles.bodyMedium.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          
          Expanded(
            child: Row(
              children: [
                // Before column
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ORIGINAL',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: Colors.grey.shade400,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildMetricRow(
                        'Distance',
                        MeasurementUtils.formatDistance(original.distance, metric: preferMetric),
                        Colors.grey.shade300,
                      ),
                      _buildMetricRow(
                        'Duration',
                        _formatDuration(original.duration),
                        Colors.grey.shade300,
                      ),
                      _buildMetricRow(
                        'Calories',
                        '${original.caloriesBurned} cal',
                        Colors.grey.shade300,
                      ),
                      _buildMetricRow(
                        'Pace',
                        MeasurementUtils.formatPace(original.averagePace, metric: preferMetric),
                        Colors.grey.shade300,
                      ),
                      _buildMetricRow(
                        'Elevation',
                        MeasurementUtils.formatSingleElevation(original.elevationGain, metric: preferMetric),
                        Colors.grey.shade300,
                      ),
                    ],
                  ),
                ),
                
                // Arrow
                Icon(
                  Icons.arrow_forward,
                  color: AppColors.primary,
                  size: 24,
                ),
                
                // After column
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'EDITED',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildMetricRow(
                        'Distance',
                        MeasurementUtils.formatDistance(preview.distance, metric: preferMetric),
                        AppColors.primary,
                      ),
                      _buildMetricRow(
                        'Duration',
                        _formatDuration(preview.duration),
                        AppColors.primary,
                      ),
                      _buildMetricRow(
                        'Calories',
                        '${preview.caloriesBurned} cal',
                        AppColors.primary,
                      ),
                      _buildMetricRow(
                        'Pace',
                        MeasurementUtils.formatPace(preview.averagePace, metric: preferMetric),
                        AppColors.primary,
                      ),
                      _buildMetricRow(
                        'Elevation',
                        MeasurementUtils.formatSingleElevation(preview.elevationGain, metric: preferMetric),
                        AppColors.primary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(color: Colors.grey.shade400),
          ),
          Text(
            value,
            style: AppTextStyles.bodySmall.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  LatLngBounds _calculateBounds(List<LatLng> points) {
    if (points.isEmpty) return LatLngBounds.fromPoints([LatLng(0, 0)]);
    
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;
    
    for (final point in points) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }
    
    return LatLngBounds.fromPoints([
      LatLng(minLat, minLng),
      LatLng(maxLat, maxLng),
    ]);
  }

  double _calculateZoom(LatLngBounds bounds) {
    final latDiff = bounds.northWest.latitude - bounds.southEast.latitude;
    final lngDiff = bounds.southEast.longitude - bounds.northWest.longitude;
    final maxDiff = math.max(latDiff, lngDiff);
    
    if (maxDiff > 0.5) return 10.0;
    if (maxDiff > 0.1) return 12.0;
    if (maxDiff > 0.05) return 13.0;
    if (maxDiff > 0.01) return 14.0;
    if (maxDiff > 0.005) return 15.0;
    return 16.0;
  }
}
