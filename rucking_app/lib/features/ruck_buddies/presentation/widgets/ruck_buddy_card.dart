import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Import for HapticFeedback
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:rucking_app/core/utils/measurement_utils.dart';
import 'package:rucking_app/features/ruck_buddies/domain/entities/ruck_buddy.dart';
import 'package:rucking_app/features/ruck_buddies/domain/entities/user_info.dart';
import 'package:rucking_app/features/ruck_buddies/presentation/pages/ruck_buddy_detail_screen.dart'; // Import for RuckBuddyDetailScreen
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/social/presentation/bloc/social_bloc.dart';
import 'package:rucking_app/features/social/presentation/bloc/social_event.dart';
import 'package:rucking_app/features/social/presentation/bloc/social_state.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_photo.dart';

class RuckBuddyCard extends StatefulWidget {
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
  State<RuckBuddyCard> createState() => _RuckBuddyCardState();
}

class _RuckBuddyCardState extends State<RuckBuddyCard> {
  // Track local state for immediate feedback
  bool _isLiked = false;
  int _likeCount = 0;
  bool _isProcessingLike = false;

  @override
  void initState() {
    super.initState();
    _likeCount = widget.ruckBuddy.likeCount;
    
    // Check if this ruck is already liked
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final ruckId = int.tryParse(widget.ruckBuddy.id);
        if (ruckId != null) {
          // Quietly check if user has liked this ruck
          context.read<SocialBloc>().add(ToggleRuckLike(ruckId));
          debugPrint('🐞 [_RuckBuddyCardState.initState] Dispatched ToggleRuckLike for Ruck ID: $ruckId');
        }
      }
    });
  }
  
  void _handleLikeTap() {
    if (_isProcessingLike) return; // Prevent multiple rapid clicks
    
    // Trigger strong haptic feedback when like button is tapped
    HapticFeedback.heavyImpact();
    
    // Optimistic update for immediate feedback FIRST
    setState(() {
      // Update the UI state immediately for responsiveness
      if (_isLiked) {
        _likeCount = _likeCount > 0 ? _likeCount - 1 : 0;
      } else {
        _likeCount += 1;
      }
      _isLiked = !_isLiked;
      
      // Only set processing to true AFTER the icon has changed
      // This ensures the user sees the heart change before any loading indicator
      _isProcessingLike = true;
    });
    
    // Dispatch event to update backend
    final ruckId = int.tryParse(widget.ruckBuddy.id);
    if (ruckId != null) {
      // Directly update backend through SocialBloc - this ensures per-ruck state
      context.read<SocialBloc>().add(ToggleRuckLike(ruckId));
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('🐞 [_RuckBuddyCardState.build] Called for RuckBuddy ID: ${widget.ruckBuddy.id}');

    if (widget.ruckBuddy.user == null) {
      debugPrint('🐞 [_RuckBuddyCardState.build] CRITICAL: widget.ruckBuddy.user is NULL for ID: ${widget.ruckBuddy.id}');
      return const SizedBox.shrink();
    }

    final authBloc = Provider.of<AuthBloc>(context, listen: false);
    final bool preferMetric = authBloc.state is Authenticated
        ? (authBloc.state as Authenticated).user.preferMetric
        : false;
    final hasPhotos = widget.ruckBuddy.photos != null && widget.ruckBuddy.photos!.isNotEmpty;
    
    return BlocListener<SocialBloc, SocialState>(
      listenWhen: (previous, current) {
        // Listen for like action completions and status checks
        // Only respond to states related to THIS specific ruck
        final thisRuckId = int.tryParse(widget.ruckBuddy.id);
        if (thisRuckId == null) return false;
        
        if (current is LikeActionCompleted) {
          return thisRuckId == current.ruckId;
        }
        if (current is LikeStatusChecked) {
          return thisRuckId == current.ruckId;
        }
        if (current is LikesLoaded) {
          return thisRuckId == current.ruckId;
        }
        return false;
      },
      listener: (context, state) {
        final thisRuckId = int.tryParse(widget.ruckBuddy.id);
        if (thisRuckId == null) return;
        
        debugPrint('🐞 [_RuckBuddyCardState.build] RuckID ${thisRuckId} received SocialBloc state: $state');
        
        if (state is LikeActionCompleted && state.ruckId == thisRuckId) {
          debugPrint('🐞 [_RuckBuddyCardState.build] Like action completed for Ruck ID: ${state.ruckId}, liked: ${state.isLiked}');
          // Update UI based on the result for THIS specific ruck
          setState(() {
            _isLiked = state.isLiked;
            _likeCount = state.likeCount; // Use the count from the state
            _isProcessingLike = false;
          });
        } else if (state is LikeActionError && state.ruckId == thisRuckId) {
          debugPrint('🐞 [_RuckBuddyCardState.build] Like action error for Ruck ID ${state.ruckId}: ${state.message}');
          // Show error and revert UI
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to like ruck. Server error related to database table.'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
          setState(() {
            _isLiked = !_isLiked; // Revert the optimistic update
            if (_isLiked) {
              _likeCount = _likeCount > 0 ? _likeCount - 1 : 0;
            } else {
              _likeCount += 1;
            }
            _isProcessingLike = false;
          });
        } else if (state is LikesLoaded && state.ruckId == thisRuckId) {
          debugPrint('🐞 [_RuckBuddyCardState.build] Likes loaded for Ruck ID ${state.ruckId}, user has liked: ${state.userHasLiked}');
          setState(() {
            _isLiked = state.userHasLiked;
            _likeCount = state.likes.length;
            _isProcessingLike = false;
          });
        }
      },
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // User Info Row
                Builder(builder: (context) {
                  debugPrint('🐞 [_RuckBuddyCardState.build ID: ${widget.ruckBuddy.id}] Building User Info Row.');
                  return Row(
                    children: [
                      // Avatar (fallback to circle with first letter if no URL)
                      _buildAvatar(widget.ruckBuddy.user),
                      const SizedBox(width: 12),
                      
                      // User Name & Time Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.ruckBuddy.user.username,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
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
                      
                      // Weight chip
                      Chip(
                        backgroundColor: AppColors.secondary,
                        label: Text(
                          MeasurementUtils.formatWeightForChip(widget.ruckBuddy.ruckWeightKg, metric: preferMetric),
                          style: AppTextStyles.labelMedium.copyWith(
                            color: Colors.white,
                          ),
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  );
                }), // End of User Info Row Builder
                
                const SizedBox(height: 12),

                // Map snippet with photos overlay if available
                Builder(builder: (context) {
                  debugPrint('🐞 [_RuckBuddyCardState.build ID: ${widget.ruckBuddy.id}] Building Map/Photo Stack.');
                  return Stack(
                    children: [
                      _RouteMapPreview(ruckBuddy: widget.ruckBuddy),
                      if (hasPhotos)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: _PhotoThumbnailsOverlay(photos: widget.ruckBuddy.photos!),
                        ),
                    ],
                  );
                }), // End of Map/Photo Stack Builder

                const Divider(height: 24),
                
                // Stats Grid (2x2)
                Builder(builder: (context) {
                  debugPrint('🐞 [_RuckBuddyCardState.build ID: ${widget.ruckBuddy.id}] Building Stats Grid.');
                  return Row(
                    children: [
                      // Left column
                      Expanded(
                        child: Column(
                          children: [
                            _buildStatTile(
                              context: context,
                              icon: Icons.straighten, 
                              label: 'Distance',
                              value: MeasurementUtils.formatDistance(widget.ruckBuddy.distanceKm, metric: preferMetric),
                            ),
                            const SizedBox(height: 16),
                            _buildStatTile(
                              context: context,
                              icon: Icons.local_fire_department, 
                              label: 'Calories',
                              value: '${widget.ruckBuddy.caloriesBurned} kcal',
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
                              value: MeasurementUtils.formatDuration(Duration(seconds: widget.ruckBuddy.durationSeconds)),
                            ),
                            const SizedBox(height: 16),
                            _buildStatTile(
                              context: context,
                              icon: Icons.terrain, 
                              label: 'Elevation',
                              value: MeasurementUtils.formatElevationCompact(widget.ruckBuddy.elevationGainM, widget.ruckBuddy.elevationLossM.abs(), metric: preferMetric),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }), // End of Stats Grid Builder

                const SizedBox(height: 16),

                // Social interactions row
                Builder(builder: (context) {
                  debugPrint('🐞 [_RuckBuddyCardState.build ID: ${widget.ruckBuddy.id}] Building Action Buttons.');
                  return Row(
                    children: [
                      // Like button with count
                      InkWell(
                        onTap: _handleLikeTap,
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                          child: Row(
                            children: [
                              // Always show the like icon (never a loading indicator)
                              // This gives immediate visual feedback
                              Image.asset(
                                    _isLiked 
                                      ? 'assets/images/tactical_ruck_like_icon_active.png' 
                                      : 'assets/images/tactical_ruck_like_icon_transparent.png',
                                    width: 40,
                                    height: 40,
                                  ),
                              const SizedBox(width: 4),
                              Text(
                                '$_likeCount',
                                style: TextStyle(
                                  fontFamily: 'Bangers',
                                  fontSize: 24,
                                  color: Colors.grey[800],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      const SizedBox(width: 16),
                      
                      // Comments count with tap action
                      InkWell(
                        onTap: () {
                          // Navigate to detail screen and focus comment field
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => RuckBuddyDetailScreen(
                                ruckBuddy: widget.ruckBuddy,
                                focusComment: true, // Signal to focus comment field
                              ),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                          child: Row(children: [
                            Icon(
                              Icons.comment,
                              size: 40, // Adjusted to 40px as requested
                              color: AppColors.secondary, // Brownish-orange color
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${widget.ruckBuddy.commentCount}',
                              style: TextStyle(
                                fontFamily: 'Bangers',
                                fontSize: 24,
                                color: Colors.grey[800],
                              ),
                            ),
                          ]),
                        ),
                      ),
                      
                      const Spacer(),
                    ],
                  );
                }), // End of Action Buttons Builder
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildAvatar(UserInfo user) {
    if (user.photoUrl != null && user.photoUrl!.isNotEmpty) {
      // Always use custom photo if present
      return CircleAvatar(
        radius: 24,
        backgroundColor: Colors.grey[200],
        backgroundImage: CachedNetworkImageProvider(user.photoUrl!),
      );
    } else {
      // Use gender-specific default avatar
      final String imagePath = user.gender == 'female'
          ? 'assets/images/lady rucker profile.png'
          : 'assets/images/profile.png';
      return CircleAvatar(
        radius: 24,
        backgroundColor: Colors.grey[200],
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
                            Icons.image,
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
    if (lp == null || lp.isEmpty) {
      // No location data available
      return pts;
    }
    
    // Process locationPoints according to DATA_MODEL_REFERENCE.md
    // Format used is {"lat": 40.41, "lng": -3.68, "timestamp": "..." }
    for (final p in lp) {
      double? lat;
      double? lng;

      if (p is Map) {
        // Primary format from backend is 'latitude'/'longitude'
        lat = _parseCoord(p['latitude']);
        lng = _parseCoord(p['longitude']);
        
        // Fallbacks for other possible formats
        if (lat == null) {
          lat = _parseCoord(p['lat']);
        }
        if (lng == null) {
          lng = _parseCoord(p['lng']) ?? _parseCoord(p['lon']);
        }
      } else if (p is List && p.length >= 2) {
        // Handle array format [lat, lng]
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
    
    // If we have no route data at all, show a placeholder
    if (routePoints.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 175,
          width: double.infinity,
          color: Colors.grey[200],
          child: Center(
            child: Icon(
              Icons.map_outlined,
              size: 48,
              color: Colors.grey[400],
            ),
          ),
        ),
      );
    }
    
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
          ],
        ),
      ),
    );
  }
}
