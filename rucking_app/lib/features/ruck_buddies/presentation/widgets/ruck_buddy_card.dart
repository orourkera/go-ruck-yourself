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
import 'package:cached_network_image/cached_network_image.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_photo.dart';

class RuckBuddyCard extends StatelessWidget {
  final RuckBuddy ruckBuddy;
  final Function()? onTap;
  final Function()? onLikeTap;

  const RuckBuddyCard({
    Key? key,
    required this.ruckBuddy,
    this.onTap,
    this.onLikeTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final authBloc = Provider.of<AuthBloc>(context, listen: false);
    final bool preferMetric = authBloc.state is Authenticated
        ? (authBloc.state as Authenticated).user.preferMetric
        : false;
    final hasPhotos = ruckBuddy.photos != null && ruckBuddy.photos!.isNotEmpty;
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
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
                      // Use the specialized formatter that preserves original input values
                      // This prevents rounding issues with standard weights like 10, 20, 60 lbs
                      MeasurementUtils.formatWeightForChip(ruckBuddy.ruckWeightKg, metric: preferMetric),
                      style: AppTextStyles.labelMedium.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
              
              const SizedBox(height: 12),

              // Map snippet with photos overlay if available
              Stack(
                children: [
                  _RouteMapPreview(ruckBuddy: ruckBuddy),
                  if (hasPhotos)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: _PhotoThumbnailsOverlay(photos: ruckBuddy.photos!),
                    ),
                ],
              ),

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
                          value: MeasurementUtils.formatElevationCompact(ruckBuddy.elevationGainM, ruckBuddy.elevationLossM.abs(), metric: preferMetric),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              // Social interactions row
              const SizedBox(height: 16),
              Row(
                children: [
                  // Like button with count
                  InkWell(
                    onTap: onLikeTap,
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                      child: Row(
                        children: [
                          Icon(
                            ruckBuddy.isLikedByCurrentUser ? Icons.favorite : Icons.favorite_border,
                            color: ruckBuddy.isLikedByCurrentUser ? Colors.red : Colors.grey[600],
                            size: 20,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${ruckBuddy.likeCount}',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Comments count
                  Row(
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        color: Colors.grey[600],
                        size: 20,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${ruckBuddy.commentCount}',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Photo count if any
                  if (ruckBuddy.photos != null && ruckBuddy.photos!.isNotEmpty)
                    Row(
                      children: [
                        Icon(
                          Icons.photo_library,
                          color: Colors.grey[600],
                          size: 20,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${ruckBuddy.photos!.length}',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildAvatar(UserInfo user) {
    // Check if we should use photo URL (if available)
    if (user.photoUrl != null && user.photoUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 20,
        backgroundImage: NetworkImage(user.photoUrl!),
      );
    } else {
      // Use gender-specific rucker image
      final String imagePath = user.gender == 'female'
          ? 'assets/images/lady rucker profile.png'
          : 'assets/images/profile.png';
      
      return CircleAvatar(
        radius: 20,
        backgroundColor: Colors.transparent,
        backgroundImage: AssetImage(imagePath),
      );
    }
  }

  String _formatCompletedDate(DateTime? completedAt) {
    if (completedAt == null) return 'Date unknown';
    return DateFormat('MMM d, yyyy').format(completedAt);
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

class _PhotoThumbnailsOverlay extends StatelessWidget {
  final List<RuckPhoto> photos;
  final int maxDisplay;

  const _PhotoThumbnailsOverlay({
    required this.photos,
    this.maxDisplay = 3,
  });

  @override
  Widget build(BuildContext context) {
    // Show up to maxDisplay photos, with a +X indicator if there are more
    final displayCount = photos.length > maxDisplay ? maxDisplay : photos.length;
    final hasMore = photos.length > maxDisplay;
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          ...List.generate(displayCount, (index) {
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: photos[index].url != null
                      ? CachedNetworkImage(
                          imageUrl: photos[index].url!,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => const Center(
                            child: SizedBox(
                              width: 10,
                              height: 10,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white54,
                              ),
                            ),
                          ),
                          errorWidget: (context, url, error) => const Icon(
                            Icons.error,
                            size: 12,
                            color: Colors.white70,
                          ),
                        )
                      : const Icon(
                          Icons.image,
                          size: 12,
                          color: Colors.white70,
                        ),
                ),
              ),
            );
          }),
          if (hasMore)
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.black38,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child: Text(
                  '+${photos.length - maxDisplay}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
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
              urlTemplate: "https://tiles.stadiamaps.com/tiles/stamen_terrain/{z}/{x}/{y}{r}.png?api_key=\${dotenv.env['STADIA_MAPS_API_KEY']}",
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
          ],
        ),
      ),
    );
  }
}
