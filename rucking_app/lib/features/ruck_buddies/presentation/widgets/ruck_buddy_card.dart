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

  @override
  void initState() {
    super.initState();
    _ruckId = int.tryParse(widget.ruckBuddy.id);
    _likeCount = widget.ruckBuddy.likeCount;
    _photos = widget.ruckBuddy.photos != null ? List<RuckPhoto>.from(widget.ruckBuddy.photos!) : [];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_ruckId != null) {
        // Use batch check for better performance (also updates other cards)
        final socialBloc = context.read<SocialBloc>();
        socialBloc.add(BatchCheckUserLikeStatus([_ruckId!])); 
        developer.log('[LIKE_DEBUG] RuckBuddyCard initState: Ruck ID $_ruckId - Dispatching BatchCheckUserLikeStatus', name: 'RuckBuddyCard');

        developer.log('[PHOTO_DEBUG] RuckBuddyCard initState: Ruck ID ${widget.ruckBuddy.id} - Fetching photos. Initial count: ${_photos.length}', name: 'RuckBuddyCard');
        final activeSessionBloc = GetIt.instance<ActiveSessionBloc>();

        final startedAt = widget.ruckBuddy.startedAt ?? DateTime.now();
        final completedAt = widget.ruckBuddy.completedAt ?? DateTime.now().add(const Duration(minutes: 30));
        final sessionDuration = completedAt.difference(startedAt);

        final double distanceKm = widget.ruckBuddy.distanceKm ?? 0.0;
        final int durationSeconds = widget.ruckBuddy.durationSeconds ?? 0;
        _calculatedPace = (distanceKm > 0 && durationSeconds > 0) ? (durationSeconds / 60) / distanceKm : 0.0;

        final ruckSession = RuckSession(
          id: widget.ruckBuddy.id,
          startTime: startedAt,
          endTime: completedAt,
          duration: sessionDuration,
          distance: widget.ruckBuddy.distanceKm,
          elevationGain: widget.ruckBuddy.elevationGainM,
          elevationLoss: widget.ruckBuddy.elevationLossM,
          caloriesBurned: widget.ruckBuddy.caloriesBurned,
          averagePace: _calculatedPace,
          ruckWeightKg: widget.ruckBuddy.ruckWeightKg,
          status: RuckStatus.completed,
          locationPoints: widget.ruckBuddy.locationPoints?.cast<Map<String, dynamic>>(),
        );

        developer.log('RuckBuddyCard initState: Ruck ID $_ruckId - Dispatching LoadSessionForViewing', name: 'RuckBuddyCard');
        activeSessionBloc.add(LoadSessionForViewing(sessionId: widget.ruckBuddy.id, session: ruckSession));
        developer.log('RuckBuddyCard initState: Ruck ID $_ruckId - Dispatching FetchSessionPhotosRequested', name: 'RuckBuddyCard');
        activeSessionBloc.add(FetchSessionPhotosRequested(widget.ruckBuddy.id));
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
    developer.log('RuckBuddyCard build: Ruck ID ${widget.ruckBuddy.id} - Current _photos count: ${_photos.length}', name: 'RuckBuddyCard');

    if (widget.ruckBuddy.user == null) {
      developer.log('RuckBuddyCard build: Ruck ID ${widget.ruckBuddy.id} - User is null, showing placeholder.', name: 'RuckBuddyCard');
      return const SizedBox.shrink();
    }

    final authBloc = Provider.of<AuthBloc>(context, listen: false);
    final bool preferMetric = authBloc.state is Authenticated
        ? (authBloc.state as Authenticated).user.preferMetric
        : false;

    return MultiBlocListener(
      listeners: [
        BlocListener<ActiveSessionBloc, ActiveSessionState>(
          bloc: GetIt.instance<ActiveSessionBloc>(),
          listener: (context, state) {
            developer.log('[PHOTO_DEBUG] RuckBuddyCard listener: Received state ${state.runtimeType}', name: 'RuckBuddyCard');

            if (state is SessionSummaryGenerated && state.session.id == widget.ruckBuddy.id) {
              developer.log('[PHOTO_DEBUG] RuckBuddyCard: Received SessionSummaryGenerated for session ${state.session.id} with ${state.photos.length} photos', name: 'RuckBuddyCard');

              if (state.photos.isNotEmpty) {
                final photoUrls = _getProcessedPhotoUrls(state.photos);
                if (photoUrls.isNotEmpty) {
                  developer.log('[PHOTO_DEBUG] RuckBuddyCard: First photo URL: ${photoUrls.first}', name: 'RuckBuddyCard');
                }
                developer.log('[PHOTO_DEBUG] RuckBuddyCard: Updating photos for card ${widget.ruckBuddy.id} with ${state.photos.length} photos', name: 'RuckBuddyCard');
                setState(() {
                  _photos = _convertToRuckPhotos(state.photos);
                });
              }
            } else if (state is ActiveSessionRunning && state.sessionId == widget.ruckBuddy.id) {
              developer.log('[PHOTO_DEBUG] RuckBuddyCard: Received ActiveSessionRunning for session ${state.sessionId} with ${state.photos.length} photos', name: 'RuckBuddyCard');

              if (state.photos.isNotEmpty) {
                developer.log('[PHOTO_DEBUG] RuckBuddyCard: Updating photos for card ${widget.ruckBuddy.id} with ${state.photos.length} photos', name: 'RuckBuddyCard');
                setState(() {
                  _photos = _convertToRuckPhotos(state.photos);
                });
              }
            } else if (state is ActiveSessionInitial && state.viewedSession != null && state.photos.isNotEmpty) {
              final sessionId = state.viewedSession?.id;
              developer.log('[PHOTO_DEBUG] RuckBuddyCard: Received ActiveSessionInitial with ${state.photos.length} photos for session $sessionId', name: 'RuckBuddyCard');

              if (sessionId == widget.ruckBuddy.id) {
                developer.log('[PHOTO_DEBUG] RuckBuddyCard: Updating photos for card with ${state.photos.length} photos', name: 'RuckBuddyCard');
                setState(() {
                  _photos = _convertToRuckPhotos(state.photos);
                });
              }
            }
          },
        ),
        BlocListener<SocialBloc, SocialState>(
          listenWhen: (previous, current) {
            if (_ruckId == null) return false;
            return (current is LikeActionCompleted && _ruckId == current.ruckId) ||
                (current is LikeStatusChecked && _ruckId == current.ruckId) ||
                (current is LikesLoaded && _ruckId == current.ruckId) ||
                (current is BatchLikeStatusChecked && current.likeStatusMap.containsKey(_ruckId));
          },
          listener: (context, state) {
            if (_ruckId == null) return;

            if (state is LikeActionCompleted && state.ruckId == _ruckId) {
              developer.log('RuckBuddyCard SocialBloc Listener: Ruck ID ${state.ruckId} - LikeActionCompleted', name: 'RuckBuddyCard');
              setState(() {
                _isLiked = state.isLiked;
                _likeCount = state.likeCount;
                _isProcessingLike = false;
              });
            } else if (state is LikeActionError && state.ruckId == _ruckId) {
              developer.log('RuckBuddyCard SocialBloc Listener: Ruck ID ${state.ruckId} - LikeActionError: ${state.message}', name: 'RuckBuddyCard');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.message.isNotEmpty ? state.message : 'Failed to like ruck. Please try again.'),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 3),
                ),
              );
              setState(() {
                _isLiked = !_isLiked;
                if (_isLiked) {
                  _likeCount = (_likeCount ?? 0) > 0 ? (_likeCount ?? 0) - 1 : 0;
                } else {
                  _likeCount = (_likeCount ?? 0) + 1;
                }
                _isProcessingLike = false;
              });
            } else if (state is LikesLoaded && state.ruckId == _ruckId) {
              developer.log('RuckBuddyCard SocialBloc Listener: Ruck ID ${state.ruckId} - LikesLoaded', name: 'RuckBuddyCard');
              setState(() {
                _isLiked = state.userHasLiked;
                _likeCount = state.likes.length;
                _isProcessingLike = false;
              });
            } else if (state is BatchLikeStatusChecked && state.likeStatusMap.containsKey(_ruckId)) {
              final isLiked = state.likeStatusMap[_ruckId] ?? false;
              final likeCount = state.likeCountMap[_ruckId];
              developer.log('RuckBuddyCard SocialBloc Listener: Ruck ID $_ruckId - BatchLikeStatusChecked, isLiked: $isLiked, likeCount: $likeCount', name: 'RuckBuddyCard');
              setState(() {
                _isLiked = isLiked;
                if (likeCount != null) {
                  _likeCount = likeCount;
                }
                _isProcessingLike = false;
              });
            }
          },
        ),
      ],
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    _buildAvatar(widget.ruckBuddy.user),
                    const SizedBox(width: 12),
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
                          if (widget.ruckBuddy.completedAt != null)
                            Text(
                              _formatCompletedDate(widget.ruckBuddy.completedAt),
                              style: AppTextStyles.bodySmall.copyWith(
                                color: Colors.grey[600],
                              ),
                            ),
                        ],
                      ),
                    ),
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
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 220,
                  child: _RouteMapPreview(
                    locationPoints: widget.ruckBuddy.locationPoints,
                  ),
                ),
                if (_photos.isNotEmpty)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 8),
                      Container(
                        height: 80,
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            for (int i = 0; i < _photos.length && i < 5; i++)
                              if (_photos[i].url != null && _photos[i].url!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: GestureDetector(
                                    onTap: () {
                                      final photoUrls = _getProcessedPhotoUrls(_photos, addCacheBuster: true);
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => PhotoViewer(
                                            photoUrls: photoUrls,
                                            initialIndex: i,
                                            title: '${widget.ruckBuddy.user.username}\'s Ruck',
                                          ),
                                        ),
                                      );
                                    },
                                    child: Container(
                                      width: 80,
                                      height: 80,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: Colors.grey.shade300),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(3),
                                        child: CachedNetworkImage(
                                          imageUrl: _getProcessedPhotoUrls([_photos[i]], addCacheBuster: true).first,
                                          fit: BoxFit.cover,
                                          placeholder: (context, url) => const Center(
                                            child: SizedBox(
                                              width: 15,
                                              height: 15,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            ),
                                          ),
                                          errorWidget: (context, url, error) => const Icon(
                                            Icons.image_not_supported,
                                            size: 20,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            if (_photos.length > 5)
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Center(
                                  child: Text(
                                    '+${_photos.length - 5}',
                                    style: TextStyle(
                                      color: Colors.grey.shade700,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                const Divider(height: 20),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 0),
                  margin: const EdgeInsets.only(bottom: 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildStatTile(
                              context: context,
                              icon: Icons.straighten,
                              label: 'Distance',
                              value: MeasurementUtils.formatDistance(widget.ruckBuddy.distanceKm ?? 0.0, metric: preferMetric),
                              compact: true,
                            ),
                            const SizedBox(height: 10),
                            _buildStatTile(
                              context: context,
                              icon: Icons.local_fire_department,
                              label: 'Calories',
                              value: '${widget.ruckBuddy.caloriesBurned ?? 0} kcal',
                              compact: true,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildStatTile(
                              context: context,
                              icon: Icons.timer,
                              label: 'Duration',
                              value: MeasurementUtils.formatDuration(Duration(seconds: widget.ruckBuddy.durationSeconds ?? 0)),
                              compact: true,
                            ),
                            const SizedBox(height: 10),
                            _buildStatTile(
                              context: context,
                              icon: Icons.terrain,
                              label: 'Elevation',
                              value: MeasurementUtils.formatElevationCompact(widget.ruckBuddy.elevationGainM, widget.ruckBuddy.elevationLossM.abs(), metric: preferMetric),
                              compact: true,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: _handleLikeTap,
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 2.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset(
                              _isLiked
                                  ? 'assets/images/tactical_ruck_like_icon_active.png'
                                  : 'assets/images/tactical_ruck_like_icon_transparent.png',
                              width: 30,
                              height: 30,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '${_likeCount ?? 0}',
                              style: TextStyle(
                                fontFamily: 'Bangers',
                                fontSize: 20,
                                color: Colors.grey[800],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    InkWell(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => RuckBuddyDetailScreen(
                              ruckBuddy: widget.ruckBuddy,
                              focusComment: true,
                            ),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 2.0),
                        child: Row(
                          children: [
                            Icon(
                              Icons.comment,
                              size: 30,
                              color: AppColors.secondary,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '${widget.ruckBuddy.commentCount}',
                              style: TextStyle(
                                fontFamily: 'Bangers',
                                fontSize: 20,
                                color: Colors.grey[800],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
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