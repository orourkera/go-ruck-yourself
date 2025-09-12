import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:rucking_app/core/models/ruck_session.dart';
import 'package:rucking_app/core/models/route.dart';
import 'package:rucking_app/core/models/location_point.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/map/robust_tile_layer.dart';

/// Interactive map overlay for active rucking sessions with real-time tracking
class ActiveSessionMapOverlay extends StatefulWidget {
  final RuckSession activeSession;
  final Route? plannedRoute;
  final LatLng? currentLocation;
  final List<LocationPoint> sessionTrack;
  final bool showPlannedRoute;
  final bool showSessionTrack;
  final bool showCurrentLocation;
  final bool showProgressMarkers;
  final bool followLocation;
  final VoidCallback? onRecenterPressed;
  final VoidCallback? onToggleFollowPressed;

  const ActiveSessionMapOverlay({
    super.key,
    required this.activeSession,
    this.plannedRoute,
    this.currentLocation,
    this.sessionTrack = const [],
    this.showPlannedRoute = true,
    this.showSessionTrack = true,
    this.showCurrentLocation = true,
    this.showProgressMarkers = true,
    this.followLocation = true,
    this.onRecenterPressed,
    this.onToggleFollowPressed,
  });

  @override
  State<ActiveSessionMapOverlay> createState() =>
      _ActiveSessionMapOverlayState();
}

class _ActiveSessionMapOverlayState extends State<ActiveSessionMapOverlay>
    with SingleTickerProviderStateMixin {
  late MapController _mapController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  bool _isFollowingLocation = true;
  MapViewType _currentViewType = MapViewType.standard;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _isFollowingLocation = widget.followLocation;

    // Setup pulse animation for current location
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ActiveSessionMapOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Auto-follow location if enabled and location changed
    if (_isFollowingLocation &&
        widget.currentLocation != null &&
        widget.currentLocation != oldWidget.currentLocation) {
      _centerOnLocation(widget.currentLocation!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Main map
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            center: _getInitialCenter(),
            zoom: 16.0,
            minZoom: 8.0,
            maxZoom: 18.0,
            interactiveFlags: InteractiveFlag.all,
            onMapEvent: _handleMapEvent,
          ),
          children: [
            // Base map layer
            SafeTileLayer(
              style: 'stamen_terrain',
            ),

            // Planned route polyline (if available)
            if (widget.showPlannedRoute && widget.plannedRoute != null)
              PolylineLayer(
                polylines: [_buildPlannedRoutePolyline()],
              ),

            // Session track polyline
            if (widget.showSessionTrack && widget.sessionTrack.isNotEmpty)
              PolylineLayer(
                polylines: [_buildSessionTrackPolyline()],
              ),

            // Progress markers
            if (widget.showProgressMarkers)
              MarkerLayer(
                markers: _buildProgressMarkers(),
              ),

            // Current location marker
            if (widget.showCurrentLocation && widget.currentLocation != null)
              MarkerLayer(
                markers: [_buildCurrentLocationMarker()],
              ),
          ],
        ),

        // Map controls overlay
        _buildMapControls(),

        // Progress overlay
        _buildProgressOverlay(),

        // Quick stats overlay
        _buildQuickStatsOverlay(),
      ],
    );
  }

  Widget _buildMapControls() {
    return Positioned(
      top: 16,
      right: 16,
      child: Column(
        children: [
          // Map type selector
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: PopupMenuButton<MapViewType>(
              icon: Icon(
                _getMapTypeIcon(),
                color: AppColors.primary,
              ),
              onSelected: (type) {
                setState(() {
                  _currentViewType = type;
                });
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: MapViewType.standard,
                  child: Row(
                    children: [
                      Icon(Icons.map),
                      SizedBox(width: 8),
                      Text('Standard'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: MapViewType.satellite,
                  child: Row(
                    children: [
                      Icon(Icons.satellite),
                      SizedBox(width: 8),
                      Text('Satellite'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: MapViewType.terrain,
                  child: Row(
                    children: [
                      Icon(Icons.terrain),
                      SizedBox(width: 8),
                      Text('Terrain'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Follow location toggle
          Container(
            decoration: BoxDecoration(
              color: _isFollowingLocation
                  ? AppColors.primary.withOpacity(0.9)
                  : Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              onPressed: _toggleFollowLocation,
              icon: Icon(
                _isFollowingLocation ? Icons.gps_fixed : Icons.gps_not_fixed,
                color: _isFollowingLocation ? Colors.white : AppColors.primary,
              ),
              tooltip:
                  _isFollowingLocation ? 'Stop following' : 'Follow location',
            ),
          ),

          const SizedBox(height: 8),

          // Recenter button
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              onPressed: _recenterMap,
              icon: Icon(
                Icons.my_location,
                color: AppColors.primary,
              ),
              tooltip: 'Recenter map',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressOverlay() {
    final progress = _calculateRouteProgress();

    return Positioned(
      top: 16,
      left: 16,
      right: 100,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.95),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Progress bar
            Row(
              children: [
                Icon(
                  Icons.route,
                  size: 16,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: LinearProgressIndicator(
                    value: progress.percentage,
                    backgroundColor: AppColors.divider,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _getProgressColor(progress.percentage),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(progress.percentage * 100).toInt()}%',
                  style: AppTextStyles.caption.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Progress details
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Distance: ${progress.completedDistance.toStringAsFixed(2)} / ${progress.totalDistance.toStringAsFixed(2)} mi',
                    style: AppTextStyles.caption,
                  ),
                ),
                if (progress.remainingDistance > 0)
                  Text(
                    '${progress.remainingDistance.toStringAsFixed(2)} mi left',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStatsOverlay() {
    return Positioned(
      bottom: 16,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.95),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Duration
            Expanded(
              child: _buildStatItem(
                'Duration',
                _formatDuration(
                    widget.activeSession.elapsedTime ?? Duration.zero),
                Icons.access_time,
                AppColors.primary,
              ),
            ),

            Container(width: 1, height: 40, color: AppColors.divider),

            // Distance
            Expanded(
              child: _buildStatItem(
                'Distance',
                '${widget.activeSession.distance?.toStringAsFixed(2) ?? '0.00'} mi',
                Icons.straighten,
                AppColors.success,
              ),
            ),

            Container(width: 1, height: 40, color: AppColors.divider),

            // Current pace
            Expanded(
              child: _buildStatItem(
                'Pace',
                _calculateCurrentPace(),
                Icons.speed,
                AppColors.info,
              ),
            ),

            if (widget.activeSession.elevationGain != null) ...[
              Container(width: 1, height: 40, color: AppColors.divider),

              // Elevation gain
              Expanded(
                child: _buildStatItem(
                  'Elevation',
                  '${widget.activeSession.elevationGain!.toInt()} ft',
                  Icons.trending_up,
                  AppColors.warning,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(
      String label, String value, IconData icon, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
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
          textAlign: TextAlign.center,
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

  // Map layers

  Polyline _buildPlannedRoutePolyline() {
    return Polyline(
      points: widget.plannedRoute!.waypoints
          .map((w) => LatLng(w.latitude, w.longitude))
          .toList(),
      strokeWidth: 3.0,
      color: AppColors.primary.withOpacity(0.6),
      borderColor: Colors.white.withOpacity(0.8),
      borderStrokeWidth: 1.0,
      pattern: StrokePattern.dashed,
    );
  }

  Polyline _buildSessionTrackPolyline() {
    return Polyline(
      points: widget.sessionTrack
          .map((point) => LatLng(point.latitude, point.longitude))
          .toList(),
      strokeWidth: 4.0,
      color: AppColors.success,
      borderColor: Colors.white,
      borderStrokeWidth: 2.0,
      pattern: StrokePattern.solid,
    );
  }

  List<Marker> _buildProgressMarkers() {
    final markers = <Marker>[];

    // Add start marker if we have session track
    if (widget.sessionTrack.isNotEmpty) {
      final startPoint = widget.sessionTrack.first;
      markers.add(
        Marker(
          point: LatLng(startPoint.latitude, startPoint.longitude),
          builder: (context) => _buildProgressMarker(
            icon: Icons.play_arrow,
            color: AppColors.success,
            label: 'Start',
          ),
        ),
      );
    }

    // Add milestone markers every mile
    if (widget.plannedRoute != null) {
      final route = widget.plannedRoute!;
      final totalDistance = route.distance;

      for (int mile = 1; mile < totalDistance.floor(); mile++) {
        final waypoint = _findWaypointAtDistance(route, mile.toDouble());
        if (waypoint != null) {
          markers.add(
            Marker(
              point: LatLng(waypoint.latitude, waypoint.longitude),
              builder: (context) => _buildProgressMarker(
                icon: Icons.flag_outlined,
                color: AppColors.info,
                label: '${mile}mi',
                isSmall: true,
              ),
            ),
          );
        }
      }
    }

    return markers;
  }

  Marker _buildCurrentLocationMarker() {
    return Marker(
      point: widget.currentLocation!,
      builder: (context) => AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              // Pulse effect
              Container(
                width: 40 + (_pulseAnimation.value * 20),
                height: 40 + (_pulseAnimation.value * 20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withOpacity(
                    0.3 * (1 - _pulseAnimation.value),
                  ),
                ),
              ),

              // Main location marker
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white,
                    width: 3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.navigation,
                  color: Colors.white,
                  size: 14,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProgressMarker({
    required IconData icon,
    required Color color,
    required String label,
    bool isSmall = false,
  }) {
    final size = isSmall ? 24.0 : 32.0;
    final iconSize = isSmall ? 14.0 : 18.0;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white,
          width: isSmall ? 2 : 3,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Icon(
        icon,
        color: Colors.white,
        size: iconSize,
      ),
    );
  }

  // Helper methods

  LatLng _getInitialCenter() {
    if (widget.currentLocation != null) {
      return widget.currentLocation!;
    }

    if (widget.sessionTrack.isNotEmpty) {
      final lastPoint = widget.sessionTrack.last;
      return LatLng(lastPoint.latitude, lastPoint.longitude);
    }

    if (widget.plannedRoute?.waypoints.isNotEmpty == true) {
      final firstWaypoint = widget.plannedRoute!.waypoints.first;
      return LatLng(firstWaypoint.latitude, firstWaypoint.longitude);
    }

    return const LatLng(37.7749, -122.4194); // Default to SF
  }

  String _getMapTileUrl() {
    switch (_currentViewType) {
      case MapViewType.satellite:
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
      case MapViewType.terrain:
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/tile/{z}/{y}/{x}';
      default:
        return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    }
  }

  IconData _getMapTypeIcon() {
    switch (_currentViewType) {
      case MapViewType.satellite:
        return Icons.satellite;
      case MapViewType.terrain:
        return Icons.terrain;
      default:
        return Icons.map;
    }
  }

  RouteProgress _calculateRouteProgress() {
    if (widget.plannedRoute == null) {
      return RouteProgress(
        percentage: 0.0,
        completedDistance: widget.activeSession.distance ?? 0.0,
        totalDistance: widget.activeSession.distance ?? 0.0,
        remainingDistance: 0.0,
      );
    }

    final totalDistance = widget.plannedRoute!.distance;
    final completedDistance = widget.activeSession.distance ?? 0.0;
    final percentage =
        totalDistance > 0 ? completedDistance / totalDistance : 0.0;

    return RouteProgress(
      percentage: percentage.clamp(0.0, 1.0),
      completedDistance: completedDistance,
      totalDistance: totalDistance,
      remainingDistance:
          (totalDistance - completedDistance).clamp(0.0, totalDistance),
    );
  }

  Color _getProgressColor(double percentage) {
    if (percentage < 0.33) return AppColors.success;
    if (percentage < 0.66) return AppColors.warning;
    return AppColors.primary;
  }

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
    final distance = widget.activeSession.distance ?? 0.0;
    final duration = widget.activeSession.elapsedTime ?? Duration.zero;

    if (distance <= 0 || duration.inSeconds <= 0) {
      return '--:-- /mi';
    }

    final paceSeconds = duration.inSeconds / distance;
    final paceMinutes = (paceSeconds / 60).floor();
    final remainSeconds = (paceSeconds % 60).floor();

    return '${paceMinutes}:${remainSeconds.toString().padLeft(2, '0')} /mi';
  }

  RouteWaypoint? _findWaypointAtDistance(Route route, double targetDistance) {
    double accumulatedDistance = 0.0;

    for (int i = 1; i < route.waypoints.length; i++) {
      final prevWaypoint = route.waypoints[i - 1];
      final currentWaypoint = route.waypoints[i];

      final segmentDistance = _calculateDistance(
        prevWaypoint.latitude,
        prevWaypoint.longitude,
        currentWaypoint.latitude,
        currentWaypoint.longitude,
      );

      if (accumulatedDistance + segmentDistance >= targetDistance) {
        // Interpolate position
        final remainingDistance = targetDistance - accumulatedDistance;
        final ratio = remainingDistance / segmentDistance;

        final lat = prevWaypoint.latitude +
            (currentWaypoint.latitude - prevWaypoint.latitude) * ratio;
        final lng = prevWaypoint.longitude +
            (currentWaypoint.longitude - prevWaypoint.longitude) * ratio;

        return RouteWaypoint(
          latitude: lat,
          longitude: lng,
          elevation: prevWaypoint.elevation,
          distance: targetDistance,
        );
      }

      accumulatedDistance += segmentDistance;
    }

    return null;
  }

  double _calculateDistance(
      double lat1, double lng1, double lat2, double lng2) {
    // Haversine formula for distance calculation
    const distance = Distance();
    return distance.as(LengthUnit.Mile, LatLng(lat1, lng1), LatLng(lat2, lng2));
  }

  void _centerOnLocation(LatLng location) {
    _mapController.move(location, _mapController.zoom);
  }

  void _toggleFollowLocation() {
    setState(() {
      _isFollowingLocation = !_isFollowingLocation;
    });

    if (widget.onToggleFollowPressed != null) {
      widget.onToggleFollowPressed!();
    }

    if (_isFollowingLocation && widget.currentLocation != null) {
      _centerOnLocation(widget.currentLocation!);
    }
  }

  void _recenterMap() {
    if (widget.currentLocation != null) {
      _centerOnLocation(widget.currentLocation!);
      setState(() {
        _isFollowingLocation = true;
      });
    }

    if (widget.onRecenterPressed != null) {
      widget.onRecenterPressed!();
    }
  }

  void _handleMapEvent(MapEvent event) {
    // Stop following location if user manually moves the map
    if (event is MapEventMove && _isFollowingLocation) {
      setState(() {
        _isFollowingLocation = false;
      });
    }
  }
}

enum MapViewType {
  standard,
  satellite,
  terrain,
}

class RouteProgress {
  final double percentage;
  final double completedDistance;
  final double totalDistance;
  final double remainingDistance;

  RouteProgress({
    required this.percentage,
    required this.completedDistance,
    required this.totalDistance,
    required this.remainingDistance,
  });
}
