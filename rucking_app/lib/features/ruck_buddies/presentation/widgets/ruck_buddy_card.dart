import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rucking_app/core/utils/measurement_utils.dart';
import 'package:rucking_app/features/ruck_buddies/domain/entities/ruck_buddy.dart';
import 'package:rucking_app/features/ruck_buddies/domain/entities/user_info.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class RuckBuddyCard extends StatelessWidget {
  final RuckBuddy ruckBuddy;

  const RuckBuddyCard({
    Key? key,
    required this.ruckBuddy,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final authBloc = Provider.of<AuthBloc>(context, listen: false);
    final bool preferMetric = authBloc.state is Authenticated
        ? (authBloc.state as Authenticated).user.preferMetric
        : false;
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User Info Row
            Row(
              children: [
                // Avatar (fallback to circle with first letter if no URL)
                _buildAvatar(ruckBuddy.user),
                const SizedBox(width: 12),
                
                // User Name & Time Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ruckBuddy.user.username,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _formatCompletedDate(ruckBuddy.completedAt),
                        style: AppTextStyles.bodySmall.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Weight chip
                Chip(
                  backgroundColor: AppColors.secondary,
                  label: Text(
                    _formatWeight(ruckBuddy.ruckWeightKg, preferMetric),
                    style: AppTextStyles.labelMedium.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            
            const SizedBox(height: 12),

            // Map snippet
            _RouteMapPreview(ruckBuddy: ruckBuddy),

            const Divider(height: 24),
            
            // Stats Grid (2x2)
            Row(
              children: [
                // Left column
                Expanded(
                  child: Column(
                    children: [
                      _buildStatTile(
                        context: context,
                        icon: Icons.straighten, 
                        label: 'Distance',
                        value: MeasurementUtils.formatDistance(ruckBuddy.distanceKm, metric: preferMetric),
                      ),
                      const SizedBox(height: 16),
                      _buildStatTile(
                        context: context,
                        icon: Icons.local_fire_department, 
                        label: 'Calories',
                        value: '${ruckBuddy.caloriesBurned} kcal',
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(width: 24),
                
                // Right column
                Expanded(
                  child: Column(
                    children: [
                      _buildStatTile(
                        context: context,
                        icon: Icons.timer, 
                        label: 'Duration',
                        value: MeasurementUtils.formatDuration(Duration(seconds: ruckBuddy.durationSeconds)),
                      ),
                      const SizedBox(height: 16),
                      _buildStatTile(
                        context: context,
                        icon: Icons.terrain, 
                        label: 'Elevation',
                        value: '+${ruckBuddy.elevationGainM.toStringAsFixed(0)}/${ruckBuddy.elevationLossM.toStringAsFixed(0)}',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildAvatar(UserInfo user) {
    if (user.photoUrl != null && user.photoUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 20,
        backgroundImage: NetworkImage(user.photoUrl!),
      );
    } else {
      final String initial = user.username.isNotEmpty 
        ? user.username[0].toUpperCase() 
        : 'R';
      
      return CircleAvatar(
        radius: 20,
        backgroundColor: AppColors.primary,
        child: Text(
          initial,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }
  }
  
  String _formatCompletedDate(DateTime? completedAt) {
    if (completedAt == null) return 'Unknown date';
    return DateFormat.yMMMd().format(completedAt);
  }
  
  String _formatWeight(double weightKg, bool preferMetric) {
    if (preferMetric) {
      return '${weightKg.toStringAsFixed(1)} kg';
    } else {
      final double weightLbs = weightKg * 2.20462;
      return '${weightLbs.toStringAsFixed(0)} lb';
    }
  }
  
  Widget _buildStatTile({
    required BuildContext context,
    required IconData icon, 
    required String label, 
    required String value,
  }) {
    return Row(
      children: [
        Icon(
          icon, 
          size: 20, 
          color: AppColors.secondary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTextStyles.bodySmall.copyWith(
                  color: Colors.grey[600],
                ),
              ),
              Text(
                value,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RouteMapPreview extends StatelessWidget {
  final RuckBuddy ruckBuddy;
  const _RouteMapPreview({required this.ruckBuddy});

  // Convert dynamic numeric or string to double, return null if not parseable
  double? _parseCoord(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  List<LatLng> _getRoutePoints() {
    final pts = <LatLng>[];
    final lp = ruckBuddy.locationPoints;
    if (lp == null) return pts;
    for (final p in lp) {
      double? lat;
      double? lng;

      if (p is Map) {
        // attempt to handle multiple possible key names and value types
        lat = _parseCoord(p['lat']) ?? _parseCoord(p['latitude']);
        lng = _parseCoord(p['lng']) ?? _parseCoord(p['lon']) ?? _parseCoord(p['longitude']);
      } else if (p is List && p.length >= 2) {
        lat = _parseCoord(p[0]);
        lng = _parseCoord(p[1]);
      }

      if (lat != null && lng != null) {
        pts.add(LatLng(lat, lng));
      }
    }
    return pts;
  }

  LatLng _getRouteCenter(List<LatLng> points) {
    if (points.isEmpty) return LatLng(40.421, -3.678);
    double avgLat = points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length;
    double avgLng = points.map((p) => p.longitude).reduce((a, b) => a + b) / points.length;
    return LatLng(avgLat, avgLng);
  }

  double _getFitZoom(List<LatLng> points) {
    if (points.isEmpty) return 16.0;
    if (points.length == 1) return 17.5;
    double minLat = points.map((p) => p.latitude).reduce((a, b) => a < b ? a : b);
    double maxLat = points.map((p) => p.latitude).reduce((a, b) => a > b ? a : b);
    double minLng = points.map((p) => p.longitude).reduce((a, b) => a < b ? a : b);
    double maxLng = points.map((p) => p.longitude).reduce((a, b) => a > b ? a : b);
    double latDiff = (maxLat - minLat).abs();
    double lngDiff = (maxLng - minLng).abs();
    double maxDiff = latDiff > lngDiff ? latDiff : lngDiff;
    maxDiff *= 1.05;
    if (maxDiff < 0.001) return 17.5;
    if (maxDiff < 0.01) return 16.0;
    if (maxDiff < 0.1) return 14.0;
    if (maxDiff < 1.0) return 11.0;
    return 8.0;
  }

  @override
  Widget build(BuildContext context) {
    final routePoints = _getRoutePoints();
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: 175,
        width: double.infinity,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: _getRouteCenter(routePoints),
            initialZoom: _getFitZoom(routePoints),
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
          ),
          children: [
            TileLayer(
              urlTemplate: "https://tiles.stadiamaps.com/tiles/stamen_terrain/{z}/{x}/{y}{r}.png?api_key=${dotenv.env['STADIA_MAPS_API_KEY']}",
              userAgentPackageName: 'com.getrucky.gfy',
              retinaMode: MediaQuery.of(context).devicePixelRatio > 1.0,
            ),
            if (routePoints.isNotEmpty)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: routePoints,
                    color: AppColors.secondary,
                    strokeWidth: 4,
                  )
                ],
              ),
            if (routePoints.isNotEmpty)
              MarkerLayer(
                markers: [
                  // Start marker
                  Marker(
                    point: routePoints.first,
                    width: 24,
                    height: 24,
                    child: Image.asset('assets/images/map marker.png'),
                  ),
                  // End marker
                  Marker(
                    point: routePoints.last,
                    width: 24,
                    height: 24,
                    child: Image.asset('assets/images/home pin.png'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
