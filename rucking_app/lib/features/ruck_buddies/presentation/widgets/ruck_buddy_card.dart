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
import 'package:rucking_app/shared/widgets/photo/photo_carousel.dart';
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
      // Remove the map key initialization from _RuckBuddyCardState
    
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
    
    // Initialize photos and log status
    _photos = widget.ruckBuddy.photos != null ? List<RuckPhoto>.from(widget.ruckBuddy.photos!) : [];
    developer.log('[PHOTO_DEBUG] RuckBuddyCard initState for ruckId: $_ruckId - initial photos count: ${_photos.length}', name: 'RuckBuddyCard');
    
    // Explicitly request photos for this ruck session
    if (_ruckId != null) {
      try {
        // Request photos for this ruck from ActiveSessionBloc
        final activeSessionBloc = GetIt.instance<ActiveSessionBloc>();
        activeSessionBloc.add(FetchSessionPhotosRequested(widget.ruckBuddy.id));
        developer.log('[PHOTO_DEBUG] RuckBuddyCard requested photos for ruckId: $_ruckId', name: 'RuckBuddyCard');
      } catch (e) {
        developer.log('[PHOTO_DEBUG] Error requesting photos in RuckBuddyCard: $e', name: 'RuckBuddyCard');
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_ruckId != null) {
        // Calculate pace from distance and duration
        if (widget.ruckBuddy.distanceKm > 0 && widget.ruckBuddy.durationSeconds > 0) {
          setState(() {
            _calculatedPace = (widget.ruckBuddy.durationSeconds / 60) / widget.ruckBuddy.distanceKm;
          });
        }
      }
    });
  }
  
  @override
  void didUpdateWidget(RuckBuddyCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Re-fetch photos when returning to this screen to ensure they display correctly
    if (_ruckId != null) {
      try {
        // 1. Force update photos from the widget if available
        if (widget.ruckBuddy.photos != null && widget.ruckBuddy.photos!.isNotEmpty) {
          setState(() {
            _photos = List<RuckPhoto>.from(widget.ruckBuddy.photos!);
            developer.log('[PHOTO_DEBUG] RuckBuddyCard directly updated photos from widget: ${_photos.length}', name: 'RuckBuddyCard');
          });
        }
        
        // 2. Request fresh photos from ActiveSessionBloc
        final activeSessionBloc = GetIt.instance<ActiveSessionBloc>();
        activeSessionBloc.add(FetchSessionPhotosRequested(widget.ruckBuddy.id));
        developer.log('[PHOTO_DEBUG] RuckBuddyCard re-requested photos on update for ruckId: $_ruckId', name: 'RuckBuddyCard');
      } catch (e) {
        developer.log('[PHOTO_DEBUG] Error re-requesting photos in RuckBuddyCard.didUpdateWidget: $e', name: 'RuckBuddyCard');
      }
    }
  }

  List<RuckPhoto> _convertToRuckPhotos(List<dynamic> photos) {
    final result = <RuckPhoto>[];
    for (final photo in photos) {
      if (photo is RuckPhoto) {
        result.add(photo);
      } else if (photo is Map<String, dynamic>) {
        try {
          final ruckPhoto = RuckPhoto(
            id: photo['id'] ?? '',
            ruckId: photo['ruck_id']?.toString() ?? '',
            userId: photo['user_id'] ?? '',
            filename: photo['filename'] ?? '',
            originalFilename: photo['original_filename'],
            contentType: photo['content_type'],
            size: photo['size'],
            createdAt: photo['created_at'] != null 
                ? DateTime.parse(photo['created_at']) 
                : DateTime.now(),
            url: photo['url'],
            thumbnailUrl: photo['thumbnail_url'],
          );
          result.add(ruckPhoto);
        } catch (e) {
          developer.log('[PHOTO_DEBUG] Error converting photo to RuckPhoto: $e', name: 'RuckBuddyCard');
        }
      }
    }
    return result;
  }

  List<String> _getProcessedPhotoUrls(List<dynamic> photos, {bool addCacheBuster = false}) {
    // Only add cache buster when explicitly requested (e.g., after photo upload/delete)
    // This preserves normal caching behavior for better performance
    final shouldBustCache = addCacheBuster; // Only when explicitly requested
    
    // Use a smaller cache value to prevent numerical overflow issues
    final cacheValue = (DateTime.now().millisecondsSinceEpoch % 1000000); // Keep it under 1M
    
    return photos.map((photo) {
      String? url;
      if (photo is RuckPhoto) {
        url = photo.url;
      } else if (photo is Map) {
        url = photo['url'] ?? photo['thumbnail_url'];
      }
      return url is String && url.isNotEmpty 
          ? (shouldBustCache ? '$url?cache=$cacheValue' : url) 
          : '';
    }).where((url) => url.isNotEmpty).toList();
  }

  void _handleLikeTap() {
    if (_isProcessingLike || _ruckId == null) return;

    try {
      // Use ToggleRuckLike event for both liking and unliking
      context.read<SocialBloc>().add(ToggleRuckLike(_ruckId!));
      
      // Optimistically update UI
      setState(() {
        _isLiked = !_isLiked;
        _likeCount = _isLiked ? (_likeCount ?? 0) + 1 : (_likeCount ?? 1) - 1;
        // Ensure like count doesn't go below 0
        if (_likeCount! < 0) _likeCount = 0;
      });
      
      developer.log('[SOCIAL_DEBUG] RuckBuddyCard: Sent ToggleRuckLike event for ruckId: $_ruckId, new status: $_isLiked', name: 'RuckBuddyCard');
      
      HapticFeedback.mediumImpact();
    } catch (e) {
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

    return MultiBlocListener(
      listeners: [
        BlocListener<ActiveSessionBloc, ActiveSessionState>(
          listener: (context, state) {
            if (!mounted || _ruckId == null) return;
            
            // Handle SessionSummaryGenerated state
            if (state is SessionSummaryGenerated && state.session.id == widget.ruckBuddy.id) {
              if (!state.isPhotosLoading && state.photos.isNotEmpty) {
                setState(() {
                  _photos = state.photos;
                  developer.log('[PHOTO_DEBUG] RuckBuddyCard updated photos from SessionSummaryGenerated: ${_photos.length}', name: 'RuckBuddyCard');
                });
              }
            } 
            // Handle ActiveSessionRunning state
            else if (state is ActiveSessionRunning && state.sessionId == widget.ruckBuddy.id) {
              if (!state.isPhotosLoading && state.photos.isNotEmpty) {
                setState(() {
                  _photos = state.photos;
                  developer.log('[PHOTO_DEBUG] RuckBuddyCard updated photos from ActiveSessionRunning: ${_photos.length}', name: 'RuckBuddyCard');
                });
              }
            }
            // We don't need to handle ActiveSessionLoaded since it doesn't exist in this bloc
            // Handle SessionPhotosLoadedForId state
            else if (state is SessionPhotosLoadedForId && state.sessionId.toString() == widget.ruckBuddy.id.toString()) {
              if (state.photos.isNotEmpty) {
                setState(() {
                  _photos = state.photos;
                  developer.log('[PHOTO_DEBUG] RuckBuddyCard updated photos from SessionPhotosLoadedForId: ${_photos.length}', name: 'RuckBuddyCard');
                });
              }
            }
          },
        ),
      ],
      child: BlocConsumer<SocialBloc, SocialState>(
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
          // Only include stable values in the key to prevent unnecessary rebuilds
          final isDarkMode = Theme.of(context).brightness == Brightness.dark;
          return Card(
            key: ValueKey('ruck_card_${widget.ruckBuddy.id}_${_photos.length}'),
            elevation: 3,
            margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 0),
            color: isDarkMode ? Colors.black : null, // Use black in dark mode
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: InkWell(
              onTap: widget.onTap ?? () async {
                // Use await to wait for navigation to complete
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => RuckBuddyDetailScreen(
                      ruckBuddy: widget.ruckBuddy,
                    ),
                  ),
                );
                
                // When returning from detail screen, explicitly refresh photos
                if (mounted && _ruckId != null) {
                  developer.log('[PHOTO_DEBUG] Returned from detail screen for ruckId: $_ruckId - refreshing photos', name: 'RuckBuddyCard');
                  try {
                    // 1. Clear existing photos from state to force a fresh view
                    setState(() {
                      _photos = [];
                    });
                    
                    // 2. Request new photos - first try direct update from ruckBuddy
                    if (widget.ruckBuddy.photos != null && widget.ruckBuddy.photos!.isNotEmpty) {
                      setState(() {
                        _photos = List<RuckPhoto>.from(widget.ruckBuddy.photos!);
                        developer.log('[PHOTO_DEBUG] Directly updated photos from widget after return: ${_photos.length}', name: 'RuckBuddyCard');
                      });
                    }
                    
                    // 3. Also request fresh photos from API through ActiveSessionBloc
                    // This is a belt-and-suspenders approach to ensure we get photos
                    final activeSessionBloc = GetIt.instance<ActiveSessionBloc>();
                    
                    // Clear any existing photos to force a clean fetch
                    activeSessionBloc.add(ClearSessionPhotos(ruckId: widget.ruckBuddy.id));
                    
                    // Then request new ones
                    activeSessionBloc.add(FetchSessionPhotosRequested(widget.ruckBuddy.id));
                    developer.log('[PHOTO_DEBUG] Requested fresh photos from API after return', name: 'RuckBuddyCard');
                  } catch (e) {
                    developer.log('[PHOTO_DEBUG] Error refreshing photos after return: $e', name: 'RuckBuddyCard');
                  }
                }
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // User Info Header with Distance
                    Row(
                      children: [
                        _buildAvatar(widget.ruckBuddy.user),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.ruckBuddy.user?.username ?? 'Anonymous Rucker',
                                style: AppTextStyles.bodyLarge.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
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
                        // Distance stat in header - matching detail page style
                        Text(
                          formattedDistance,
                          style: TextStyle(
                            fontFamily: 'Bangers',
                            fontSize: 28,
                            color: isDarkMode ? Colors.white : Colors.black,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // Map Preview
                    _RouteMapPreview(
                      locationPoints: widget.ruckBuddy.locationPoints,
                      ruckWeightKg: widget.ruckBuddy.ruckWeightKg,
                    ),
                    
                    // Photos Carousel (directly after map with minimal spacing)
                    if (_photos.isNotEmpty) 
                      Builder(builder: (context) {
                        // Force create a new carousel widget each time with unique cache busters
                        final processedUrls = _getProcessedPhotoUrls(_photos, addCacheBuster: true);
                        developer.log('[PHOTO_DEBUG] Building photo carousel with ${processedUrls.length} photos', name: 'RuckBuddyCard');
                        
                        return Container(
                          key: ValueKey('photo_carousel_${DateTime.now().millisecondsSinceEpoch}'),
                          // Remove horizontal padding, only keep vertical spacing
                          margin: EdgeInsets.zero,
                          padding: const EdgeInsets.only(top: 5.0),
                          width: MediaQuery.of(context).size.width,
                          alignment: Alignment.centerLeft,
                          child: PhotoCarousel(
                            photoUrls: processedUrls,
                            height: 140,
                            showDeleteButtons: false,
                            onPhotoTap: (index) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => PhotoViewer(
                                    photoUrls: processedUrls,
                                    initialIndex: index,
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      }),
                    
                    const SizedBox(height: 8),
                    
                    // Stats in a 2x2 grid layout
                    Column(
                      children: [
                        // First row: Time and Elevation
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatTile(
                                context: context,
                                icon: Icons.timer,
                                label: 'Time',
                                value: formattedDuration,
                                compact: true,
                              ),
                            ),
                            Expanded(
                              child: _buildStatTile(
                                context: context,
                                icon: Icons.trending_up,
                                label: 'Elevation',
                                value: formattedElevation,
                                compact: true,
                              ),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 8),
                        
                        // Second row: Pace and Calories
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatTile(
                                context: context,
                                icon: Icons.speed,
                                label: 'Pace',
                                value: formattedPace,
                                compact: true,
                              ),
                            ),
                            Expanded(
                              child: _buildStatTile(
                                context: context,
                                icon: Icons.local_fire_department,
                                label: 'Calories',
                                value: formattedCalories,
                                compact: true,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // Social interactions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        // Like button
                        InkWell(
                          onTap: widget.onLikeTap ?? _handleLikeTap,
                          child: Row(
                            children: [
                              Image.asset(
                                _isLiked 
                                  ? 'assets/images/tactical_ruck_like_icon_active.png'
                                  : 'assets/images/tactical_ruck_like_icon_transparent.png',
                                width: 48,
                                height: 48,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${_likeCount ?? 0}',
                                style: const TextStyle(
                                  fontFamily: 'Bangers',
                                  fontSize: 20,
                                  color: Colors.black,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 20),
                        // Comments count
                        InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => RuckBuddyDetailScreen(
                                  ruckBuddy: widget.ruckBuddy,
                                  focusComment: true, // Auto-focus the comment input field
                                ),
                              ),
                            );
                          },
                          child: Row(
                            children: [
                              Icon(
                                Icons.comment,
                                size: 40,
                                color: AppColors.secondary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${_commentCount ?? 0}',
                                style: const TextStyle(
                                  fontFamily: 'Bangers',
                                  fontSize: 20,
                                  color: Colors.black,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAvatar(UserInfo? user) {
    // Increased size from 40 to 60 (50% larger)
    final double avatarSize = 60.0;
    final double borderRadius = 30.0; // Adjusted border radius
  
    if (user?.photoUrl != null && user!.photoUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: CachedNetworkImage(
          imageUrl: user.photoUrl!,
          width: avatarSize,
          height: avatarSize,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            width: avatarSize,
            height: avatarSize,
            child: const Center(child: CircularProgressIndicator()),
          ),
          errorWidget: (context, url, error) => Container(
            width: avatarSize,
            height: avatarSize,
            padding: const EdgeInsets.all(4),
            // No background color
            child: Image.asset(
              user.gender?.toLowerCase() == 'female' 
                ? 'assets/images/lady rucker profile.png'
                : 'assets/images/profile.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
      );
    } else {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Container(
          width: avatarSize,
          height: avatarSize,
          padding: const EdgeInsets.all(4),
          // No background color
          child: Image.asset(
            user?.gender?.toLowerCase() == 'female' 
              ? 'assets/images/lady rucker profile.png'
              : 'assets/images/profile.png',
            fit: BoxFit.contain,
          ),
        ),
      );
    }  
  }

  String _formatCompletedDate(DateTime? completedAt) {
    if (completedAt == null) return 'Unknown date';
    return DateFormat('MMM d, yyyy • h:mm a').format(completedAt);
  }

  Widget _buildStatTile({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
    bool compact = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              color: AppColors.secondary,
              size: compact ? 16 : 20,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: Colors.grey[600],
                fontSize: compact ? 12 : 14,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTextStyles.bodyMedium.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: compact ? 16 : 22,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _RouteMapPreview extends StatefulWidget {
  final List<dynamic>? locationPoints;
  final double? ruckWeightKg; // Add weight parameter

  const _RouteMapPreview({
    required this.locationPoints,
    this.ruckWeightKg,
  });
  
  @override
  State<_RouteMapPreview> createState() => _RouteMapPreviewState();
}

class _RouteMapPreviewState extends State<_RouteMapPreview> {
  // Cache the map widget to prevent rebuilding during scrolling
  FlutterMap? _cachedMapWidget;
  List<LatLng>? _cachedRoutePoints;
  late final Key _mapKey;
  
  @override
  void initState() {
    super.initState();
    _mapKey = UniqueKey();
  }
  
  // Helper method to compare route points for equality
  bool _areRoutePointsEqual(List<LatLng> list1, List<LatLng> list2) {
    if (list1.length != list2.length) return false;
    for (int i = 0; i < list1.length; i++) {
      if (list1[i].latitude != list2[i].latitude || 
          list1[i].longitude != list2[i].longitude) {
        return false;
      }
    }
    return true;
  }

  double? _parseCoord(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  List<LatLng> _getRoutePoints() {
    final pts = <LatLng>[];
    final lp = widget.locationPoints;
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
    final String weightText = widget.ruckWeightKg != null ? '${widget.ruckWeightKg!.toStringAsFixed(1)} kg' : '';

    if (routePoints.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            Container(
              height: 175,
              width: double.infinity,
              color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[900] : Colors.grey[200],
              child: Center(
                child: Icon(
                  Icons.map_outlined,
                  size: 48,
                  color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[600] : Colors.grey[400],
                ),
              ),
            ),
            // Weight chip overlay
            if (widget.ruckWeightKg != null)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.secondary,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Text(
                    weightText,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    // Only rebuild the map if the route points have changed
    if (_cachedMapWidget == null || 
        _cachedRoutePoints == null || 
        !_areRoutePointsEqual(_cachedRoutePoints!, routePoints)) {
      _cachedRoutePoints = List.from(routePoints);
      _cachedMapWidget = FlutterMap(
        key: _mapKey,
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
            // Add tile caching for performance
            tileProvider: NetworkTileProvider(),
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

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        children: [
          SizedBox(
            height: 175,
            width: double.infinity,
            child: _cachedMapWidget!,
          ),
          // Weight chip overlay
          if (widget.ruckWeightKg != null)
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.secondary,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Text(
                  weightText,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: Colors.white,
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