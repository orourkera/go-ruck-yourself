import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:rucking_app/core/utils/measurement_utils.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/ruck_buddies/domain/entities/ruck_buddy.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_photo.dart';
import 'package:rucking_app/features/ruck_session/presentation/widgets/photo_carousel.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

class RuckBuddyDetailScreen extends StatefulWidget {
  final RuckBuddy ruckBuddy;

  const RuckBuddyDetailScreen({
    Key? key,
    required this.ruckBuddy,
  }) : super(key: key);

  @override
  State<RuckBuddyDetailScreen> createState() => _RuckBuddyDetailScreenState();
}

class _RuckBuddyDetailScreenState extends State<RuckBuddyDetailScreen> {
  final TextEditingController _commentController = TextEditingController();
  bool _isLiked = false;
  List<RuckPhoto> _photos = [];
  int _likeCount = 0;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.ruckBuddy.isLikedByCurrentUser;
    _likeCount = widget.ruckBuddy.likeCount;
    _photos = widget.ruckBuddy.photos ?? [];
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _toggleLike() {
    // In the future, this would call an API to record the like
    setState(() {
      _isLiked = !_isLiked;
      _likeCount = _isLiked ? _likeCount + 1 : _likeCount - 1;
    });
  }

  void _submitComment() {
    if (_commentController.text.trim().isEmpty) return;

    // In the future, this would call an API to submit the comment
    // For now, we'll just clear the input
    _commentController.clear();
    
    // Show a feedback snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Comment feature coming soon!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  String _formatDuration(int durationSeconds) {
    final hours = durationSeconds ~/ 3600;
    final minutes = (durationSeconds % 3600) ~/ 60;
    final seconds = durationSeconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '$minutes:${seconds.toString().padLeft(2, '0')}';
    }
  }

  String _formatCompletedDate(DateTime? completedAt) {
    if (completedAt == null) return 'Date unknown';
    return DateFormat('MMM d, yyyy • h:mm a').format(completedAt);
  }

  @override
  Widget build(BuildContext context) {
    final authBloc = Provider.of<AuthBloc>(context, listen: false);
    final bool preferMetric = authBloc.state is Authenticated
        ? (authBloc.state as Authenticated).user.preferMetric
        : false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ruck Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Sharing coming soon!'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User info and date
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  // Avatar
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.secondary,
                    child: Text(
                      widget.ruckBuddy.user.username.isNotEmpty 
                          ? widget.ruckBuddy.user.username[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  
                  // User info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.ruckBuddy.user.username,
                          style: AppTextStyles.titleMedium,
                        ),
                        Text(
                          _formatCompletedDate(widget.ruckBuddy.completedAt),
                          style: AppTextStyles.bodySmall.copyWith(
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Route Map
            SizedBox(
              height: 250,
              width: double.infinity,
              child: _RouteMap(
                locationPoints: widget.ruckBuddy.locationPoints,
              ),
            ),

            // Ruck details
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Weight and duration row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Weight
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.secondary,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          MeasurementUtils.formatWeightForChip(widget.ruckBuddy.ruckWeightKg, metric: preferMetric),
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      
                      // Duration
                      Row(
                        children: [
                          const Icon(Icons.timer, size: 18),
                          const SizedBox(width: 4),
                          Text(
                            _formatDuration(widget.ruckBuddy.durationSeconds),
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Stats grid
                  Row(
                    children: [
                      // Distance
                      Expanded(
                        child: _buildStatItem(
                          icon: Icons.straighten,
                          label: 'Distance',
                          value: MeasurementUtils.formatDistance(widget.ruckBuddy.distanceKm, metric: preferMetric),
                        ),
                      ),
                      // Calories
                      Expanded(
                        child: _buildStatItem(
                          icon: Icons.local_fire_department,
                          label: 'Calories',
                          value: '${widget.ruckBuddy.caloriesBurned}',
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  Row(
                    children: [
                      // Pace
                      Expanded(
                        child: _buildStatItem(
                          icon: Icons.speed,
                          label: 'Avg Pace',
                          value: widget.ruckBuddy.distanceKm > 0 
                            ? MeasurementUtils.formatPace(
                                widget.ruckBuddy.durationSeconds / widget.ruckBuddy.distanceKm, // Calculate seconds per km
                                metric: preferMetric,
                              )
                            : '--',
                        ),
                      ),
                      // Elevation gain
                      Expanded(
                        child: _buildStatItem(
                          icon: Icons.terrain,
                          label: 'Elevation',
                          value: MeasurementUtils.formatElevation(
                            widget.ruckBuddy.elevationGainM, 
                            0.0, // We don't have elevation loss data, so passing 0
                            metric: preferMetric
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            const Divider(),
            
            // Photos section
            if (_photos.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Photos', style: AppTextStyles.titleMedium),
                    const SizedBox(height: 8),
                    PhotoCarousel(
                      photoUrls: (widget.ruckBuddy.photos ?? []).map((photo) => photo.url ?? '').toList(), 
                      showDeleteButtons: false,
                      onPhotoTap: (index) {
                        // View photo full screen
                      },
                    ),
                  ],
                ),
              ),
              const Divider(),
            ],
            
            // Social section
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Like and comment counts
                  Row(
                    children: [
                      // Like button
                      InkWell(
                        onTap: _toggleLike,
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            children: [
                              Image.asset(
                                'assets/images/tactical_ruck_like_icon_transparent.png',
                                width: 24,
                                height: 24,
                                color: _isLiked ? Colors.red : Colors.grey[600],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$_likeCount',
                                style: AppTextStyles.bodyMedium,
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
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${widget.ruckBuddy.commentCount}',
                            style: AppTextStyles.bodyMedium,
                          ),
                        ],
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Comment input
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _commentController,
                          decoration: InputDecoration(
                            hintText: 'Add a comment...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: _submitComment,
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Comments list (placeholder for now)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        'Comments coming soon!',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              color: AppColors.secondary,
              size: 18,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTextStyles.bodyLarge.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _RouteMap extends StatelessWidget {
  final List<dynamic>? locationPoints;

  const _RouteMap({
    required this.locationPoints,
  });

  // Convert dynamic numeric or string to double, return null if not parseable
  double? _parseCoord(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  List<LatLng> _getRoutePoints() {
    final pts = <LatLng>[];
    final lp = locationPoints;
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
    return FlutterMap(
      options: MapOptions(
        initialCenter: _getRouteCenter(routePoints),
        initialZoom: _getFitZoom(routePoints),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.none,
        ),
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
      ],
    );
  }
}
