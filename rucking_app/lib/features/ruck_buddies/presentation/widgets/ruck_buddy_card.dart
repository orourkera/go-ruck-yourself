import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:rucking_app/core/utils/measurement_utils.dart';
import 'package:rucking_app/features/ruck_buddies/domain/entities/ruck_buddy.dart';
import 'package:rucking_app/features/ruck_buddies/domain/entities/user_info.dart';
import 'package:rucking_app/features/ruck_buddies/presentation/pages/ruck_buddy_detail_screen.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/social/presentation/bloc/social_bloc.dart';
import 'package:rucking_app/features/social/presentation/bloc/social_event.dart';
import 'package:rucking_app/features/social/presentation/bloc/social_state.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/photo/photo_viewer.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_photo.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_session.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';
import 'package:get_it/get_it.dart';
import 'dart:developer' as developer;

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
  int? _likeCount;
  bool _isLiked = false;
  bool _isProcessingLike = false;
  List<RuckPhoto> _photos = [];
  double _calculatedPace = 0.0;
  int? _ruckId;
  int? _commentCount;  // Track comment count locally

  @override
  void initState() {
    super.initState();
    _ruckId = int.tryParse(widget.ruckBuddy.id);
    
    // IMPORTANT: Immediately use the data from widget.ruckBuddy to prevent initial zero values
    _likeCount = widget.ruckBuddy.likeCount ?? 0;
    _commentCount = widget.ruckBuddy.commentCount ?? 0;
    _isLiked = widget.ruckBuddy.isLikedByCurrentUser ?? false; // Initialize with RuckBuddy data
    
    // Fetch fresh data from SocialBloc
    if (_ruckId != null) {
      developer.log('[SOCIAL_DEBUG] RuckBuddyCard initState for ruckId: $_ruckId - dispatching CheckRuckLikeStatus and LoadRuckComments', name: 'RuckBuddyCard');
      // Use context.read<SocialBloc>() if SocialBloc is provided via Provider higher up the tree
      // If using GetIt for BLoC access directly (as hinted by previous code), ensure it's appropriate here.
      // For standard BLoC usage with widget tree, context.read is preferred.
      // Assuming SocialBloc is accessible via context here for typical Flutter BLoC pattern.
      try {
        context.read<SocialBloc>().add(CheckRuckLikeStatus(_ruckId!));
        context.read<SocialBloc>().add(LoadRuckComments(_ruckId!.toString()));
      } catch (e) {
        developer.log('[SOCIAL_DEBUG] Error dispatching events in RuckBuddyCard initState: $e. Ensure SocialBloc is provided.', name: 'RuckBuddyCard');
        // Fallback or error handling if SocialBloc is not found in context
      }
    }
    
    // Initialize photos
    _photos = widget.ruckBuddy.photos != null ? List<RuckPhoto>.from(widget.ruckBuddy.photos!) : [];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_ruckId != null) {
        // Calculate pace from distance and duration
        final double distanceKm = widget.ruckBuddy.distanceKm ?? 0.0;
        final int durationSeconds = widget.ruckBuddy.durationSeconds ?? 0;
        _calculatedPace = (distanceKm > 0 && durationSeconds > 0) ? (durationSeconds / 60) / distanceKm : 0.0;
        
        // Only fetch photos if needed, but skip heart rate data to avoid unnecessary API calls
        if (_photos.isEmpty) {
          developer.log('[PHOTO_DEBUG] RuckBuddyCard initState: Ruck ID ${widget.ruckBuddy.id} - Fetching photos.', name: 'RuckBuddyCard');
          final activeSessionBloc = GetIt.instance<ActiveSessionBloc>();
          
          // Only dispatch the photo fetch event, NOT the LoadSessionForViewing event
          // This avoids the heart rate API calls while still loading photos
          activeSessionBloc.add(FetchSessionPhotosRequested(widget.ruckBuddy.id));
        } else {
          developer.log('[PHOTO_DEBUG] RuckBuddyCard: Using photos already in RuckBuddy object. Count: ${_photos.length}', name: 'RuckBuddyCard');
        }
      }
    });
  }

  List<RuckPhoto> _convertToRuckPhotos(List<dynamic> photos) {
    return photos.map((dynamic photo) {
      if (photo is RuckPhoto) {
        return photo;
      }
      if (photo is Map<String, dynamic>) {
        return RuckPhoto(
          id: photo['id'] as String? ?? '',
          ruckId: photo['ruck_id'] != null ? photo['ruck_id'].toString() : '',
          userId: photo['user_id'] as String? ?? '',
          filename: photo['filename'] as String? ?? '',
          originalFilename: photo['original_filename'] as String?,
          contentType: photo['content_type'] as String?,
          size: photo['size'] as int?,
          createdAt: photo['created_at'] != null ? DateTime.parse(photo['created_at'] as String) : DateTime.now(),
          url: photo['url'] as String?,
          thumbnailUrl: photo['thumbnail_url'] as String?,
        );
      }
      return RuckPhoto(
        id: '',
        ruckId: '',
        userId: '',
        filename: '',
        createdAt: DateTime.now(),
      );
    }).toList().cast<RuckPhoto>();
  }

  List<String> _getProcessedPhotoUrls(List<dynamic> photos, {bool addCacheBuster = false}) {
    final photoUrls = photos.map((p) {
      if (p is RuckPhoto) {
        final url = p.url;
        final thumbnailUrl = p.thumbnailUrl;
        if (url != null && url.isNotEmpty) return url;
        if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) return thumbnailUrl;
      }
      return '';
    }).where((url) => url.isNotEmpty).toList();

    if (!addCacheBuster) return photoUrls;

    final cacheBuster = DateTime.now().millisecondsSinceEpoch;
    return photoUrls.map((url) => url.contains('?') ? '$url&t=$cacheBuster' : '$url?t=$cacheBuster').toList();
  }

  void _handleLikeTap() {
    if (_isProcessingLike || _ruckId == null) return;

    HapticFeedback.heavyImpact();
    
    // Save original values in case we need to revert due to API error
    final originalIsLiked = _isLiked;
    final originalLikeCount = _likeCount ?? 0;

    // Optimistically update the UI immediately
    setState(() {
      if (_isLiked) {
        _likeCount = (_likeCount ?? 0) > 0 ? (_likeCount ?? 0) - 1 : 0;
      } else {
        _likeCount = (_likeCount ?? 0) + 1;
      }
      _isLiked = !_isLiked;
      _isProcessingLike = true;
    });

    // Important: Use GetIt to ensure we're using the shared singleton instance
    final socialBloc = GetIt.instance<SocialBloc>();
    
    // Handle potential server-side errors (we know there's a 500 error issue)
    try {
      socialBloc.add(ToggleRuckLike(_ruckId!));
      developer.log('[SOCIAL_DEBUG] RuckBuddyCard: Like toggle requested for ruckId $_ruckId');
    } catch (e) {
      // Revert UI on error
      setState(() {
        _isLiked = originalIsLiked;
        _likeCount = originalLikeCount;
        _isProcessingLike = false;
      });
      developer.log('[SOCIAL_DEBUG] RuckBuddyCard: Error toggling like: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Calculate pace if not already done
    if (_calculatedPace == 0.0 && widget.ruckBuddy.distanceKm > 0 && widget.ruckBuddy.durationSeconds > 0) {
      _calculatedPace = (widget.ruckBuddy.durationSeconds / 60) / widget.ruckBuddy.distanceKm;
    }

    // Determine if metric system is preferred from AuthBloc state
    final authState = context.watch<AuthBloc>().state;
    final bool preferMetric = authState is Authenticated ? authState.user.preferMetric : true; // Default to true or handle appropriately

    final String formattedPace = MeasurementUtils.formatPace(_calculatedPace, metric: preferMetric);
    final String formattedDistance = MeasurementUtils.formatDistance(widget.ruckBuddy.distanceKm, metric: preferMetric);
    final String formattedDuration = MeasurementUtils.formatDuration(Duration(seconds: widget.ruckBuddy.durationSeconds.round()));
    final String formattedElevation = MeasurementUtils.formatElevation(widget.ruckBuddy.elevationGainM, 0, metric: preferMetric);
    final String formattedCalories = '${widget.ruckBuddy.caloriesBurned.round()} kcal';
    final String formattedWeight = MeasurementUtils.formatWeight(widget.ruckBuddy.ruckWeightKg, metric: preferMetric);

    return BlocConsumer<SocialBloc, SocialState>(
      listener: (context, state) {
        if (!mounted || _ruckId == null) return;

        if (state is LikeStatusChecked && state.ruckId == _ruckId) {
          setState(() {
            _isLiked = state.isLiked;
            _likeCount = state.likeCount; 
            developer.log('[SOCIAL_DEBUG] RuckBuddyCard (ruckId: $_ruckId) updated _isLiked to ${state.isLiked} and _likeCount to ${state.likeCount} from LikeStatusChecked', name: 'RuckBuddyCard');
          });
        }
        if (state is LikeActionCompleted && state.ruckId == _ruckId) {
          setState(() {
            _isProcessingLike = false;
            _isLiked = state.isLiked;
            _likeCount = state.likeCount;
            developer.log('[SOCIAL_DEBUG] RuckBuddyCard (ruckId: $_ruckId) updated _isLiked to ${state.isLiked} and _likeCount to ${state.likeCount} from LikeActionCompleted', name: 'RuckBuddyCard');
          });
        }
        if (state is CommentsLoaded && state.ruckId == _ruckId.toString()) {
          setState(() {
            _commentCount = state.comments.length;
            developer.log('[SOCIAL_DEBUG] RuckBuddyCard (ruckId: $_ruckId) updated _commentCount to ${state.comments.length} from CommentsLoaded', name: 'RuckBuddyCard');
          });
        }
        if (state is LikeActionInProgress) {
          setState(() => _isProcessingLike = true);
        }
        if (state is LikeActionError && state.ruckId == _ruckId) {
          setState(() => _isProcessingLike = false);
          developer.log('[SOCIAL_DEBUG] RuckBuddyCard (ruckId: $_ruckId) encountered LikeActionError: ${state.message}', name: 'RuckBuddyCard');
        }
      },
      builder: (context, socialState) {
        return BlocListener<ActiveSessionBloc, ActiveSessionState>(
          bloc: GetIt.instance<ActiveSessionBloc>(),
          listener: (context, activeSessionState) {
            if (!mounted) return;
            final cardSessionId = widget.ruckBuddy.id;
            developer.log('[PHOTO_DEBUG] RuckBuddyCard (ID: $cardSessionId) listener: Received ActiveSessionState ${activeSessionState.runtimeType}', name: 'RuckBuddyCard');

            if (activeSessionState is SessionSummaryGenerated && activeSessionState.session.id == cardSessionId) {
              developer.log('[PHOTO_DEBUG] RuckBuddyCard (ID: $cardSessionId): SessionSummaryGenerated with ${activeSessionState.photos.length} photos', name: 'RuckBuddyCard');
              if (activeSessionState.photos.isNotEmpty) {
                setState(() => _photos = _convertToRuckPhotos(activeSessionState.photos));
              }
            } else if (activeSessionState is ActiveSessionRunning && activeSessionState.sessionId == cardSessionId) {
              developer.log('[PHOTO_DEBUG] RuckBuddyCard (ID: $cardSessionId): ActiveSessionRunning with ${activeSessionState.photos.length} photos', name: 'RuckBuddyCard');
              if (activeSessionState.photos.isNotEmpty) {
                setState(() => _photos = _convertToRuckPhotos(activeSessionState.photos));
              }
            } else if (activeSessionState is ActiveSessionInitial && activeSessionState.viewedSession?.id == cardSessionId) {
              developer.log('[PHOTO_DEBUG] RuckBuddyCard (ID: $cardSessionId): ActiveSessionInitial with ${activeSessionState.photos.length} photos for viewed session', name: 'RuckBuddyCard');
              if (activeSessionState.photos.isNotEmpty) {
                setState(() => _photos = _convertToRuckPhotos(activeSessionState.photos));
              }
            } else if (activeSessionState is SessionPhotosLoadedForId && activeSessionState.sessionId == cardSessionId) {
              developer.log('[PHOTO_DEBUG] RuckBuddyCard (ID: $cardSessionId): SessionPhotosLoadedForId with ${activeSessionState.photos.length} photos', name: 'RuckBuddyCard');
               // SessionPhotosLoadedForId carries a List<RuckPhoto>
              setState(() => _photos = activeSessionState.photos); // No conversion needed if it's already List<RuckPhoto>
            }
          },
          child: Card(
            elevation: 3,
            margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 0),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: InkWell(
              onTap: widget.onTap ?? () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => RuckBuddyDetailScreen(
                      ruckBuddy: widget.ruckBuddy,
                    ),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // User Info Header
                    Row(
                      children: [
                        _buildAvatar(widget.ruckBuddy.user),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.ruckBuddy.user.username, // Use username here
                                style: AppTextStyles.titleMedium.copyWith(fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (widget.ruckBuddy.completedAt != null)
                                Text(
                                  _formatCompletedDate(widget.ruckBuddy.completedAt),
                                  style: AppTextStyles.bodyMedium.copyWith(fontSize: 12),
                                ),
                            ],
                          ),
                        ),
                        // Like button
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                _isLiked ? Icons.favorite : Icons.favorite_border,
                                color: _isLiked ? AppColors.primary : Colors.grey[600],
                                size: 28,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: _isProcessingLike ? null : _handleLikeTap,
                            ),
                            if (_likeCount != null)
                              Text(
                                '$_likeCount', // Use local state variable
                                style: AppTextStyles.bodyMedium.copyWith(fontSize: 12, color: Colors.grey[700]),
                              ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Map Preview with Ruck Weight Chip
                    Stack(
                      children: [
                        _RouteMapPreview(locationPoints: widget.ruckBuddy.locationPoints),
                        if (widget.ruckBuddy.ruckWeightKg > 0)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Chip(
                              label: Text(formattedWeight, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                              backgroundColor: AppColors.primary.withOpacity(0.85),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Stats Grid
                    GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: 2.8, // Adjust for better spacing
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      children: [
                        _buildStatTile(context: context, icon: Icons.directions_walk, label: 'Distance', value: formattedDistance, compact: true),
                        _buildStatTile(context: context, icon: Icons.timer_outlined, label: 'Duration', value: formattedDuration, compact: true),
                        _buildStatTile(context: context, icon: Icons.local_fire_department_outlined, label: 'Calories', value: formattedCalories, compact: true),
                        _buildStatTile(context: context, icon: Icons.speed_outlined, label: 'Pace', value: formattedPace, compact: true),
                        _buildStatTile(context: context, icon: Icons.terrain_outlined, label: 'Elevation', value: formattedElevation, compact: true),
                        // Comment Count Tile
                        InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => RuckBuddyDetailScreen(
                                  ruckBuddy: widget.ruckBuddy,
                                  focusComment: true, 
                                ),
                              ),
                            );
                          },
                          child: _buildStatTile(
                            context: context,
                            icon: Icons.comment_outlined,
                            label: 'Comments',
                            value: '${_commentCount ?? 0}', // Use local state variable
                            compact: true,
                          ),
                        ),
                      ],
                    ),
                    
                    // Photos Preview (if any)
                    // This part would also use local _photos state, updated by ActiveSessionBloc listener if integrated
                    if (_photos.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12.0),
                        child: SizedBox(
                          height: 80,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _photos.length,
                            itemBuilder: (context, index) {
                              final photo = _photos[index];
                              return Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: InkWell(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => PhotoViewer(
                                          photoUrls: _photos.map((photo) => photo.url ?? photo.thumbnailUrl ?? '').where((url) => url.isNotEmpty).toList(),
                                          initialIndex: index,
                                        ),
                                      ),
                                    );
                                  },
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8.0),
                                    child: CachedNetworkImage(
                                      imageUrl: photo.thumbnailUrl ?? photo.url ?? '',
                                      width: 80,
                                      height: 80,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => Container(color: Colors.grey[300]),
                                      errorWidget: (context, url, error) => Container(
                                        color: Colors.grey[300],
                                        child: const Icon(Icons.broken_image, color: Colors.grey),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAvatar(UserInfo? user) {
    if (user == null) {
      return CircleAvatar(
        radius: 24,
        backgroundColor: Colors.grey[200],
        backgroundImage: const AssetImage('assets/images/profile.png'),
      );
    }
    if (user.photoUrl != null && user.photoUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 24,
        backgroundColor: Colors.grey[200],
        backgroundImage: CachedNetworkImageProvider(user.photoUrl!),
      );
    } else {
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
    bool compact = false,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: compact ? 22 : 28,
          color: AppColors.secondary,
        ),
        SizedBox(width: compact ? 4 : 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTextStyles.bodySmall.copyWith(
                  color: Colors.grey[600],
                  fontSize: compact ? 14 : 18,
                ),
              ),
              Text(
                value,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: compact ? 16 : 22,
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
  final List<dynamic>? locationPoints;

  const _RouteMapPreview({
    required this.locationPoints,
  });

  double? _parseCoord(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  List<LatLng> _getRoutePoints() {
    final pts = <LatLng>[];
    final lp = locationPoints;
    if (lp == null || lp.isEmpty) {
      return pts;
    }

    for (final p in lp) {
      double? lat;
      double? lng;

      if (p is Map) {
        lat = _parseCoord(p['latitude']);
        lng = _parseCoord(p['longitude']);

        if (lat == null) {
          lat = _parseCoord(p['lat']);
        }
        if (lng == null) {
          lng = _parseCoord(p['lng']) ?? _parseCoord(p['lon']);
        }
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