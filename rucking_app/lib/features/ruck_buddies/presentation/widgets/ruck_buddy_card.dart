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
import 'package:rucking_app/features/ruck_buddies/domain/entities/user_info.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/photo/photo_carousel.dart';
import 'package:rucking_app/shared/widgets/photo/photo_viewer.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_photo.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_session.dart'; // Also provides RuckStatus enum
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
  // Track local state for immediate feedback
  int? _likeCount;
  bool _isLiked = false;
  bool _isProcessingLike = false;
  String? _userId;
  // Initialize photos as empty list instead of null to avoid null safety issues
  List<RuckPhoto> _photos = [];
  // We calculate and store pace locally since RuckBuddy doesn't have averagePace
  double _calculatedPace = 0.0;

  @override
  void initState() {
    super.initState();
    _likeCount = widget.ruckBuddy.likeCount;
    // Always initialize _photos as a non-null list
    _photos = widget.ruckBuddy.photos != null ? List<RuckPhoto>.from(widget.ruckBuddy.photos!) : [];
    
    // Check if this ruck is already liked
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // Extract the ID first, converting from String to int safely
        final ruckIdStr = widget.ruckBuddy.id;
        final ruckId = int.tryParse(ruckIdStr);

        if (ruckId != null) {
          // Quietly check if user has liked this ruck
          context.read<SocialBloc>().add(CheckUserLikeStatus(ruckId));
          developer.log('RuckBuddyCard initState: Ruck ID $ruckId - Dispatching CheckUserLikeStatus', name: 'RuckBuddyCard');
          
          // Always fetch photos for this ruck to ensure consistency
          developer.log('[PHOTO_DEBUG] RuckBuddyCard initState: Ruck ID $ruckIdStr - Fetching photos. Initial count: ${_photos.length}', name: 'RuckBuddyCard');
          final activeSessionBloc = GetIt.instance<ActiveSessionBloc>();
          
          // Request photos from the bloc - must use string ID
          activeSessionBloc.add(FetchSessionPhotosRequested(ruckIdStr));
          
          // First, convert the RuckBuddy to a RuckSession to properly prime the bloc
          // This mimics what LoadSessionForViewing does in the detail screen
          final startedAt = widget.ruckBuddy.startedAt ?? DateTime.now();
          final completedAt = widget.ruckBuddy.completedAt ?? DateTime.now().add(const Duration(minutes: 30));
          final sessionDuration = completedAt.difference(startedAt);
          
          // Calculate pace manually since RuckBuddy doesn't have averagePace
          // Handle null safety for all fields
          final double distanceKm = widget.ruckBuddy.distanceKm ?? 0.0;
          final int durationSeconds = widget.ruckBuddy.durationSeconds ?? 0;
          
          final double calculatedPace = 
              (distanceKm > 0 && durationSeconds > 0)
              ? (durationSeconds / 60) / distanceKm 
              : 0.0;
          
          // Store the calculated pace locally for UI display too
          _calculatedPace = calculatedPace;
          
          final ruckSession = RuckSession(
            id: ruckIdStr,
            startTime: startedAt,
            endTime: completedAt,
            duration: sessionDuration,
            distance: widget.ruckBuddy.distanceKm,
            elevationGain: widget.ruckBuddy.elevationGainM,
            elevationLoss: widget.ruckBuddy.elevationLossM,
            caloriesBurned: widget.ruckBuddy.caloriesBurned,
            averagePace: calculatedPace,
            ruckWeightKg: widget.ruckBuddy.ruckWeightKg,
            // Must provide RuckStatus
            status: RuckStatus.completed,
            // Convert location points if available
            locationPoints: widget.ruckBuddy.locationPoints?.cast<Map<String, dynamic>>(),
          );
          
          // Load session into bloc first - this sets up the proper state
          developer.log('RuckBuddyCard initState: Ruck ID $ruckId - Dispatching LoadSessionForViewing', name: 'RuckBuddyCard');
          activeSessionBloc.add(LoadSessionForViewing(sessionId: ruckIdStr, session: ruckSession));
          
          // Then request photos for that session
          // The bloc will now be in the proper state to handle this request
          developer.log('RuckBuddyCard initState: Ruck ID $ruckId - Dispatching FetchSessionPhotosRequested', name: 'RuckBuddyCard');
          activeSessionBloc.add(FetchSessionPhotosRequested(ruckIdStr));
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
        _likeCount = (_likeCount ?? 0) > 0 ? (_likeCount ?? 0) - 1 : 0;
      } else {
        _likeCount = (_likeCount ?? 0) + 1;
      }
      _isLiked = !_isLiked;
      
      // Only set processing to true AFTER the icon has changed
      // This ensures the user sees the heart change before any loading indicator
      _isProcessingLike = true;
    });
    
    // Dispatch event to update backend
    final ruckIdStr = widget.ruckBuddy.id;
    final ruckId = int.tryParse(ruckIdStr);
    if (ruckId != null) {
      // Directly update backend through SocialBloc - this ensures per-ruck state
      context.read<SocialBloc>().add(ToggleRuckLike(ruckId));
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
    
    // Check if we have photos either locally or from the original buddy data
    final hasPhotos = _photos.isNotEmpty;
    
    return MultiBlocListener(
      listeners: [
        BlocListener<ActiveSessionBloc, ActiveSessionState>(
          bloc: GetIt.instance<ActiveSessionBloc>(),
          listener: (context, state) {
            developer.log('[PHOTO_DEBUG] RuckBuddyCard listener: Received state ${state.runtimeType}', name: 'RuckBuddyCard');
            
            // Handle SessionSummaryGenerated state - the most common for completed sessions
            if (state is SessionSummaryGenerated && state.session.id == widget.ruckBuddy.id) {
              developer.log('[PHOTO_DEBUG] RuckBuddyCard: Received SessionSummaryGenerated for session ${state.session.id} with ${state.photos.length} photos', name: 'RuckBuddyCard');
              
              if (mounted && state.photos.isNotEmpty) {
                // Extract photo URLs for logging
                final photoUrls = state.photos.map((p) {
                  if (p is RuckPhoto) {
                    final url = p.url;
                    final thumbnailUrl = p.thumbnailUrl;
                    if (url != null && url.isNotEmpty) return url;
                    if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) return thumbnailUrl;
                  }
                  return '';
                }).where((url) => url.isNotEmpty).toList();
                
                if (photoUrls.isNotEmpty) {
                  developer.log('[PHOTO_DEBUG] RuckBuddyCard: First photo URL: ${photoUrls.first}', name: 'RuckBuddyCard');
                }
                
                developer.log('[PHOTO_DEBUG] RuckBuddyCard: Updating photos for card ${widget.ruckBuddy.id} with ${state.photos.length} photos', name: 'RuckBuddyCard');
                setState(() {
                  // Properly convert each dynamic object to RuckPhoto
                  _photos = state.photos.map((dynamic photo) {
                    if (photo is RuckPhoto) {
                      return photo;
                    }
                    // If it's a Map, convert it to RuckPhoto
                    if (photo is Map<String, dynamic>) {
                      return RuckPhoto(
                        id: photo['id'] as String? ?? '',
                        ruckId: photo['ruck_id'] != null ? photo['ruck_id'].toString() : '',
                        userId: photo['user_id'] as String? ?? '',
                        filename: photo['filename'] as String? ?? '',
                        originalFilename: photo['original_filename'] as String?,
                        contentType: photo['content_type'] as String?,
                        size: photo['size'] as int?,
                        createdAt: photo['created_at'] != null 
                            ? DateTime.parse(photo['created_at'] as String) 
                            : DateTime.now(),
                        url: photo['url'] as String?,
                        thumbnailUrl: photo['thumbnail_url'] as String?,
                      );
                    }
                    // Fallback empty photo (shouldn't happen)
                    return RuckPhoto(
                      id: '',
                      ruckId: '',
                      userId: '',
                      filename: '',
                      createdAt: DateTime.now(),
                    );
                  }).toList().cast<RuckPhoto>();
                });
              }
            }
            // Handle ActiveSessionRunning state
            else if (state is ActiveSessionRunning && state.sessionId == widget.ruckBuddy.id) {
              developer.log('[PHOTO_DEBUG] RuckBuddyCard: Received ActiveSessionRunning for session ${state.sessionId} with ${state.photos.length} photos', name: 'RuckBuddyCard');
              
              if (mounted && state.photos.isNotEmpty) {
                developer.log('[PHOTO_DEBUG] RuckBuddyCard: Updating photos for card ${widget.ruckBuddy.id} with ${state.photos.length} photos', name: 'RuckBuddyCard');
                setState(() {
                  // Properly convert each dynamic object to RuckPhoto
                  _photos = state.photos.map((dynamic photo) {
                    if (photo is RuckPhoto) {
                      return photo;
                    }
                    // If it's a Map, convert it to RuckPhoto
                    if (photo is Map<String, dynamic>) {
                      return RuckPhoto(
                        id: photo['id'] as String? ?? '',
                        ruckId: photo['ruck_id'] != null ? photo['ruck_id'].toString() : '',
                        userId: photo['user_id'] as String? ?? '',
                        filename: photo['filename'] as String? ?? '',
                        originalFilename: photo['original_filename'] as String?,
                        contentType: photo['content_type'] as String?,
                        size: photo['size'] as int?,
                        createdAt: photo['created_at'] != null 
                            ? DateTime.parse(photo['created_at'] as String) 
                            : DateTime.now(),
                        url: photo['url'] as String?,
                        thumbnailUrl: photo['thumbnail_url'] as String?,
                      );
                    }
                    // Fallback empty photo
                    return RuckPhoto(
                      id: '',
                      ruckId: '',
                      userId: '',
                      filename: '',
                      createdAt: DateTime.now(),
                    );
                  }).toList().cast<RuckPhoto>();
                });
              }
            }
            // Handle ActiveSessionInitial state
            else if (state is ActiveSessionInitial && state.viewedSession != null && state.photos.isNotEmpty) {
              final sessionId = state.viewedSession?.id;
              developer.log('[PHOTO_DEBUG] RuckBuddyCard: Received ActiveSessionInitial with ${state.photos.length} photos for session $sessionId', name: 'RuckBuddyCard');
              
              if (mounted && sessionId == widget.ruckBuddy.id) {
                developer.log('[PHOTO_DEBUG] RuckBuddyCard: Updating photos for card with ${state.photos.length} photos', name: 'RuckBuddyCard');
                setState(() {
                  // Properly convert each dynamic object to RuckPhoto
                  _photos = state.photos.map((dynamic photo) {
                    if (photo is RuckPhoto) {
                      return photo;
                    }
                    // If it's a Map, convert it to RuckPhoto
                    if (photo is Map<String, dynamic>) {
                      return RuckPhoto(
                        id: photo['id'] as String? ?? '',
                        ruckId: photo['ruck_id'] != null ? photo['ruck_id'].toString() : '',
                        userId: photo['user_id'] as String? ?? '',
                        filename: photo['filename'] as String? ?? '',
                        originalFilename: photo['original_filename'] as String?,
                        contentType: photo['content_type'] as String?,
                        size: photo['size'] as int?,
                        createdAt: photo['created_at'] != null 
                            ? DateTime.parse(photo['created_at'] as String) 
                            : DateTime.now(),
                        url: photo['url'] as String?,
                        thumbnailUrl: photo['thumbnail_url'] as String?,
                      );
                    }
                    // Fallback empty photo
                    return RuckPhoto(
                      id: '',
                      ruckId: '',
                      userId: '',
                      filename: '',
                      createdAt: DateTime.now(),
                    );
                  }).toList().cast<RuckPhoto>();
                });
              }
            }
          },
        ), 
        BlocListener<SocialBloc, SocialState>(
      listenWhen: (previous, current) {
        // Listen for like action completions and status checks
        // Only respond to states related to THIS specific ruck
        final thisRuckIdStr = widget.ruckBuddy.id;
        final thisRuckId = int.tryParse(thisRuckIdStr);
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
        // Also listen for batch status updates that include this ruck
        if (current is BatchLikeStatusChecked) {
          return current.likeStatusMap.containsKey(thisRuckId);
        }
        return false;
      },
      listener: (context, state) {
        final thisRuckIdStr = widget.ruckBuddy.id;
        final thisRuckId = int.tryParse(thisRuckIdStr);
        if (thisRuckId == null) return;
        
        if (state is LikeActionCompleted && state.ruckId == thisRuckId) {
          developer.log('RuckBuddyCard SocialBloc Listener: Ruck ID ${state.ruckId} - LikeActionCompleted', name: 'RuckBuddyCard');
          setState(() {
            _isLiked = state.isLiked;
            _likeCount = state.likeCount; // Use the count from the state
            _isProcessingLike = false;
          });
        } else if (state is LikeActionError && state.ruckId == thisRuckId) {
          developer.log('RuckBuddyCard SocialBloc Listener: Ruck ID ${state.ruckId} - LikeActionError: ${state.message}', name: 'RuckBuddyCard');
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
              _likeCount = (_likeCount ?? 0) > 0 ? (_likeCount ?? 0) - 1 : 0;
            } else {
              _likeCount = (_likeCount ?? 0) + 1;
            }
            _isProcessingLike = false;
          });
        } else if (state is LikesLoaded && state.ruckId == thisRuckId) {
          developer.log('RuckBuddyCard SocialBloc Listener: Ruck ID ${state.ruckId} - LikesLoaded', name: 'RuckBuddyCard');
          setState(() {
            _isLiked = state.userHasLiked;
            _likeCount = state.likes.length;
            _isProcessingLike = false;
          });
        } else if (state is BatchLikeStatusChecked && state.likeStatusMap.containsKey(thisRuckId)) {
          final isLiked = state.likeStatusMap[thisRuckId] ?? false;
          developer.log('RuckBuddyCard SocialBloc Listener: Ruck ID ${thisRuckId} - BatchLikeStatusChecked', name: 'RuckBuddyCard');
          setState(() {
            _isLiked = isLiked;
            // Note: We keep the current _likeCount as the batch check doesn't update count
            _isProcessingLike = false;
          });
        }
      },
        ), // Close SocialBloc listener
      ], // Close listeners array
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            // Reduce overall padding to save space
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 580.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min, // Ensure Column is as tall as its content or minHeight
                children: [
                  // User Info Row
                  Builder(builder: (context) {
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
                              if (widget.ruckBuddy.completedAt != null) // Added null check here
                                Text(
                                  _formatCompletedDate(widget.ruckBuddy.completedAt!), // Safely use '!' because of the null check above
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

                  // Map snippet with reduced height
                  Builder(builder: (context) {
                    return SizedBox(
                      // Set a fixed height for the map
                      height: 220, // Restored original height
                      child: _RouteMapPreview(
                        locationPoints: widget.ruckBuddy.locationPoints,
                        // No longer passing photos to the map preview
                      ),
                    );
                  }), // End of Map Builder
                
                  // Photos carousel builder
                  Builder(builder: (context) {
                    // Log photo count for debugging
                    developer.log('RuckBuddyCard build: Photos count for ${widget.ruckBuddy.id}: ${_photos.length}', name: 'RuckBuddyCard');
                    
                    // Only show carousel if photos exist
                    if (_photos.isEmpty) return const SizedBox.shrink();
                    
                    // Show photo carousel with photos
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 8), // Reduced spacing
                        Container(
                          height: 40, // Reduced height to make thumbnails half size
                          margin: const EdgeInsets.only(bottom: 8), // Reduced margin
                          child: PhotoCarousel(
                            photoUrls: _photos.map((photo) => photo.url ?? '').toList(), 
                            showDeleteButtons: false,
                            onPhotoTap: (index) {
                              // View photo full screen
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => PhotoViewer(
                                    photoUrls: _photos.map((photo) => photo.url ?? '').toList(),
                                    initialIndex: index,
                                    title: '${widget.ruckBuddy.user.username}\'s Ruck',
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  }),

                  const Divider(height: 16), // Reduced divider height
                
                  // Ultra-compact Stats Grid - designed to minimize space while keeping information readable
                  Builder(builder: (context) {
                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      margin: EdgeInsets.zero,
                      constraints: const BoxConstraints(maxHeight: 100), // Enforce maximum height
                      child: Row(
                        children: [
                          // Left column
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min, // Use minimum vertical space
                              children: [
                                _buildStatTile(
                                  context: context,
                                  icon: Icons.straighten, 
                                  label: 'Distance',
                                  value: MeasurementUtils.formatDistance(widget.ruckBuddy.distanceKm ?? 0.0, metric: preferMetric),
                                  compact: true, // Use compact mode
                                ),
                                const SizedBox(height: 4), // minimal spacing
                                _buildStatTile(
                                  context: context,
                                  icon: Icons.local_fire_department, 
                                  label: 'Calories',
                                  value: '${widget.ruckBuddy.caloriesBurned ?? 0} kcal',
                                  compact: true, // Use compact mode
                                ),
                              ],
                            ),
                          ),
                          
                          const SizedBox(width: 8), // minimal spacing
                          
                          // Right column
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min, // Use minimum vertical space
                              children: [
                                _buildStatTile(
                                  context: context,
                                  icon: Icons.timer, 
                                  label: 'Duration',
                                  value: MeasurementUtils.formatDuration(Duration(seconds: widget.ruckBuddy.durationSeconds ?? 0)),
                                  compact: true, // Use compact mode
                                ),
                                const SizedBox(height: 4), // minimal spacing
                                _buildStatTile(
                                  context: context,
                                  icon: Icons.terrain, 
                                  label: 'Elevation',
                                  value: MeasurementUtils.formatElevationCompact(widget.ruckBuddy.elevationGainM, widget.ruckBuddy.elevationLossM.abs(), metric: preferMetric),
                                  compact: true, // Use compact mode
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }), // End of Stats Grid Builder

                  const SizedBox(height: 16),

                  // Ultra compact social interactions row
                  Builder(builder: (context) {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        // Like button with count - more compact
                        InkWell(
                          onTap: _handleLikeTap,
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 2.0),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Smaller icon
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
                                    fontSize: 20, // Smaller font
                                    color: Colors.grey[800],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        
                        const SizedBox(width: 10), // Reduced spacing
                        
                        // Comments count with tap action - more compact
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
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 2.0),
                            child: Row(children: [
                              Icon(
                                Icons.comment,
                                size: 30, // Smaller icon
                                color: AppColors.secondary,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                '${widget.ruckBuddy.commentCount}',
                                style: TextStyle(
                                  fontFamily: 'Bangers',
                                  fontSize: 20, // Smaller font
                                  color: Colors.grey[800],
                                ),
                              ),
                            ]),
                          ),
                        ),
                      ],
                    );
                  }), // End of Action Buttons Builder
                ],
              ),
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
    bool compact = false, // Added compact mode parameter
  }) {
    return Row(
      children: [
        Icon(
          icon, 
          size: compact ? 16 : 20,  // Smaller icon in compact mode
          color: AppColors.secondary,
        ),
        SizedBox(width: compact ? 4 : 8), // Smaller spacing in compact mode
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min, // Minimize vertical space
            children: [
              Text(
                label,
                style: AppTextStyles.bodySmall.copyWith(
                  color: Colors.grey[600],
                  fontSize: compact ? 10 : null, // Smaller font in compact mode
                ),
              ),
              Text(
                value,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: compact ? 12 : null, // Smaller font in compact mode
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
  
  // Process photo URLs with cache busting parameters
  List<String> _getProcessedUrls() {
    developer.log('[PHOTO_DEBUG] _PhotoThumbnailsOverlay: Processing ${photos.length} photos', name: 'RuckBuddyCard');
    
    // More robust approach that handles both URLs and falls back to thumbnails
    final photoUrls = photos.map((p) {
      final url = p.url;
      final thumbnailUrl = p.thumbnailUrl;
      
      developer.log('[PHOTO_DEBUG] _PhotoThumbnailsOverlay: Photo ${p.id} has URL: $url, thumbnail: $thumbnailUrl', name: 'RuckBuddyCard');
      
      // Prefer main URL, fall back to thumbnail if main is empty/null
      if (url != null && url.isNotEmpty) {
        return url;
      } else if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
        return thumbnailUrl;
      }
      return '';
    })
    .where((url) => url.isNotEmpty)
    .toList();
    
    developer.log('[PHOTO_DEBUG] _PhotoThumbnailsOverlay: Extracted ${photoUrls.length} valid URLs', name: 'RuckBuddyCard');
    
    // Add cache busting parameters to URLs
    return photoUrls.map((url) {
      final cacheBuster = DateTime.now().millisecondsSinceEpoch;
      return url.contains('?') ? '$url&t=$cacheBuster' : '$url?t=$cacheBuster';
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    // Process URLs with cache busting
    final processedUrls = _getProcessedUrls();
    
    // Show up to maxDisplay photos, with a +X indicator if there are more
    final displayCount = processedUrls.length > maxDisplay ? maxDisplay : processedUrls.length;
    final hasMore = processedUrls.length > maxDisplay;
    
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
                  child: index < processedUrls.length
                      ? CachedNetworkImage(
                          imageUrl: processedUrls[index],
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
  final List<dynamic>? locationPoints;
  final List<RuckPhoto>? photos;

  const _RouteMapPreview({
    required this.locationPoints,
    this.photos,
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
      child: Stack(
        children: [
          SizedBox(
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
          // Show photo thumbnails overlay if available
          if (photos != null && photos!.isNotEmpty)
            Positioned(
              bottom: 8,
              left: 8,
              child: _PhotoThumbnailsOverlay(
                photos: photos!,
                maxDisplay: 3,
              ),
            ),
        ],
      ),
    );
  }
}
