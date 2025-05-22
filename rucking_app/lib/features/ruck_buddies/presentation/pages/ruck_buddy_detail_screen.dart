import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Import for HapticFeedback
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import 'package:rucking_app/core/utils/measurement_utils.dart';
import 'package:rucking_app/core/utils/location_utils.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/ruck_buddies/domain/entities/ruck_buddy.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_photo.dart';
import 'package:rucking_app/features/social/presentation/widgets/comments_section.dart';
import 'package:rucking_app/features/social/presentation/bloc/social_bloc.dart';
import 'package:rucking_app/features/social/presentation/bloc/social_event.dart';
import 'package:rucking_app/features/social/presentation/bloc/social_state.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/photo/photo_viewer.dart';
import 'package:rucking_app/shared/widgets/photo/photo_carousel.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';

class RuckBuddyDetailScreen extends StatefulWidget {
  final RuckBuddy ruckBuddy;
  final bool focusComment;

  const RuckBuddyDetailScreen({
    Key? key,
    required this.ruckBuddy,
    this.focusComment = false, // Added parameter to trigger comment field focus
  }) : super(key: key);

  @override
  State<RuckBuddyDetailScreen> createState() => _RuckBuddyDetailScreenState();
}

class _RuckBuddyDetailScreenState extends State<RuckBuddyDetailScreen> {
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode(); // Added focus node for comment field
  bool _isLiked = false;
  List<RuckPhoto> _photos = [];
  int _likeCount = 0;
  int _commentCount = 0; // Added comment count state variable
  bool _isProcessingLike = false;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.ruckBuddy.isLikedByCurrentUser;
    _likeCount = widget.ruckBuddy.likeCount;
    _commentCount = widget.ruckBuddy.commentCount; // Initialize comment count
    _photos = widget.ruckBuddy.photos ?? [];

    // Always fetch photos for ruck buddies, as they're not included in the initial RuckBuddy model
    if (widget.ruckBuddy.id.isNotEmpty) {
      // Make sure we get photos on screen initialization with a small delay to ensure the bloc is ready
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && GetIt.I.isRegistered<ActiveSessionBloc>()) {
          final activeSessionBloc = GetIt.instance<ActiveSessionBloc>();
          print('[PHOTO_DEBUG] RuckBuddyDetailScreen: Fetching photos for ${widget.ruckBuddy.id} from ActiveSessionBloc.');
          // Request photos from the bloc
          try {
            final ruckId = widget.ruckBuddy.id;
            print('[PHOTO_DEBUG] RuckBuddyDetailScreen: Dispatching FetchSessionPhotosRequested event with ruckId: $ruckId');
            // Force the bloc to fetch fresh photos
            activeSessionBloc.add(FetchSessionPhotosRequested(ruckId));
          } catch (e) {
            print('[PHOTO_DEBUG] RuckBuddyDetailScreen: Error requesting photos for ID ${widget.ruckBuddy.id}: $e');
          }
        } else {
          print('[PHOTO_DEBUG] RuckBuddyDetailScreen: ActiveSessionBloc not registered or widget not mounted');
        }
      });
    } else {
      print('[PHOTO_DEBUG] RuckBuddyDetailScreen: Empty ruckBuddy.id, can\'t fetch photos');
    }
    
    // Check current like status through SocialBloc
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final ruckId = int.tryParse(widget.ruckBuddy.id);
        if (ruckId != null) {
          // Use the singleton instance of SocialBloc from GetIt
          final socialBloc = GetIt.instance<SocialBloc>();
          
          // First ensure we're getting the latest state
          socialBloc.add(CheckRuckLikeStatus(ruckId));
          
          // Important debug logging
          print('[SOCIAL_DEBUG] RuckBuddyDetailScreen: Checking like status for ruckId $ruckId');
        }
      }
    });
    
    // If focusComment is true, request focus on the comment field after build
    if (widget.focusComment) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _commentFocusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocusNode.dispose(); // Clean up focus node
    super.dispose();
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

  void _submitComment() {
    if (_commentController.text.trim().isEmpty) return;

    // Dispatch AddRuckComment to SocialBloc
    context.read<SocialBloc>().add(
      AddRuckComment(
        ruckId: widget.ruckBuddy.id,
        content: _commentController.text.trim(),
      ),
    );

    _commentController.clear();
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
    
    return BlocListener<ActiveSessionBloc, ActiveSessionState>(
      bloc: GetIt.instance<ActiveSessionBloc>(),
      listenWhen: (previous, current) {
        print('[PHOTO_DEBUG] RuckBuddyDetailScreen listenWhen: previous=${previous.runtimeType}, current=${current.runtimeType}');
        
        // Helper function to get photos from any state type that might contain them
        List<dynamic> getPhotosFromState(ActiveSessionState state) {
          if (state is SessionSummaryGenerated) return state.photos;
          if (state is ActiveSessionRunning) return state.photos;
          if (state is ActiveSessionInitial) return state.photos;
          if (state is SessionPhotosLoadedForId && state.sessionId.toString() == widget.ruckBuddy.id.toString()) return state.photos;
          return [];
        }
        
        final prevPhotos = getPhotosFromState(previous);
        final currPhotos = getPhotosFromState(current);
        
        print('[PHOTO_DEBUG] RuckBuddyDetailScreen listenWhen: previousPhotos=${prevPhotos.length}, currentPhotos=${currPhotos.length}');
        
        // Only trigger listener when photos change
        final bool photosChanged = prevPhotos != currPhotos;
        
        print('[PHOTO_DEBUG] RuckBuddyDetailScreen listenWhen: ${photosChanged ? "PHOTOS CHANGED" : "no change"}');
        return photosChanged;
      },
      listener: (context, state) {
        print('[PHOTO_DEBUG] RuckBuddyDetailScreen listener: Received state ${state.runtimeType}');
        
        List<dynamic> statePhotos = [];
        if (state is SessionSummaryGenerated) {
          statePhotos = state.photos;
          print('[PHOTO_DEBUG] RuckBuddyDetailScreen: Found ${statePhotos.length} photos in SessionSummaryGenerated state');
        } else if (state is ActiveSessionInitial) {
          statePhotos = state.photos;
          print('[PHOTO_DEBUG] RuckBuddyDetailScreen: Found ${statePhotos.length} photos in ActiveSessionInitial state');
        } else if (state is ActiveSessionRunning) {
          statePhotos = state.photos;
          print('[PHOTO_DEBUG] RuckBuddyDetailScreen: Found ${statePhotos.length} photos in ActiveSessionRunning state');
        } else if (state is SessionPhotosLoadedForId && state.sessionId.toString() == widget.ruckBuddy.id.toString()) {
          // Handle the SessionPhotosLoadedForId state which is emitted by our updated ActiveSessionBloc
          statePhotos = state.photos;
          print('[PHOTO_DEBUG] RuckBuddyDetailScreen: Found ${statePhotos.length} photos in SessionPhotosLoadedForId state');
        }
        
        // Extract photo URLs and log them for debugging
        final photoUrls = _extractPhotoUrls(statePhotos);
        print('[PHOTO_DEBUG] RuckBuddyDetailScreen: Extracted ${photoUrls.length} valid photo URLs from ${statePhotos.length} photos');
        if (photoUrls.isNotEmpty) {
          print('[PHOTO_DEBUG] RuckBuddyDetailScreen: First URL: ${photoUrls.first}');
        }
        
        // Check if new photos are available and update
        if (statePhotos.isNotEmpty && mounted) {
          print('[PHOTO_DEBUG] RuckBuddyDetailScreen: Updating UI with ${statePhotos.length} photos');
          setState(() {
            // Properly convert each dynamic object to RuckPhoto to match the expected type
            _photos = statePhotos.map((photo) {
              if (photo is RuckPhoto) {
                return photo;
              }
              // If it's a Map, convert it to RuckPhoto
              if (photo is Map<String, dynamic>) {
                return RuckPhoto(
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
              }
              // Fallback empty photo (shouldn't happen)
              return RuckPhoto(
                id: '',
                ruckId: '',
                userId: '',
                filename: '',
                createdAt: DateTime.now(), // Use current time as fallback
              );
            }).toList().cast<RuckPhoto>();
          });
        }
      },
      child: BlocListener<SocialBloc, SocialState>(
        listener: (context, state) {
          final ruckId = int.tryParse(widget.ruckBuddy.id);
          if (ruckId == null) return;
          
          if (state is LikeStatusChecked) {
            if (state.ruckId == ruckId) {
              setState(() {
                _isLiked = state.isLiked;
                _likeCount = state.likeCount;
                _isProcessingLike = false;
              });
              print('[SOCIAL_DEBUG] RuckBuddyDetailScreen: LikeStatusChecked for ruckId: ${state.ruckId}, isLiked: ${state.isLiked}, likeCount: ${state.likeCount}');
            }
          } else if (state is LikeActionCompleted) {
            if (state.ruckId == ruckId) {
              setState(() {
                _isLiked = state.isLiked;
                _likeCount = state.likeCount;
                _isProcessingLike = false;
              });
              print('[SOCIAL_DEBUG] RuckBuddyDetailScreen: LikeActionCompleted for ruckId: ${state.ruckId}, isLiked: ${state.isLiked}, likeCount: ${state.likeCount}');
            }
          } else if (state is CommentCountUpdated) {
            if (state.ruckId == ruckId) {
              setState(() {
                _commentCount = state.count;
              });
              print('[SOCIAL_DEBUG] RuckBuddyDetailScreen: CommentCountUpdated for ruckId: ${state.ruckId}, new commentCount: ${state.count}');
            }
          }
        },  
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Ruck Details'),
            actions: [
              // IconButton(
              //   icon: const Icon(Icons.share),
              //   onPressed: () {
              //     ScaffoldMessenger.of(context).showSnackBar(
              //       const SnackBar(
              //         content: Text('Sharing coming soon!'),
              //         duration: Duration(seconds: 2),
              //       ),
              //     );
              //   },
              // ),
            ],
          ),
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // User info, date, and distance
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      // Gender-appropriate avatar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: Container(
                          width: 60,
                          height: 60,
                          padding: const EdgeInsets.all(4),
                          child: widget.ruckBuddy.user?.photoUrl != null && widget.ruckBuddy.user!.photoUrl!.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: widget.ruckBuddy.user!.photoUrl!,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
                                errorWidget: (context, url, error) => Image.asset(
                                  widget.ruckBuddy.user?.gender?.toLowerCase() == 'female' 
                                    ? 'assets/images/lady rucker profile.png'
                                    : 'assets/images/profile.png',
                                  fit: BoxFit.contain,
                                ),
                              )
                            : Image.asset(
                                widget.ruckBuddy.user?.gender?.toLowerCase() == 'female' 
                                  ? 'assets/images/lady rucker profile.png'
                                  : 'assets/images/profile.png',
                                fit: BoxFit.contain,
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
                      
                      // Distance badge at right side of header
                      Text(
                        MeasurementUtils.formatDistance(
                          widget.ruckBuddy.distanceKm,
                          metric: context.read<AuthBloc>().state is Authenticated
                            ? (context.read<AuthBloc>().state as Authenticated).user.preferMetric
                            : true,
                        ),
                        style: TextStyle(
                          fontFamily: 'Bangers',
                          fontSize: 28,
                          color: Colors.black,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),

                // Route Map with ruck weight
                SizedBox(
                  height: 250,
                  width: double.infinity,
                  child: _RouteMap(
                    locationPoints: widget.ruckBuddy.locationPoints,
                    ruckWeightKg: widget.ruckBuddy.ruckWeightKg,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                  child: FutureBuilder<String>(
                    future: LocationUtils.getLocationName(widget.ruckBuddy.locationPoints),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Text(
                          'Could not determine location',
                          style: AppTextStyles.bodySmall.copyWith(color: Colors.grey),
                          textAlign: TextAlign.center,
                        );
                      }
                      if (snapshot.hasData && snapshot.data!.isNotEmpty && snapshot.data! != 'Unknown location') {
                        return Text(
                          snapshot.data!,
                          style: TextStyle(
                            fontFamily: 'Bangers',
                            fontSize: 26,
                            color: AppColors.primary,
                            letterSpacing: 1.2,
                          ),
                          textAlign: TextAlign.center,
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),
                
                // Photos section - moved directly after map and location
                if (_photos.isNotEmpty) ...[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // RUCK SHOTS title with matching padding as geolocation
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        child: Text(
                          'RUCK SHOTS', 
                          style: TextStyle(
                            fontFamily: 'Bangers',
                            fontSize: 26,
                            letterSpacing: 1.2,
                            color: AppColors.secondary,
                          ),
                        ),
                      ),
                      // Make carousel flush with left edge
                      Container(
                        margin: EdgeInsets.zero,
                        padding: EdgeInsets.zero,
                        child: PhotoCarousel(
                          photoUrls: _extractPhotoUrls(_photos),
                          showDeleteButtons: false,
                          height: 200, // Medium-sized tiles
                          onPhotoTap: (index) {
                            // View photo full screen
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => PhotoViewer(
                                  photoUrls: _extractPhotoUrls(_photos),
                                  initialIndex: index,
                                  title: '${widget.ruckBuddy.user.username}\'s Ruck',
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const Divider(),
                ],
                
                // Ruck details
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Stats grid in a 2x2 layout
                      
                      // First row: Time and Elevation
                      Row(
                        children: [
                          // Time
                          Expanded(
                            child: _buildStatItem(
                              icon: Icons.timer,
                              label: 'Time',
                              value: _formatDuration(widget.ruckBuddy.durationSeconds.round()),
                            ),
                          ),
                          // Elevation
                          Expanded(
                            child: _buildStatItem(
                              icon: Icons.trending_up,
                              label: 'Elevation',
                              value: MeasurementUtils.formatElevation(
                                widget.ruckBuddy.elevationGainM,
                                0,
                                metric: preferMetric,
                              ),
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Second row: Pace and Calories
                      Row(
                        children: [
                          // Pace
                          Expanded(
                            child: _buildStatItem(
                              icon: Icons.speed,
                              label: 'Pace',
                              value: MeasurementUtils.formatPace(
                                (widget.ruckBuddy.durationSeconds / 60) / widget.ruckBuddy.distanceKm,
                                metric: preferMetric,
                              ),
                            ),
                          ),
                          // Calories
                          Expanded(
                            child: _buildStatItem(
                              icon: Icons.local_fire_department,
                              label: 'Calories',
                              value: '${widget.ruckBuddy.caloriesBurned.round()} kcal',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Like and comment counts, and comment input
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Like and comment counts
                      Row(
                        children: [
                          // Like button with same styling as card
                          InkWell(
                            onTap: _handleLikeTap,
                            borderRadius: BorderRadius.circular(20),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                              child: Row(
                                children: [
                                  // Use same image assets with same size as card
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
                          // Comments count with same styling as card
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                            child: Row(
                              children: [
                                Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    // White outline version of chat bubble
                                    Icon(
                                      Icons.chat_bubble_outline,
                                      color: Colors.white,
                                      size: 40, // Exactly 40px as requested
                                    ),
                                    // Slightly smaller solid icon to create a white outline effect
                                    Icon(
                                      Icons.chat_bubble,
                                      color: AppColors.secondary,
                                      size: 36,
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '$_commentCount',
                                  style: TextStyle(
                                    fontFamily: 'Bangers',
                                    fontSize: 24,
                                    color: Colors.grey[800],
                                  ),
                                ),
                              ],
                            ),
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
                              focusNode: _commentFocusNode,
                              decoration: const InputDecoration(
                                hintText: 'Add a comment...',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.all(Radius.circular(20.0)),
                                ),
                                contentPadding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                                isDense: true,
                              ),
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _submitComment(),
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
                      
                      // Comments section
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: CommentsSection(
                          ruckId: widget.ruckBuddy.id, // Now directly using string ID
                          maxDisplayed: 5, // Show 5 most recent comments
                          showViewAllButton: true,
                          hideInput: true, // Prevent CommentsSection from rendering its own input field
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Robustly extract photo URLs from a list of photo objects
  List<String> _extractPhotoUrls(List<dynamic> photos) {
    return photos.map((p) {
      if (p is RuckPhoto) {
        // If it's already a RuckPhoto object
        final url = p.url;
        return url != null && url.isNotEmpty ? url : p.thumbnailUrl ?? '';
      } else if (p is Map<String, dynamic>) {
        // Handle raw map data
        final url = p['url'] ?? p['thumbnail_url'];
        return url is String && url.isNotEmpty ? url : '';
      }
      return '';
    })
    .where((url) => url.isNotEmpty)
    .toList();
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
  final double? ruckWeightKg;

  const _RouteMap({
    required this.locationPoints,
    this.ruckWeightKg,
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
    final String weightText = ruckWeightKg != null ? '${ruckWeightKg!.toStringAsFixed(1)} kg' : '';
    
    // If no route points, show empty state with weight if available
    if (routePoints.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            Container(
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
            // Weight chip overlay
            if (ruckWeightKg != null)
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
    
    // Return map with route and weight overlay
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        children: [
          FlutterMap(
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
          
          // Weight chip overlay
          if (ruckWeightKg != null)
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