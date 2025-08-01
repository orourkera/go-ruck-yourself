import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:rucking_app/core/models/route.dart' as route_model;
import 'package:rucking_app/core/models/route_point_of_interest.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/map/robust_tile_layer.dart';

/// Interactive map widget showing route preview with optional controls
class RouteMapPreview extends StatefulWidget {
  final route_model.Route route;
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
          initialCenter: _getRouteCenter(),
          initialZoom: _getOptimalZoom(),
          interactionOptions: InteractionOptions(
            flags: widget.isInteractive 
                ? InteractiveFlag.all 
                : InteractiveFlag.none,
          ),
          onTap: widget.onTap != null 
              ? (_, __) => widget.onTap!() 
              : null,
          minZoom: 8,
          maxZoom: 18,
        ),
        children: [
          // Base map layer
          SafeTileLayer(
            style: _getMapStyle(),
            retinaMode: false,
          ),
          
          // Route polyline
          PolylineLayer(
            polylines: [
              Polyline(
                points: _getRoutePoints(),
                strokeWidth: 4.0,
                color: AppColors.primary,
                borderColor: Colors.white,
                borderStrokeWidth: 2.0,
                pattern: const StrokePattern.solid(),
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
      color: AppColors.backgroundLight,
      child: Stack(
        children: [
          // Shimmer effect for map loading
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.textDarkSecondary.withOpacity(0.1),
                  AppColors.textDarkSecondary.withOpacity(0.05),
                  AppColors.textDarkSecondary.withOpacity(0.1),
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
                color: AppColors.textDarkSecondary.withOpacity(0.3),
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
                      _mapController.camera.center,
                      _mapController.camera.zoom + 1,
                    );
                  },
                  icon: const Icon(Icons.add),
                  color: AppColors.primary,
                ),
                Container(
                  height: 1,
                  color: AppColors.greyLight,
                ),
                IconButton(
                  onPressed: () {
                    _mapController.move(
                      _mapController.camera.center,
                      _mapController.camera.zoom - 1,
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
              color: AppColors.textDarkSecondary,
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
                    style: AppTextStyles.titleMedium.copyWith(
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
                        style: AppTextStyles.bodySmall.copyWith(
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                      if (widget.route.elevationGainM != null) ...[
                        const SizedBox(width: 12),
                        Icon(
                          Icons.trending_up,
                          size: 14,
                          color: Colors.white.withOpacity(0.8),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          widget.route.formattedElevationGain,
                          style: AppTextStyles.bodySmall.copyWith(
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
    final points = _getRoutePoints();
    if (points.isEmpty) return [];
    
    final markers = <Marker>[];
    
    // Start marker
    markers.add(
      Marker(
        point: points.first,
        width: 32,
        height: 32,
        child: _buildRoutePointMarker(
          icon: Icons.play_arrow,
          color: AppColors.success,
          label: 'Start',
        ),
      ),
    );
    
    // End marker (if different from start)
    if (points.length > 1) {
      final lastPoint = points.last;
      final firstPoint = points.first;
      
      if (lastPoint.latitude != firstPoint.latitude || 
          lastPoint.longitude != firstPoint.longitude) {
        markers.add(
          Marker(
            point: lastPoint,
            width: 32,
            height: 32,
            child: _buildRoutePointMarker(
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
        width: 24,
        height: 24,
        child: GestureDetector(
          onTap: () {
            _showPOIDetails(poi);
          },
          child: _buildPOIMarker(poi),
        ),
      );
    }).toList();
  }

  Marker _buildSelectedWaypointMarker() {
    final points = _getRoutePoints();
    if (_selectedWaypointIndex >= points.length) return Marker(point: points.first, child: Container());
    
    return Marker(
      point: points[_selectedWaypointIndex],
      width: 32,
      height: 32,
      child: _buildRoutePointMarker(
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

  Widget _buildPOIMarker(RoutePointOfInterest poi) {
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
        _getPOIIcon(poi.poiType),
        color: Colors.white,
        size: 14,
      ),
    );
  }

  // Helper methods

  List<LatLng> _getRoutePoints() {
    // First try to decode the route polyline if available
    if (widget.route.routePolyline?.isNotEmpty == true) {
      try {
        final polylinePoints = <LatLng>[];
        final coordinates = widget.route.routePolyline!.split(';');
        
        for (final coord in coordinates) {
          final parts = coord.trim().split(',');
          if (parts.length == 2) {
            final lat = double.tryParse(parts[0]);
            final lng = double.tryParse(parts[1]);
            if (lat != null && lng != null) {
              polylinePoints.add(LatLng(lat, lng));
            }
          }
        }
        
        if (polylinePoints.isNotEmpty) {
          return polylinePoints;
        }
      } catch (e) {
        // If polyline parsing fails, fall back to basic points
        // Log the error but don't crash
        debugPrint('Error parsing route polyline: $e');
      }
    }
    
    // Fallback: Create basic route points from start/end coordinates
    final points = <LatLng>[
      LatLng(widget.route.startLatitude, widget.route.startLongitude),
    ];
    
    // Add any elevation points if available
    if (widget.route.elevationPoints.isNotEmpty) {
      for (final point in widget.route.elevationPoints) {
        if (point.latitude != null && point.longitude != null) {
          points.add(LatLng(point.latitude!, point.longitude!));
        }
      }
    }
    
    // Add end point if different from start
    if (widget.route.endLatitude != null && widget.route.endLongitude != null) {
      final endPoint = LatLng(widget.route.endLatitude!, widget.route.endLongitude!);
      if (points.isEmpty || points.last != endPoint) {
        points.add(endPoint);
      }
    }
    
    return points;
  }

  LatLng _getRouteCenter() {
    final points = _getRoutePoints();
    if (points.isEmpty) {
      return const LatLng(37.7749, -122.4194); // Default to SF
    }
    
    double totalLat = 0;
    double totalLng = 0;
    
    for (final point in points) {
      totalLat += point.latitude;
      totalLng += point.longitude;
    }
    
    return LatLng(
      totalLat / points.length,
      totalLng / points.length,
    );
  }

  double _getOptimalZoom() {
    final points = _getRoutePoints();
    if (points.length < 2) return 14.0;
    
    // Calculate bounds and determine appropriate zoom level
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;
    
    for (final point in points) {
      minLat = minLat < point.latitude ? minLat : point.latitude;
      maxLat = maxLat > point.latitude ? maxLat : point.latitude;
      minLng = minLng < point.longitude ? minLng : point.longitude;
      maxLng = maxLng > point.longitude ? maxLng : point.longitude;
    }
    
    final latDiff = maxLat - minLat;
    final lngDiff = maxLng - minLng;
    final maxDiff = latDiff > lngDiff ? latDiff : lngDiff;
    
    if (maxDiff > 0.1) return 10.0;
    if (maxDiff > 0.05) return 12.0;
    if (maxDiff > 0.01) return 14.0;
    return 16.0;
  }

  String _getMapStyle() {
    switch (_currentViewType) {
      case MapViewType.satellite:
        return 'alidade_satellite';
      case MapViewType.terrain:
        return 'stamen_terrain';
      default:
        return 'osm_bright';
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
    final points = _getRoutePoints();
    if (points.isEmpty) return;
    
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;
    
    for (final point in points) {
      minLat = minLat < point.latitude ? minLat : point.latitude;
      maxLat = maxLat > point.latitude ? maxLat : point.latitude;
      minLng = minLng < point.longitude ? minLng : point.longitude;
      maxLng = maxLng > point.longitude ? maxLng : point.longitude;
    }
    
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(
          LatLng(minLat, minLng),
          LatLng(maxLat, maxLng),
        ),
        padding: const EdgeInsets.all(50),
      ),
    );
  }

  void _showPOIDetails(RoutePointOfInterest poi) {
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
                Icon(_getPOIIcon(poi.poiType), size: 16),
                const SizedBox(width: 8),
                Text(poi.poiType.toUpperCase()),
              ],
            ),
            if (poi.description?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(poi.description!),
            ],
            if (poi.distanceFromStartKm > 0) ...[
              const SizedBox(height: 8),
              Text('${poi.distanceFromStartKm.toStringAsFixed(1)} km from start'),
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
