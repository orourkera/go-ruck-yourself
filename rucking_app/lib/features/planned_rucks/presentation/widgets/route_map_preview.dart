import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:rucking_app/core/models/route.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

/// Interactive map widget showing route preview with optional controls
class RouteMapPreview extends StatefulWidget {
  final Route route;
  final bool isInteractive;
  final bool showControls;
  final bool isHeroImage;
  final bool showOverlay;
  final double? height;
  final VoidCallback? onTap;

  const RouteMapPreview({
    super.key,
    required this.route,
    this.isInteractive = false,
    this.showControls = false,
    this.isHeroImage = false,
    this.showOverlay = false,
    this.height,
    this.onTap,
  });

  @override
  State<RouteMapPreview> createState() => _RouteMapPreviewState();
}

class _RouteMapPreviewState extends State<RouteMapPreview>
    with TickerProviderStateMixin {
  late MapController _mapController;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  
  bool _isLoading = true;
  int _selectedWaypointIndex = -1;
  MapViewType _currentViewType = MapViewType.standard;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    
    // Simulate loading delay and start animation
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
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
    return Container(
      height: widget.height ?? (widget.isHeroImage ? double.infinity : 300),
      decoration: BoxDecoration(
        borderRadius: widget.isHeroImage 
            ? null 
            : BorderRadius.circular(12),
        boxShadow: widget.isHeroImage
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: widget.isHeroImage 
            ? BorderRadius.zero 
            : BorderRadius.circular(12),
        child: Stack(
          children: [
            // Map content
            _isLoading ? _buildLoadingMap() : _buildMap(),
            
            // Loading overlay
            if (_isLoading) _buildLoadingOverlay(),
            
            // Map controls
            if (widget.showControls && !_isLoading) _buildMapControls(),
            
            // Info overlay
            if (widget.showOverlay && !widget.isHeroImage) _buildInfoOverlay(),
            
            // Tap overlay for non-interactive maps
            if (!widget.isInteractive && widget.onTap != null)
              Positioned.fill(
                child: GestureDetector(
                  onTap: widget.onTap,
                  child: Container(
                    color: Colors.transparent,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          center: _getRouteCenter(),
          zoom: _getOptimalZoom(),
          interactiveFlags: widget.isInteractive 
              ? InteractiveFlag.all 
              : InteractiveFlag.none,
          onTap: widget.onTap != null 
              ? (_, __) => widget.onTap!() 
              : null,
          minZoom: 8,
          maxZoom: 18,
        ),
        children: [
          // Base map layer
          TileLayer(
            urlTemplate: _getMapTileUrl(),
            userAgentPackageName: 'com.example.rucking_app',
            tileSize: 256,
            maxZoom: 18,
          ),
          
          // Route polyline
          PolylineLayer(
            polylines: [
              Polyline(
                points: widget.route.waypoints.map((w) => LatLng(w.latitude, w.longitude)).toList(),
                strokeWidth: 4.0,
                color: AppColors.primary,
                borderColor: Colors.white,
                borderStrokeWidth: 2.0,
                pattern: StrokePattern.solid,
              ),
            ],
          ),
          
          // Start/End markers
          MarkerLayer(
            markers: _buildRouteMarkers(),
          ),
          
          // Points of Interest markers
          if (widget.route.pointsOfInterest.isNotEmpty)
            MarkerLayer(
              markers: _buildPOIMarkers(),
            ),
          
          // Waypoint markers (for interactive mode)
          if (widget.isInteractive && _selectedWaypointIndex >= 0)
            MarkerLayer(
              markers: [_buildSelectedWaypointMarker()],
            ),
        ],
      ),
    );
  }

  Widget _buildLoadingMap() {
    return Container(
      color: AppColors.surface,
      child: Stack(
        children: [
          // Shimmer effect for map loading
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.primary.withOpacity(0.1),
                  AppColors.primary.withOpacity(0.05),
                  AppColors.primary.withOpacity(0.1),
                ],
              ),
            ),
          ),
          
          // Loading route placeholder
          Center(
            child: Container(
              width: 200,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.3),
      child: const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      ),
    );
  }

  Widget _buildMapControls() {
    return Positioned(
      top: 16,
      right: 16,
      child: Column(
        children: [
          // Map type toggle
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
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
          
          // Zoom controls
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                IconButton(
                  onPressed: () {
                    _mapController.move(
                      _mapController.center,
                      _mapController.zoom + 1,
                    );
                  },
                  icon: const Icon(Icons.add),
                  color: AppColors.primary,
                ),
                Container(
                  height: 1,
                  color: AppColors.divider,
                ),
                IconButton(
                  onPressed: () {
                    _mapController.move(
                      _mapController.center,
                      _mapController.zoom - 1,
                    );
                  },
                  icon: const Icon(Icons.remove),
                  color: AppColors.primary,
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 8),
          
          // Fit bounds button
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
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
              onPressed: _fitRouteBounds,
              icon: const Icon(Icons.center_focus_strong),
              color: AppColors.primary,
              tooltip: 'Fit route to view',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoOverlay() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withOpacity(0.8),
              Colors.black.withOpacity(0.4),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.route.name,
                    style: AppTextStyles.subtitle1.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.straighten,
                        size: 14,
                        color: Colors.white.withOpacity(0.8),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.route.formattedDistance,
                        style: AppTextStyles.caption.copyWith(
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                      if (widget.route.elevationGain != null) ...[
                        const SizedBox(width: 12),
                        Icon(
                          Icons.trending_up,
                          size: 14,
                          color: Colors.white.withOpacity(0.8),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          widget.route.formattedElevationGain,
                          style: AppTextStyles.caption.copyWith(
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            
            if (widget.onTap != null)
              Icon(
                Icons.open_in_full,
                color: Colors.white.withOpacity(0.8),
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  List<Marker> _buildRouteMarkers() {
    if (widget.route.waypoints.isEmpty) return [];
    
    final waypoints = widget.route.waypoints;
    final markers = <Marker>[];
    
    // Start marker
    markers.add(
      Marker(
        point: LatLng(waypoints.first.latitude, waypoints.first.longitude),
        builder: (context) => _buildRoutePointMarker(
          icon: Icons.play_arrow,
          color: AppColors.success,
          label: 'Start',
        ),
      ),
    );
    
    // End marker (if different from start)
    if (waypoints.length > 1) {
      final lastPoint = waypoints.last;
      final firstPoint = waypoints.first;
      
      if (lastPoint.latitude != firstPoint.latitude || 
          lastPoint.longitude != firstPoint.longitude) {
        markers.add(
          Marker(
            point: LatLng(lastPoint.latitude, lastPoint.longitude),
            builder: (context) => _buildRoutePointMarker(
              icon: Icons.flag,
              color: AppColors.error,
              label: 'End',
            ),
          ),
        );
      }
    }
    
    return markers;
  }

  List<Marker> _buildPOIMarkers() {
    return widget.route.pointsOfInterest.map((poi) {
      return Marker(
        point: LatLng(poi.latitude, poi.longitude),
        builder: (context) => GestureDetector(
          onTap: () {
            _showPOIDetails(poi);
          },
          child: _buildPOIMarker(poi),
        ),
      );
    }).toList();
  }

  Marker _buildSelectedWaypointMarker() {
    final waypoint = widget.route.waypoints[_selectedWaypointIndex];
    return Marker(
      point: LatLng(waypoint.latitude, waypoint.longitude),
      builder: (context) => _buildRoutePointMarker(
        icon: Icons.location_on,
        color: AppColors.warning,
        label: 'Selected',
        isSelected: true,
      ),
    );
  }

  Widget _buildRoutePointMarker({
    required IconData icon,
    required Color color,
    required String label,
    bool isSelected = false,
  }) {
    return Container(
      width: isSelected ? 40 : 32,
      height: isSelected ? 40 : 32,
      decoration: BoxDecoration(
        color: color,
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
      child: Icon(
        icon,
        color: Colors.white,
        size: isSelected ? 24 : 18,
      ),
    );
  }

  Widget _buildPOIMarker(PointOfInterest poi) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: AppColors.info,
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white,
          width: 2,
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
        _getPOIIcon(poi.type),
        color: Colors.white,
        size: 14,
      ),
    );
  }

  // Helper methods

  LatLng _getRouteCenter() {
    if (widget.route.waypoints.isEmpty) {
      return const LatLng(37.7749, -122.4194); // Default to SF
    }
    
    final waypoints = widget.route.waypoints;
    double totalLat = 0;
    double totalLng = 0;
    
    for (final waypoint in waypoints) {
      totalLat += waypoint.latitude;
      totalLng += waypoint.longitude;
    }
    
    return LatLng(
      totalLat / waypoints.length,
      totalLng / waypoints.length,
    );
  }

  double _getOptimalZoom() {
    if (widget.route.waypoints.length < 2) return 14.0;
    
    // Calculate bounds and determine appropriate zoom level
    final waypoints = widget.route.waypoints;
    double minLat = waypoints.first.latitude;
    double maxLat = waypoints.first.latitude;
    double minLng = waypoints.first.longitude;
    double maxLng = waypoints.first.longitude;
    
    for (final waypoint in waypoints) {
      minLat = minLat < waypoint.latitude ? minLat : waypoint.latitude;
      maxLat = maxLat > waypoint.latitude ? maxLat : waypoint.latitude;
      minLng = minLng < waypoint.longitude ? minLng : waypoint.longitude;
      maxLng = maxLng > waypoint.longitude ? maxLng : waypoint.longitude;
    }
    
    final latDiff = maxLat - minLat;
    final lngDiff = maxLng - minLng;
    final maxDiff = latDiff > lngDiff ? latDiff : lngDiff;
    
    if (maxDiff > 0.1) return 10.0;
    if (maxDiff > 0.05) return 12.0;
    if (maxDiff > 0.01) return 14.0;
    return 16.0;
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

  IconData _getPOIIcon(String type) {
    switch (type.toLowerCase()) {
      case 'water':
        return Icons.water_drop;
      case 'restroom':
        return Icons.wc;
      case 'viewpoint':
        return Icons.visibility;
      case 'parking':
        return Icons.local_parking;
      default:
        return Icons.place;
    }
  }

  void _fitRouteBounds() {
    if (widget.route.waypoints.isEmpty) return;
    
    final waypoints = widget.route.waypoints;
    double minLat = waypoints.first.latitude;
    double maxLat = waypoints.first.latitude;
    double minLng = waypoints.first.longitude;
    double maxLng = waypoints.first.longitude;
    
    for (final waypoint in waypoints) {
      minLat = minLat < waypoint.latitude ? minLat : waypoint.latitude;
      maxLat = maxLat > waypoint.latitude ? maxLat : waypoint.latitude;
      minLng = minLng < waypoint.longitude ? minLng : waypoint.longitude;
      maxLng = maxLng > waypoint.longitude ? maxLng : waypoint.longitude;
    }
    
    _mapController.fitBounds(
      LatLngBounds(
        LatLng(minLat, minLng),
        LatLng(maxLat, maxLng),
      ),
      options: const FitBoundsOptions(
        padding: EdgeInsets.all(50),
      ),
    );
  }

  void _showPOIDetails(PointOfInterest poi) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(poi.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_getPOIIcon(poi.type), size: 16),
                const SizedBox(width: 8),
                Text(poi.type.toUpperCase()),
              ],
            ),
            if (poi.description?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(poi.description!),
            ],
            if (poi.distance != null) ...[
              const SizedBox(height: 8),
              Text('${poi.distance!.toStringAsFixed(1)} miles from start'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

enum MapViewType {
  standard,
  satellite,
  terrain,
}
