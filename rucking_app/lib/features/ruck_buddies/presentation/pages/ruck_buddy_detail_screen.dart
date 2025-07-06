import 'dart:developer';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Import for HapticFeedback
import 'package:cached_network_image/cached_network_image.dart';
import 'package:rucking_app/core/services/image_cache_manager.dart';
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
  
  // API client for user profile fetching
  final ApiClient _apiClient = GetIt.I<ApiClient>();
  
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
          final ruckId = displayBuddy.id;
          activeSessionBloc.add(FetchSessionPhotosRequested(ruckId));
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
      log('RuckBuddyDetailScreen _loadRuckDetails: API response data for ruckId $ruckId: $data');

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
        // Log initial user-related data from getRuckDetails response
        final initialApiUserId = data['user_id']?.toString();
        final initialApiUserName = data['user_name']?.toString(); // often from a direct field
        final initialApiNestedUsername = data['user']?['username']?.toString() ?? data['users']?['username']?.toString(); // from a nested user object
        log('RuckBuddyDetailScreen _loadRuckDetails: From getRuckDetails - user_id: $initialApiUserId, user_name: $initialApiUserName, nested username: $initialApiNestedUsername');

        // Extract user information
        final userId = data['user_id']?.toString() ?? '';
        final username = data['user']?['username']?.toString() ?? ''; // Use documented API structure
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
        print('RuckBuddyDetailScreen _loadRuckDetails: Raw route data: ${data['route']}');
        print('RuckBuddyDetailScreen _loadRuckDetails: Route data type: ${data['route'].runtimeType}');
        
        if (data['route'] != null && data['route'] is List) {
          print('RuckBuddyDetailScreen _loadRuckDetails: Route is a list with ${data['route'].length} items');
          try {
            for (int i = 0; i < data['route'].length; i++) {
              final point = data['route'][i];
              print('RuckBuddyDetailScreen _loadRuckDetails: Processing route point $i: $point (type: ${point.runtimeType})');
              
              if (point is Map) {
                final lat = _parseDouble(point['lat'] ?? point['latitude']);
                final lng = _parseDouble(point['lng'] ?? point['longitude'] ?? point['lon']);
                print('RuckBuddyDetailScreen _loadRuckDetails: Parsed coordinates - lat: $lat, lng: $lng');

                if (lat != null && lng != null) {
                  locationPoints.add({'lat': lat, 'lng': lng});
                  print('RuckBuddyDetailScreen _loadRuckDetails: Added valid point: {lat: $lat, lng: $lng}');
                } else {
                  print('RuckBuddyDetailScreen _loadRuckDetails: Skipped invalid point - lat: $lat, lng: $lng');
                }
              } else {
                print('RuckBuddyDetailScreen _loadRuckDetails: Point is not a Map: $point');
              }
            }
          } catch (e) {
            print('Error parsing route points: $e');
          }
        } else {
          print('RuckBuddyDetailScreen _loadRuckDetails: No route data available or route is not a List');
        }
        
        print('RuckBuddyDetailScreen _loadRuckDetails: Final locationPoints count: ${locationPoints.length}');
        if (locationPoints.isNotEmpty) {
          print('RuckBuddyDetailScreen _loadRuckDetails: First location point: ${locationPoints.first}');
          print('RuckBuddyDetailScreen _loadRuckDetails: Last location point: ${locationPoints.last}');
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
                  createdAt: DateTime.now(), // Use current time as fallback
                  url: photoData,
                ));
              }
            }
          } catch (e) {
            print('Error processing photos: $e');
          }
        }

        // Parse timestamps - use the exact field names from the database schema
        DateTime createdAt;
        try {
          final timestamp = data['created_at'];
          createdAt = timestamp != null ? DateTime.parse(timestamp.toString()) : DateTime.now();
        } catch (e) {
          createdAt = DateTime.now();
          print('Error parsing timestamp: $e');
        }
        print('RuckBuddyDetailScreen _loadRuckDetails: Parsed createdAt: $createdAt');
        
        // Handle completed timestamp - only use the specific field name from the schema
        final completedAtTimestamp = data['completed_at'];
        DateTime? completedAt;
        if (completedAtTimestamp != null) {
          try {
            completedAt = DateTime.parse(completedAtTimestamp.toString());
            print('RuckBuddyDetailScreen _loadRuckDetails: Successfully parsed completedAt: $completedAt');
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
            username: username, // Uses the initially parsed username (now defaults to '')
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

        // Get the user data from the API response - this is reliable in all navigation flows
        final dataUserId = data['user_id']?.toString();
        
        // Create user info directly matching the approach used in RuckBuddyModel.fromJson
        Map<String, dynamic> userData = {};
        if (data.containsKey('users')) {
          userData = data['users'] ?? {};
        } else if (data.containsKey('user')) {
          userData = data['user'] ?? {};
        }
        
        log('RuckBuddyDetailScreen _loadRuckDetails: Data API user_id = $dataUserId, completeBuddy.userId = ${completeBuddy.userId}');

        // Always fetch the user profile directly
        RuckBuddy finalBuddy = completeBuddy;
        if (finalBuddy.userId.isNotEmpty) {
          log('RuckBuddyDetailScreen _loadRuckDetails: Fetching user profile for userId = ${finalBuddy.userId}');
          try {
            final fetchedUserProfile = await _apiClient.getUserProfile(finalBuddy.userId);
            log('RuckBuddyDetailScreen _loadRuckDetails: Fetched UserProfile object: id=${fetchedUserProfile.id}, username="${fetchedUserProfile.username}", gender=${fetchedUserProfile.gender}'); // DETAILED LOG OF FETCHED PROFILE

            // Check fetched profile: if its username is empty or "Unknown User", use "Rucker"
            if (fetchedUserProfile.username.isEmpty || fetchedUserProfile.username == 'Unknown User') {
              log('RuckBuddyDetailScreen _loadRuckDetails: Fetched profile has empty or "Unknown User" username. Using "Rucker". Profile username was: "${fetchedUserProfile.username}"');
              finalBuddy = finalBuddy.copyWith(user: fetchedUserProfile.copyWith(username: 'Rucker'));
            } else {
              finalBuddy = finalBuddy.copyWith(user: fetchedUserProfile);
              log('RuckBuddyDetailScreen _loadRuckDetails: Successfully fetched user profile: ${fetchedUserProfile.username}');
            }
          } catch (e) { // Profile fetch failed
            log('RuckBuddyDetailScreen _loadRuckDetails: Failed to fetch user profile: $e');
            // Fallback: Use username from ruck details (data['users']['username']) if available,
            // otherwise "Rucker". If ruck details username is "Unknown User" or empty, also use "Rucker".
            Map<String, dynamic> userDataFromRuckDetails = data['users'] ?? data['user'] ?? {};
            String fallbackUsername = userDataFromRuckDetails['username']?.toString() ?? ''; // Get it, or empty string
            
            if (fallbackUsername.isEmpty || fallbackUsername == 'Unknown User') {
              log('RuckBuddyDetailScreen _loadRuckDetails: Fallback username from ruck details is empty or "Unknown User". Setting to "Rucker". Was: $fallbackUsername');
              fallbackUsername = 'Rucker';
            }

            try {
              final updatedUserInfo = UserInfo.fromJson({
                'id': userDataFromRuckDetails['id']?.toString() ?? finalBuddy.userId,
                'username': fallbackUsername, // Use the refined fallbackUsername
                'avatar_url': userDataFromRuckDetails['avatar_url']?.toString(),
                'gender': userDataFromRuckDetails['gender']?.toString() ?? 'male',
              });
              finalBuddy = finalBuddy.copyWith(user: updatedUserInfo);
              log('RuckBuddyDetailScreen _loadRuckDetails: Created fallback UserInfo with username = ${updatedUserInfo.username}');
            } catch (userInfoErr) {
              log('RuckBuddyDetailScreen _loadRuckDetails: Error creating fallback user info: $userInfoErr. Setting username to Rucker.');
              // Ensure a sane default even if UserInfo.fromJson fails with the refined fallback
              finalBuddy = finalBuddy.copyWith(user: finalBuddy.user.copyWith(username: 'Rucker'));
            }
          }
        } else { // userId was empty from getRuckDetails response (or initial widget.ruckBuddy if getRuckDetails failed early)
          log('RuckBuddyDetailScreen _loadRuckDetails: UserID is empty. Setting username to Rucker. Original username in finalBuddy: ${finalBuddy.user.username}');
          // finalBuddy.user.username at this point could be '', or 'Unknown User' if data['user_name'] was that and data['user_id'] was null.
          finalBuddy = finalBuddy.copyWith(user: finalBuddy.user.copyWith(username: 'Rucker'));
        }

        if (mounted) {
          setState(() {
            _completeBuddy = finalBuddy; 
            // Update other local state variables based on the new _completeBuddy
            _isLiked = _completeBuddy!.isLikedByCurrentUser;
            _likeCount = _completeBuddy!.likeCount;
            _commentCount = _completeBuddy!.commentCount;
            _photos = _completeBuddy!.photos ?? [];
            
            // Enhanced debugging for location points
            final locationPointsCount = _completeBuddy?.locationPoints?.length ?? 0;
            log('RuckBuddyDetailScreen _loadRuckDetails: _completeBuddy state updated. Username: ${_completeBuddy?.user.username}, Distance: ${_completeBuddy?.distanceKm}, LocationPoints: $locationPointsCount');
            print('RuckBuddyDetailScreen _loadRuckDetails: Updated state with ${locationPointsCount} location points');
            if (locationPointsCount > 0) {
              print('RuckBuddyDetailScreen _loadRuckDetails: First route point in _completeBuddy: ${_completeBuddy?.locationPoints?.first}');
            } else {
              print('RuckBuddyDetailScreen _loadRuckDetails: WARNING: No location points in _completeBuddy!');
            }
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

    return BlocListener<ActiveSessionBloc, ActiveSessionState>(
      bloc: GetIt.instance<ActiveSessionBloc>(),
      listenWhen: (previous, current) {
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
        
        // Only trigger listener when photos change
        final bool photosChanged = prevPhotos != currPhotos;
        
        return photosChanged;
      },
      listener: (context, state) {
        List<dynamic> statePhotos = [];
        if (state is SessionSummaryGenerated) {
          statePhotos = state.photos;
        } else if (state is ActiveSessionInitial) {
          statePhotos = state.photos;
        } else if (state is ActiveSessionRunning) {
          statePhotos = state.photos;
        } else if (state is SessionPhotosLoadedForId && state.sessionId.toString() == displayBuddy.id.toString()) {
          // Handle the SessionPhotosLoadedForId state which is emitted by our updated ActiveSessionBloc
          statePhotos = state.photos;
        }
        
        // Extract photo URLs and log them for debugging
        final photoUrls = _extractPhotoUrls(statePhotos);
        
        // Check if new photos are available and update
        if (statePhotos.isNotEmpty && mounted) {
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
            }
          } else if (state is LikeActionCompleted) {
            if (state.ruckId == ruckId) {
              setState(() {
                _isLiked = state.isLiked;
                _likeCount = state.likeCount;
                _isProcessingLike = false;
              });
            }
          } else if (state is CommentActionCompleted) {
            // Refresh comments when a comment is added, updated, or deleted
            context.read<SocialBloc>().add(LoadRuckComments(ruckId.toString()));
          } else if (state is CommentCountUpdated) {
            if (state.ruckId == ruckId) {
              setState(() {
                _commentCount = state.count;
              });
            }
          }
        },  
        child: Scaffold(
          backgroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.black : AppColors.backgroundLight,
          appBar: AppBar(
            iconTheme: const IconThemeData(color: Colors.white),
            foregroundColor: Colors.white,
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
                                cacheManager: ImageCacheManager.instance,
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
                            : false,
                        ),
                        style: AppTextStyles.displayMedium.copyWith(
                          color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),

                // Route Map with ruck weight
                SizedBox(
                  height: 250,
                  width: double.infinity,
                  child: () {
                    final locationPoints = displayBuddy.locationPoints;
                    final hasLocationPoints = locationPoints != null && locationPoints.isNotEmpty;
                    
                    if (hasLocationPoints) {
                      return _RouteMap(
                        locationPoints: locationPoints,
                        ruckWeightKg: displayBuddy.ruckWeightKg,
                      );
                    } else {
                      return const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 8),
                            Text('Loading route...'),
                          ],
                        ),
                      );
                    }
                  }(),
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
                        return const SizedBox.shrink();
                      }
                      if (snapshot.hasData && snapshot.data != null && snapshot.data!.isNotEmpty && snapshot.data!.toLowerCase() != 'unknown location') {
                        return FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            snapshot.data!,
                            style: AppTextStyles.displayMedium.copyWith(
                              color: Theme.of(context).primaryColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      } else {
                        return const SizedBox.shrink();
                      }
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
                          style: AppTextStyles.displayMedium.copyWith(
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
                ] else ...[
                  const SizedBox.shrink(),
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
                              icon: Icons.terrain,
                              label: 'Elevation',
                              value: MeasurementUtils.formatElevation(
                                displayBuddy.elevationGainM,
                                displayBuddy.elevationLossM,
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
                                  ? displayBuddy.durationSeconds / displayBuddy.distanceKm 
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
                                    style: AppTextStyles.statValue.copyWith(
                                      color: Theme.of(context).brightness == Brightness.dark 
                                          ? Colors.white 
                                          : Colors.grey[800],
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
                                  style: AppTextStyles.statValue.copyWith(
                                    color: Theme.of(context).brightness == Brightness.dark 
                                        ? Colors.white 
                                        : Colors.grey[800],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Comments section
                      Column(
                        children: [
                          // Comments title with icon
                          Row(
                            children: [
                              Icon(
                                Icons.comment,
                                color: AppColors.secondary,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Comments',
                                style: TextStyle(
                                  fontFamily: 'Bangers',
                                  fontSize: 18,
                                  color: AppColors.secondary,
                                ),
                              ),
                            ],
                          ),
                          
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
                          
                          // Comment input - only show when not in edit mode
                          if (!_isEditingComment)
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
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
                                  ElevatedButton(
                                    onPressed: _submitComment,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      shape: const CircleBorder(),
                                    ),
                                    child: Icon(
                                      Icons.arrow_right_alt,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
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
                                      style: AppTextStyles.bodySmall.copyWith(
                                        fontStyle: FontStyle.italic,
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
              color: Theme.of(context).primaryColor,
              size: 20,
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

class _RouteMap extends StatefulWidget {
  final List<dynamic>? locationPoints;
  final double? ruckWeightKg;

  const _RouteMap({
    required this.locationPoints,
    this.ruckWeightKg,
  });
  
  @override
  State<_RouteMap> createState() => _RouteMapState();
}

class _RouteMapState extends State<_RouteMap> {
  // Cache the map widget to prevent rebuilding during scrolling
  FlutterMap? _cachedMapWidget;
  List<LatLng>? _cachedRoutePoints;
  final GlobalKey _mapKey = GlobalKey();

  // Compare route points for equality to determine if we need to rebuild
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

  // Convert dynamic numeric or string to double, return null if not parseable
  double? _parseCoord(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  List<LatLng> _getRoutePoints() {
    final pts = <LatLng>[];
    final lp = widget.locationPoints;
    
    // Enhanced debugging for route points conversion
    print('RouteMap _getRoutePoints: Input locationPoints: $lp');
    print('RouteMap _getRoutePoints: locationPoints count: ${lp?.length ?? 0}');
    
    if (lp == null || lp.isEmpty) {
      print('RouteMap _getRoutePoints: No location points available, returning default San Francisco location');
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

        if (lat != null && lng != null) {
          pts.add(LatLng(lat, lng));
        }
      } else if (p is List && p.length >= 2) {
        lat = _parseCoord(p[0]);
        lng = _parseCoord(p[1]);

        if (lat != null && lng != null) {
          pts.add(LatLng(lat, lng));
        }
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

    // Add 20% padding around bounds
    const paddingFactor = 1.20;
    double latDiff = (maxLat - minLat) * paddingFactor;
    double lngDiff = (maxLng - minLng) * paddingFactor;

    // Protect against zero diff
    if (latDiff == 0) latDiff = 0.00001;
    if (lngDiff == 0) lngDiff = 0.00001;

    // Use widget dimensions for calculation (approximate full-width map)
    const double mapWidth = 375.0;  // Typical mobile width
    const double mapHeight = 175.0; // Height from widget
    const tileSize = 256.0;
    const ln2 = 0.6931471805599453;

    // Calculate zoom to fit bounds
    double latZoom = (math.log(mapHeight * 360 / (latDiff * tileSize)) / ln2);
    double lngZoom = (math.log(mapWidth * 360 / (lngDiff * tileSize)) / ln2);

    double zoom = latZoom < lngZoom ? latZoom : lngZoom;
    return zoom.clamp(4.0, 18.0);
  }

  @override
  Widget build(BuildContext context) {
    final routePoints = _getRoutePoints();
    final String weightText = widget.ruckWeightKg != null ? '${widget.ruckWeightKg!.toStringAsFixed(1)} kg' : '';
    
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
            // Add tile caching for performance
            tileProvider: NetworkTileProvider(),
            errorTileCallback: (tile, error, stackTrace) {
              print('Ruck buddy detail map tile error: $error');
              // Just log the error - can't return a widget from this callback
            },
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
      );
    }

    // Return map with route and weight overlay
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        children: [
          _cachedMapWidget!,
          
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