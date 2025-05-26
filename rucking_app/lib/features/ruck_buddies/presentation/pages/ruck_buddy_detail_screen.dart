import 'dart:developer';
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
import 'package:rucking_app/features/ruck_buddies/domain/entities/user_info.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_photo.dart';
import 'package:rucking_app/features/ruck_session/data/repositories/session_repository.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_session.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/features/social/presentation/widgets/comments_section.dart';
import 'package:rucking_app/features/social/presentation/bloc/social_bloc.dart';
import 'package:rucking_app/features/social/presentation/bloc/social_event.dart';
import 'package:rucking_app/features/social/presentation/bloc/social_state.dart';
import 'package:rucking_app/features/social/domain/models/ruck_comment.dart';
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
  
  // For storing complete data when loaded from a notification
  RuckBuddy? _completeBuddy;
  
  // Getter to use the complete buddy data if available, otherwise fallback to widget.ruckBuddy
  RuckBuddy get displayBuddy => _completeBuddy ?? widget.ruckBuddy;
  
  // Comment editing state
  bool _isEditingComment = false;
  String? _editingCommentId;
  RuckComment? _commentBeingEdited;

  @override
  void initState() {
    super.initState();
    // Use widget.ruckBuddy directly here since _completeBuddy isn't set yet
    _isLiked = widget.ruckBuddy.isLikedByCurrentUser;
    _likeCount = widget.ruckBuddy.likeCount;
    _commentCount = widget.ruckBuddy.commentCount; // Initialize comment count
    _photos = widget.ruckBuddy.photos ?? [];
    
    // Check if this is a minimal RuckBuddy (e.g., from a notification)
    bool isMinimalRuckBuddy = widget.ruckBuddy.id.isNotEmpty && 
                           widget.ruckBuddy.user.username.isEmpty && 
                           widget.ruckBuddy.distanceKm == 0;
                           
    // If this is a minimal RuckBuddy, we need to fetch the complete session data
    if (isMinimalRuckBuddy) {
      // Defer _loadRuckDetails to after the first frame to avoid context issues
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadRuckDetails();
        }
      });
    }

    // Always fetch photos for ruck buddies, as they're not included in the initial RuckBuddy model
    if (displayBuddy.id.isNotEmpty) {
      // Make sure we get photos on screen initialization with a small delay to ensure the bloc is ready
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && GetIt.I.isRegistered<ActiveSessionBloc>()) {
          final activeSessionBloc = GetIt.instance<ActiveSessionBloc>();
          print('[PHOTO_DEBUG] RuckBuddyDetailScreen: Fetching photos for ${displayBuddy.id} from ActiveSessionBloc.');
          // Request photos from the bloc
          try {
            final ruckId = displayBuddy.id;
            print('[PHOTO_DEBUG] RuckBuddyDetailScreen: Dispatching FetchSessionPhotosRequested event with ruckId: $ruckId');
            // Force the bloc to fetch fresh photos
            activeSessionBloc.add(FetchSessionPhotosRequested(ruckId));
          } catch (e) {
            print('[PHOTO_DEBUG] RuckBuddyDetailScreen: Error requesting photos for ID ${displayBuddy.id}: $e');
          }
        } else {
          print('[PHOTO_DEBUG] RuckBuddyDetailScreen: ActiveSessionBloc not registered or widget not mounted');
        }
      });
    } else {
      print('[PHOTO_DEBUG] RuckBuddyDetailScreen: Empty ruckBuddy.id, can\'t fetch photos');
    }
    
    // Load social data immediately without waiting for post-frame callback
    final ruckId = int.tryParse(displayBuddy.id);
    if (ruckId != null && GetIt.I.isRegistered<SocialBloc>()) {
      // Use the singleton instance of SocialBloc from GetIt
      final socialBloc = GetIt.instance<SocialBloc>();
      
      // Load both like status and comments with high priority
      socialBloc.add(CheckRuckLikeStatus(ruckId));
      socialBloc.add(LoadRuckComments(ruckId.toString()));
      
      // Debug log
      print('[SOCIAL_DEBUG] RuckBuddyDetailScreen: Immediately dispatched social data loading for ruckId: $ruckId');
    }
    
    // If focusComment is true, request focus on the comment field after build
    if (widget.focusComment) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _commentFocusNode.requestFocus();
      });
    }
  }

  @override
  /// Load complete ruck details when opening from notification
  Future<void> _loadRuckDetails() async {
    final ruckId = widget.ruckBuddy.id;
    if (ruckId.isEmpty) return;

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false, // User cannot dismiss by tapping outside
      builder: (context) => const Dialog(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading details...'),
            ],
          ),
        ),
      ),
    );

    try {
      print('====== LOADING RUCK DETAILS FOR ID: $ruckId ======');

      // Get API client for direct API access
      final apiClient = GetIt.I<ApiClient>();

      // Fetch session data directly - this gives us all raw fields
      final data = await apiClient.get('/rucks/$ruckId');

      print('RuckBuddyDetailScreen _loadRuckDetails: Raw API data = $data'); // Log raw data

      // If the widget was disposed while waiting for data,
      // attempt to pop the dialog if it's still active and then return.
      if (!mounted) {
        try {
          // Check if dialog is part of the current route stack before popping
          if (Navigator.of(context, rootNavigator: true).canPop()) {
            Navigator.of(context, rootNavigator: true).pop();
          }
        } catch (_) {
          // Ignore errors if context is invalid for popping (e.g., already disposed)
        }
        return;
      }

      // Close loading dialog (widget is mounted here)
      Navigator.of(context, rootNavigator: true).pop();

      if (data != null) {
        // Extract user information
        final userId = data['user_id']?.toString() ?? '';
        final username = data['user_name']?.toString() ?? data['username']?.toString() ?? 'Unknown User';
        final userGender = data['user_gender']?.toString() ?? 'male';
        print('RuckBuddyDetailScreen _loadRuckDetails: Parsed User: id=$userId, name=$username, gender=$userGender');

        // Extract metrics
        final distanceKm = _parseDouble(data['distance_km']) ?? 0.0;
        final durationSeconds = _parseInt(data['duration_seconds']) ?? 0;
        final caloriesBurned = _parseInt(data['calories_burned']) ?? 0;
        final ruckWeightKg = _parseDouble(data['ruck_weight_kg']) ?? 0.0;
        final elevationGainM = _parseDouble(data['elevation_gain_meters']) ?? 0.0;
        final elevationLossM = _parseDouble(data['elevation_loss_meters']) ?? 0.0;
        print('RuckBuddyDetailScreen _loadRuckDetails: Parsed Metrics: dist=$distanceKm, dur=$durationSeconds, cal=$caloriesBurned, weight=$ruckWeightKg, elevGain=$elevationGainM, elevLoss=$elevationLossM');

        // Process location points
        List<Map<String, dynamic>> locationPoints = [];
        if (data['route'] != null && data['route'] is List) {
          try {
            for (final point in data['route']) {
              if (point is Map) {
                final lat = _parseDouble(point['lat'] ?? point['latitude']);
                final lng = _parseDouble(point['lng'] ?? point['longitude'] ?? point['lon']);

                if (lat != null && lng != null) {
                  locationPoints.add({'lat': lat, 'lng': lng});
                }
              }
            }
          } catch (e) {
            print('Error parsing route points: $e');
          }
        }

        // Process photos
        List<RuckPhoto> photos = [];
        if (data['photos'] != null && data['photos'] is List) {
          print('RuckBuddyDetailScreen _loadRuckDetails: Processing photos data: ${data['photos']}');
          try {
            for (final photoData in data['photos']) {
              if (photoData is Map<String, dynamic>) {
                try {
                  photos.add(RuckPhoto.fromJson(photoData));
                } catch (e) {
                  // Fallback for partial photo data
                  photos.add(RuckPhoto(
                    id: photoData['id']?.toString() ?? 'photo-${DateTime.now().millisecondsSinceEpoch}',
                    ruckId: ruckId,
                    userId: userId,
                    filename: photoData['filename']?.toString() ?? 'photo.jpg',
                    createdAt: DateTime.now(),
                    url: photoData['url']?.toString() ?? '',
                  ));
                }
              } else if (photoData is String) {
                // Simple URL as photo
                photos.add(RuckPhoto(
                  id: 'photo-${DateTime.now().millisecondsSinceEpoch}',
                  ruckId: ruckId,
                  userId: userId,
                  filename: 'photo.jpg',
                  createdAt: DateTime.now(),
                  url: photoData,
                ));
              }
            }
          } catch (e) {
            print('Error processing photos: $e');
          }
        }

        // Parse timestamps
        DateTime createdAt;
        try {
          final timestamp = data['start_time'] ?? data['started_at'] ?? data['created_at'];
          createdAt = timestamp != null ? DateTime.parse(timestamp.toString()) : DateTime.now();
        } catch (e) {
          createdAt = DateTime.now();
          print('Error parsing timestamp: $e');
        }
        print('RuckBuddyDetailScreen _loadRuckDetails: Parsed createdAt: $createdAt');
        final completedAtTimestamp = data['end_time'];
        DateTime? completedAt;
        if (completedAtTimestamp != null) {
          try {
            completedAt = DateTime.parse(completedAtTimestamp.toString());
          } catch (e) {
            print('Error parsing completedAt timestamp: $e');
          }
        }
        print('RuckBuddyDetailScreen _loadRuckDetails: Parsed completedAt: $completedAt');

        // Create the complete buddy object
        final completeBuddy = RuckBuddy(
          id: ruckId,
          userId: userId,
          ruckWeightKg: ruckWeightKg,
          durationSeconds: durationSeconds,
          distanceKm: distanceKm,
          caloriesBurned: caloriesBurned,
          elevationGainM: elevationGainM,
          elevationLossM: elevationLossM,
          createdAt: createdAt,
          completedAt: completedAt,
          user: UserInfo(
            id: userId,
            username: username,
            gender: userGender,
          ),
          locationPoints: locationPoints,
          photos: photos,
          likeCount: _parseInt(data['like_count']) ?? 0,
          isLikedByCurrentUser: data['is_liked_by_current_user'] == true,
          commentCount: _parseInt(data['comment_count']) ?? 0,
        );
        print('RuckBuddyDetailScreen _loadRuckDetails: Created completeBuddy object: $completeBuddy');

        log('RuckBuddyDetailScreen _loadRuckDetails: Parsed completeBuddy | distanceKm: ${completeBuddy.distanceKm}, duration: ${completeBuddy.durationSeconds}, calories: ${completeBuddy.caloriesBurned}, username: ${completeBuddy.user.username}, locationPoints: ${completeBuddy.locationPoints?.length}');

        if (mounted) {
          setState(() {
            print('RuckBuddyDetailScreen _loadRuckDetails: Calling setState with _completeBuddy');
            _completeBuddy = completeBuddy;
            _isLiked = completeBuddy.isLikedByCurrentUser;
            _likeCount = completeBuddy.likeCount;
            _commentCount = completeBuddy.commentCount;
            _photos = completeBuddy.photos ?? [];
            log('RuckBuddyDetailScreen _loadRuckDetails: setState | _completeBuddy.distanceKm: ${_completeBuddy?.distanceKm}, _completeBuddy.duration: ${_completeBuddy?.durationSeconds}, _completeBuddy.calories: ${_completeBuddy?.caloriesBurned}, _completeBuddy.username: ${_completeBuddy?.user.username}, _completeBuddy.locationPoints: ${_completeBuddy?.locationPoints?.length}');
          });
        }
      } else {
        // Handle case where data is null (e.g., API returned 200 but no body)
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to retrieve ruck details. No data received.')),
          );
        }
      }
    } catch (e) {
      print('Error in _loadRuckDetails: $e');
      if (mounted) {
        // Attempt to pop the dialog if it's still open due to an error
        try {
          if (Navigator.of(context, rootNavigator: true).canPop()) {
            Navigator.of(context, rootNavigator: true).pop();
          }
        } catch (popError) {
          print('Error popping dialog in catch block: $popError');
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading details: ${e.toString()}')),
        );
      }
    }
  }

  // Helper methods for safer parsing
  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString());
  }
  
  int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value.toString());
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocusNode.dispose();
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
    final ruckId = int.tryParse(displayBuddy.id);
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
        ruckId: displayBuddy.id,
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

    // Debug print to check displayBuddy's state at build time
    print('[BUILD_DEBUG] displayBuddy.user.username: ${displayBuddy.user.username}');
    print('[BUILD_DEBUG] displayBuddy.ruckWeightKg: ${displayBuddy.ruckWeightKg}');
    print('[BUILD_DEBUG] displayBuddy.distanceKm: ${displayBuddy.distanceKm}');

    return BlocListener<ActiveSessionBloc, ActiveSessionState>(
      bloc: GetIt.instance<ActiveSessionBloc>(),
      listenWhen: (previous, current) {
        print('[PHOTO_DEBUG] RuckBuddyDetailScreen listenWhen: previous=${previous.runtimeType}, current=${current.runtimeType}');
        
        // Helper function to get photos from any state type that might contain them
        List<dynamic> getPhotosFromState(ActiveSessionState state) {
          if (state is SessionSummaryGenerated) return state.photos;
          if (state is ActiveSessionRunning) return state.photos;
          if (state is ActiveSessionInitial) return state.photos;
          if (state is SessionPhotosLoadedForId && state.sessionId.toString() == displayBuddy.id.toString()) return state.photos;
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
        } else if (state is SessionPhotosLoadedForId && state.sessionId.toString() == displayBuddy.id.toString()) {
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
          final ruckId = int.tryParse(displayBuddy.id);
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
          } else if (state is CommentActionCompleted) {
            // Refresh comments when a comment is added, updated, or deleted
            print('[SOCIAL_DEBUG] RuckBuddyDetailScreen: CommentActionCompleted with actionType: ${state.actionType}');
            context.read<SocialBloc>().add(LoadRuckComments(ruckId.toString()));
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
          backgroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.black : AppColors.backgroundLight,
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
                          child: displayBuddy.user?.photoUrl != null && displayBuddy.user!.photoUrl!.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: displayBuddy.user!.photoUrl!,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
                                errorWidget: (context, url, error) => Image.asset(
                                  displayBuddy.user?.gender?.toLowerCase() == 'female' 
                                    ? 'assets/images/lady rucker profile.png'
                                    : 'assets/images/profile.png',
                                  fit: BoxFit.contain,
                                ),
                              )
                            : Image.asset(
                                displayBuddy.user?.gender?.toLowerCase() == 'female' 
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
                              displayBuddy.user.username,
                              style: AppTextStyles.titleMedium,
                            ),
                            Text(
                              _formatCompletedDate(displayBuddy.completedAt),
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
                          displayBuddy.distanceKm,
                          metric: context.read<AuthBloc>().state is Authenticated
                            ? (context.read<AuthBloc>().state as Authenticated).user.preferMetric
                            : true,
                        ),
                        style: TextStyle(
                          fontFamily: 'Bangers',
                          fontSize: 28,
                          color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
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
                    locationPoints: displayBuddy.locationPoints,
                    ruckWeightKg: displayBuddy.ruckWeightKg,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                  child: FutureBuilder<String>(
                    future: LocationUtils.getLocationName(displayBuddy.locationPoints),
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
                      // Ensure carousel is flush with left edge
                      Container(
                        margin: EdgeInsets.zero,
                        padding: EdgeInsets.zero,
                        width: MediaQuery.of(context).size.width,
                        alignment: Alignment.centerLeft,
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
                                  title: '${displayBuddy.user.username}\'s Ruck',
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
                              value: _formatDuration(displayBuddy.durationSeconds.round()),
                            ),
                          ),
                          // Elevation
                          Expanded(
                            child: _buildStatItem(
                              icon: Icons.trending_up,
                              label: 'Elevation',
                              value: MeasurementUtils.formatElevation(
                                displayBuddy.elevationGainM,
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
                                displayBuddy.distanceKm > 0 
                                  ? (displayBuddy.durationSeconds / 60) / displayBuddy.distanceKm 
                                  : 0,
                                metric: preferMetric,
                              ),
                            ),
                          ),
                          // Calories
                          Expanded(
                            child: _buildStatItem(
                              icon: Icons.local_fire_department,
                              label: 'Calories',
                              value: '${displayBuddy.caloriesBurned.round()} kcal',
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
                                    // Using the same comment icon as the card page
                                    Icon(
                                      Icons.comment,
                                      color: AppColors.secondary,
                                      size: 40, // Exactly 40px as requested
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
                      
                      // Comment input - only show when not in edit mode
                      if (!_isEditingComment)
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
                      Column(
                        children: [
                          // Comments section
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: CommentsSection(
                              ruckId: displayBuddy.id, // Now directly using string ID
                              maxDisplayed: 5, // Show 5 most recent comments
                              showViewAllButton: true,
                              hideInput: true, // Prevent CommentsSection from rendering its own input field
                              onEditCommentRequest: (comment) {
                                // Handle edit request from CommentsSection
                                setState(() {
                                  _isEditingComment = true;
                                  _editingCommentId = comment.id;
                                  _commentBeingEdited = comment;
                                  _commentController.text = comment.content;
                                });
                                _commentFocusNode.requestFocus();
                              },
                            ),
                          ),
                          
                          // Custom comment edit input when in edit mode
                          if (_isEditingComment)
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Edit mode indicator
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8.0),
                                    child: Text(
                                      'Editing comment',
                                      style: TextStyle(
                                        fontStyle: FontStyle.italic,
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ),
                                  // Input field and action buttons
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      // Text field
                                      Expanded(
                                        child: TextField(
                                          controller: _commentController,
                                          focusNode: _commentFocusNode,
                                          maxLines: null,
                                          decoration: const InputDecoration(
                                            hintText: 'Edit your comment...',
                                            border: OutlineInputBorder(),
                                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          ),
                                        ),
                                      ),
                                      // Save button
                                      IconButton(
                                        icon: const Icon(Icons.check, color: Colors.green),
                                        onPressed: () {
                                          // Submit the edited comment
                                          if (_editingCommentId != null && _commentController.text.trim().isNotEmpty) {
                                            context.read<SocialBloc>().add(
                                              UpdateRuckComment(
                                                commentId: _editingCommentId!,
                                                content: _commentController.text.trim(),
                                              ),
                                            );
                                            
                                            // Reset state
                                            setState(() {
                                              _isEditingComment = false;
                                              _editingCommentId = null;
                                              _commentBeingEdited = null;
                                              _commentController.clear();
                                            });
                                          }
                                        },
                                      ),
                                      // Cancel button
                                      IconButton(
                                        icon: const Icon(Icons.close, color: Colors.red),
                                        onPressed: () {
                                          // Cancel editing
                                          setState(() {
                                            _isEditingComment = false;
                                            _editingCommentId = null;
                                            _commentBeingEdited = null;
                                            _commentController.clear();
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                        ],
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
    if (lp == null || lp.isEmpty) {
      // Return default location if no points available
      return [const LatLng(37.7749, -122.4194)]; // San Francisco as default
    }
    
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

      // Only add point if coordinates are valid (not null, finite, and within range)
      if (lat != null && lng != null && 
          lat.isFinite && lng.isFinite && 
          lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180) {
        pts.add(LatLng(lat, lng));
      }
    }
    
    // If we couldn't extract any valid points, return a default
    return pts.isEmpty
        ? [const LatLng(37.7749, -122.4194)] // San Francisco as default
        : pts;
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
            key: ObjectKey(routePoints), // Added key here
            options: MapOptions(
              initialCenter: _getRouteCenter(routePoints),
              initialZoom: _getFitZoom(routePoints),
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all, // Enable all map interactions including pinch-zoom, pan, etc.
              ),
              // Set min/max zoom constraints for better user experience
              minZoom: 3,
              maxZoom: 18,
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