import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rucking_app/core/utils/measurement_utils.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/error_messages.dart' as error_msgs;
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_session.dart';
import 'package:rucking_app/features/ruck_session/domain/models/heart_rate_sample.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/session_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:rucking_app/shared/widgets/styled_snackbar.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/widgets/photo/photo_carousel.dart';
import 'package:rucking_app/shared/widgets/photo/photo_viewer.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_photo.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';
import 'package:rucking_app/features/social/presentation/bloc/social_bloc.dart';
import 'package:rucking_app/features/social/presentation/bloc/social_event.dart';
import 'package:rucking_app/features/social/presentation/bloc/social_state.dart';
import 'package:rucking_app/features/social/presentation/widgets/like_button.dart';
import 'package:rucking_app/features/social/presentation/widgets/comments_section.dart';
import 'package:rucking_app/shared/widgets/charts/heart_rate_graph.dart';
import 'package:rucking_app/features/ruck_session/presentation/widgets/photo_upload_section.dart';
import 'package:rucking_app/core/services/service_locator.dart'; // For 'getIt' variable
import 'package:get_it/get_it.dart';

/// Screen that displays detailed information about a completed session
class SessionDetailScreen extends StatefulWidget {
  final RuckSession session;
  
  const SessionDetailScreen({
    Key? key,
    required this.session,
  }) : super(key: key);
  
  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  late ScrollController _scrollController;
  bool _isScrolledToTop = true;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _photosLoadAttemptedForThisSession = false; // Flag to prevent multiple fetches
  Timer? _photoRefreshTimer;
  bool _uploadInProgress = false;
  int _refreshAttempts = 0;
  final int _maxRefreshAttempts = 5;

  @override
  void initState() {
    super.initState();
    AppLogger.debug('[CASCADE_TRACE] SessionDetailScreen initState called.');
    
    // Debug log heart rate data in the initial session
    AppLogger.debug('[HEARTRATE DEBUG] Initial session heart rate data:');
    AppLogger.debug('[HEARTRATE DEBUG] Has heartRateSamples: ${widget.session.heartRateSamples != null}');
    if (widget.session.heartRateSamples != null) {
      AppLogger.debug('[HEARTRATE DEBUG] Number of samples: ${widget.session.heartRateSamples!.length}');
    }
    AppLogger.debug('[HEARTRATE DEBUG] avgHeartRate: ${widget.session.avgHeartRate}');
    AppLogger.debug('[HEARTRATE DEBUG] maxHeartRate: ${widget.session.maxHeartRate}');
    AppLogger.debug('[HEARTRATE DEBUG] minHeartRate: ${widget.session.minHeartRate}');

    _tabController = TabController(length: 2, vsync: this);
    _scrollController = ScrollController()
      ..addListener(() {
        setState(() {
          _isScrolledToTop = _scrollController.offset <= 0;
        });
      });
      
    // Load session data and photos
    if (widget.session.id != null) {
      AppLogger.debug('[CASCADE_TRACE] SessionDetailScreen initState: Loading session ${widget.session.id}');
      
      // 1. Load the full session data
      GetIt.instance<ActiveSessionBloc>().add(LoadSessionForViewing(
        sessionId: widget.session.id!, 
        session: widget.session
      ));
      
      // 2. Force a fresh load of photos
      AppLogger.debug('[PHOTO_DEBUG] Force loading photos in initState for session: ${widget.session.id}');
      _forceLoadPhotos();
      
      // 3. Load social data
      _loadSocialData(widget.session.id!);
    } else {
      AppLogger.error('[CASCADE_TRACE] SessionDetailScreen initState: Session ID is null, cannot load session data');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AppLogger.debug('[CASCADE_TRACE] SessionDetailScreen didChangeDependencies called.');
  }

  // Load social data (likes and comments) for the session
  void _loadSocialData(String ruckId) {
    AppLogger.debug('[SOCIAL_DEBUG] Loading social data for session $ruckId');
    try {
      final socialBloc = getIt<SocialBloc>();
      
      // Use batch checking for likes to ensure state is synchronized across screens
      final ruckIdInt = int.tryParse(ruckId);
      if (ruckIdInt != null) {
        // This will update all screens that display this ruck
        socialBloc.add(BatchCheckUserLikeStatus([ruckIdInt]));
      }
      
      // Also load the standard likes and comments
      socialBloc.add(LoadRuckLikes(int.parse(ruckId))); 
      socialBloc.add(LoadRuckComments(ruckId));
    } catch (e) {
      AppLogger.error('[SOCIAL_DEBUG] Error loading social data: $e');
    }
  }

  List<Widget> _buildSessionDetailTabs(RuckSession session) {
    final tabs = <Widget>[
      const Tab(text: 'Overview'),
    ];
    // Only add the 'Live Map' tab if the session status indicates it might have a map.
    // For instance, if it's in progress or completed and had tracking.
    // Based on the RuckStatus enum, we use inProgress for active sessions
    if (session.status == RuckStatus.inProgress) {
      tabs.add(const Tab(text: 'Live Map'));
    }
    return tabs;
  }

  void _forceLoadPhotos() {
    if (widget.session.id != null) {
      AppLogger.info('[PHOTO_DEBUG] 🔄 Force loading photos for session ${widget.session.id}');
      if (!GetIt.I.isRegistered<ActiveSessionBloc>()) {
        AppLogger.error('[PHOTO_DEBUG] ❌ ActiveSessionBloc is not registered in GetIt. Cannot load photos.');
        return;
      }
      final activeSessionBloc = GetIt.instance<ActiveSessionBloc>();
      // Clear the current photos from the BLoC state before fetching new ones
      AppLogger.debug('[CASCADE_TRACE] _forceLoadPhotos: Attempting to add ClearSessionPhotos for session ${widget.session.id}');
      activeSessionBloc.add(ClearSessionPhotos(ruckId: widget.session.id!));
      AppLogger.debug('[CASCADE_TRACE] _forceLoadPhotos: Successfully added ClearSessionPhotos for session ${widget.session.id}');
      // Then fetch new photos
      AppLogger.debug('[CASCADE_TRACE] _forceLoadPhotos: Attempting to add FetchSessionPhotosRequested for session ${widget.session.id}');
      activeSessionBloc.add(FetchSessionPhotosRequested(widget.session.id!));
      AppLogger.debug('[CASCADE_TRACE] _forceLoadPhotos: Successfully added FetchSessionPhotosRequested for session ${widget.session.id}');
    } else {
      AppLogger.error('[PHOTO_DEBUG] ❌ Cannot load photos - session ID is null');
    }
  }
  
  /// Standard photo loading - doesn't clear existing photos first
  void _loadPhotos() {
    if (widget.session.id != null) {
      AppLogger.info('[PHOTO_DEBUG] 📸 Loading photos for session ${widget.session.id}');
      if (!GetIt.I.isRegistered<ActiveSessionBloc>()) {
        AppLogger.error('[PHOTO_DEBUG] ❌ ActiveSessionBloc is not registered in GetIt. Cannot load photos.');
        return;
      }
      final activeSessionBloc = GetIt.instance<ActiveSessionBloc>();
      activeSessionBloc.add(FetchSessionPhotosRequested(widget.session.id!));
    } else {
      AppLogger.error('[PHOTO_DEBUG] ❌ Cannot load photos - session ID is null');
    }
  }
  
  @override
  void dispose() {
    _photoRefreshTimer?.cancel();
    super.dispose();
  }
  
  // Starts polling for photos after upload
  void _startPhotoRefreshPolling() {
    _refreshAttempts = 0;
    _uploadInProgress = true;
    
    AppLogger.info('[SESSION_DETAIL] Starting photo refresh polling');
    
    // Cancel existing timer if running
    _photoRefreshTimer?.cancel();
    
    // Start a new timer to check every 2 seconds
    _photoRefreshTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _refreshAttempts++;
      
      AppLogger.info('[SESSION_DETAIL] Refresh attempt $_refreshAttempts of $_maxRefreshAttempts');
      
      if (_refreshAttempts > _maxRefreshAttempts) {
        AppLogger.info('[SESSION_DETAIL] Max refresh attempts reached, stopping polling');
        timer.cancel();
        _uploadInProgress = false;
        return;
      }
      
      // Request a fresh photo fetch
      if (mounted && widget.session.id != null) {
        // Get direct access to the bloc
        final activeSessionBloc = GetIt.instance<ActiveSessionBloc>();
        activeSessionBloc.add(FetchSessionPhotosRequested(widget.session.id!));
      }
    });
  }

  // Builds the photo section - either showing photos or empty state
  // _buildPhotoSection method removed - functionality moved to photo section in main build method

  // Helper method to get the appropriate color based on user gender
  Color _getLadyModeColor(BuildContext context) {
    try {
      final authState = context.read<AuthBloc>().state;
      if (authState is Authenticated && authState.user.gender == 'female') {
        return AppColors.ladyPrimary;
      }
    } catch (e) {
      // If we can't access the AuthBloc, fall back to default color
    }
    return AppColors.primary;
  }

  // Heart rate calculation helper methods (from feature/heart-rate-viz)
  int _calculateAvgHeartRate(List<HeartRateSample> samples) {
    if (samples.isEmpty) return 0;
    final sum = samples.fold(0, (sum, sample) => sum + sample.bpm);
    return (sum / samples.length).round();
  }

  int _calculateMaxHeartRate(List<HeartRateSample> samples) {
    if (samples.isEmpty) return 0;
    return samples.map((e) => e.bpm).reduce((max, bpm) => bpm > max ? bpm : max);
  }

  // Potentially add _calculateMinHeartRate if needed, or rely on session.minHeartRate
  int? _getMinHeartRate(RuckSession session) {
    if (session.minHeartRate != null && session.minHeartRate! > 0) return session.minHeartRate;
    if (session.heartRateSamples != null && session.heartRateSamples!.isNotEmpty) {
      return session.heartRateSamples!.map((e) => e.bpm).reduce((min, bpm) => bpm < min ? bpm : min);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeSessionBloc = GetIt.instance<ActiveSessionBloc>();
    
    // Get user preferences for metric/imperial
    final authState = context.read<AuthBloc>().state;
    final bool preferMetric = authState is Authenticated ? authState.user.preferMetric : true;

    return MultiBlocListener(
      listeners: [
        BlocListener<ActiveSessionBloc, ActiveSessionState>(
          bloc: activeSessionBloc, // Provide the bloc instance
          listener: (context, state) {
            AppLogger.debug('[CASCADE_TRACE] SessionDetailScreen BlocListener: Received state: $state');
            final currentRuckId = widget.session.id;
            if (currentRuckId == null) return;

            bool sessionReadyForPhotoLoad = false;
            if (state is ActiveSessionRunning && state.sessionId == currentRuckId) {
              AppLogger.debug('[CASCADE_TRACE] SessionDetailScreen BlocListener: State is ActiveSessionRunning for current session.');
              sessionReadyForPhotoLoad = true;
            } else if (state is ActiveSessionInitial && state.viewedSession?.id == currentRuckId) {
              AppLogger.debug('[CASCADE_TRACE] SessionDetailScreen BlocListener: State is ActiveSessionInitial with viewedSession loaded.');
              sessionReadyForPhotoLoad = true;
            }

            if (sessionReadyForPhotoLoad) {
              // Check if photos have already been fetched for this session ID in this screen instance to avoid loops.
              // This simple flag might need to be more robust depending on navigation patterns.
              if (!_photosLoadAttemptedForThisSession) {
                AppLogger.debug('[CASCADE_TRACE] SessionDetailScreen BlocListener: Session is ready, calling _forceLoadPhotos for $currentRuckId.');
                _forceLoadPhotos();
                if (mounted) {
                  setState(() {
                    _photosLoadAttemptedForThisSession = true;
                  });
                }
              }
            }
          },
        ),
        BlocListener<SessionBloc, SessionState>(
          listener: (context, state) {
            AppLogger.debug('[CASCADE_TRACE] SessionDetailScreen SessionBloc listener: $state');
            
            if (state is SessionDeleteSuccess) {
              // Show confirmation message using StyledSnackBar
              StyledSnackBar.showSuccess(
                context: context,
                message: error_msgs.sessionDeleteSuccess,
                animationStyle: SnackBarAnimationStyle.slideUpBounce,
              );
              
              // Navigate back to home screen
              Navigator.of(context).popUntil((route) => route.isFirst);
            } else if (state is SessionOperationFailure) {
              // Show error message using StyledSnackBar
              StyledSnackBar.showError(
                context: context,
                message: state.message,
                animationStyle: SnackBarAnimationStyle.slideFromTop,
              );
            }
          },
        ),
      ],
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Session Details'),
          backgroundColor: _getLadyModeColor(context),
          elevation: 0,
          actions: [
            // Delete session button
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete session',
              onPressed: () => _showDeleteConfirmationDialog(context),
            ),
          ],
        ),
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header section with date and rating stars
              Container(
                padding: const EdgeInsets.all(16),
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  MeasurementUtils.formatDate(widget.session.startTime),
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                // Add the like button here
                                if (widget.session.id != null)
                                  BlocProvider.value(
                                    value: getIt<SocialBloc>(),
                                    child: BlocBuilder<SocialBloc, SocialState>(
                                      buildWhen: (previous, current) {
                                        final ruckId = int.tryParse(widget.session.id!);
                                        if (ruckId == null) return false;
                                        
                                        return (current is LikeActionCompleted && current.ruckId == ruckId) ||
                                            (current is LikeStatusChecked && current.ruckId == ruckId) ||
                                            (current is LikesLoaded && current.ruckId == ruckId) ||
                                            (current is BatchLikeStatusChecked && current.likeStatusMap.containsKey(ruckId));
                                      },
                                      builder: (context, state) {
                                        final ruckId = int.tryParse(widget.session.id!);
                                        if (ruckId == null) return const SizedBox.shrink();
                                        
                                        bool isLiked = false;
                                        int likeCount = 0;
                                        
                                        if (state is LikesLoaded && state.ruckId == ruckId) {
                                          isLiked = state.userHasLiked;
                                          likeCount = state.likes.length;
                                        } else if (state is LikeActionCompleted && state.ruckId == ruckId) {
                                          isLiked = state.isLiked;
                                          likeCount = state.likeCount;
                                        } else if (state is LikeStatusChecked && state.ruckId == ruckId) {
                                          isLiked = state.isLiked;
                                          likeCount = state.likeCount;
                                        } else if (state is BatchLikeStatusChecked) {
                                          isLiked = state.likeStatusMap[ruckId] ?? false;
                                          likeCount = state.likeCountMap[ruckId] ?? 0;
                                        }
                                        
                                        return InkWell(
                                          onTap: () {
                                            // Use haptic feedback for better UX
                                            HapticFeedback.heavyImpact();
                                            
                                            // Important: Use the singleton instance from GetIt
                                            final socialBloc = getIt<SocialBloc>();
                                            socialBloc.add(ToggleRuckLike(ruckId));
                                            
                                            // Log for debugging
                                            AppLogger.debug('[SOCIAL_DEBUG] SessionDetailScreen: Like toggled for ruckId $ruckId');
                                          },
                                          borderRadius: BorderRadius.circular(10),
                                          child: Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Image.asset(
                                                  isLiked
                                                      ? 'assets/images/tactical_ruck_like_icon_active.png'
                                                      : 'assets/images/tactical_ruck_like_icon_transparent.png',
                                                  width: 30,
                                                  height: 30,
                                                ),
                                                const SizedBox(width: 2),
                                                Text(
                                                  '$likeCount',
                                                  style: TextStyle(
                                                    fontFamily: 'Bangers',
                                                    fontSize: 20,
                                                    color: Colors.grey[800],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "${MeasurementUtils.formatTime(widget.session.startTime)} - ${MeasurementUtils.formatTime(widget.session.endTime)}",
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ],
                        ),
                        // Rating stars - show all 5 with empty ones if needed
                        Row(
                          children: List.generate(
                            5, // Always generate 5 stars
                            (index) => Icon(
                              index < (widget.session.rating ?? 0) 
                                  ? Icons.star 
                                  : Icons.star_border,
                              color: Colors.amber,
                              size: 24,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Stats row with Distance, Pace, Duration
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildHeaderStat(
                          context,
                          Icons.straighten,
                          'Distance',
                          MeasurementUtils.formatDistance(widget.session.distance, metric: preferMetric),
                        ),
                        _buildHeaderStat(
                          context,
                          Icons.speed,
                          'Pace',
                          MeasurementUtils.formatPace(
                            widget.session.averagePace,
                            metric: preferMetric,
                          ),
                        ),
                        _buildHeaderStat(
                          context,
                          Icons.timer,
                          'Duration',
                          MeasurementUtils.formatDuration(widget.session.duration),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Map Section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                child: _SessionRouteMap(session: widget.session),
              ),

              // Photo Gallery Section - only shown when there are photos
              BlocBuilder<ActiveSessionBloc, ActiveSessionState>(
                builder: (context, state) {
                  List<String> photoUrls = [];
                  bool isPhotosLoading = false;
                  bool isUploading = false;
                  List<dynamic> photos = [];
                  if (state is ActiveSessionRunning) {
                    photos = state.photos;
                    isPhotosLoading = state.isPhotosLoading;
                    isUploading = state.isUploading;
                  } else if (state is SessionSummaryGenerated) {
                    photos = state.photos;
                    isPhotosLoading = state.isPhotosLoading;
                  }
                  
                  // Improved URL extraction with better handling of potential nulls - works for both state types
                  photoUrls = photos.map((p) {
                    if (p is RuckPhoto) {
                      // If it's already a RuckPhoto object
                      final url = p.url;
                      return url != null && url.isNotEmpty ? url : p.thumbnailUrl;
                    } else if (p is Map<String, dynamic>) {
                      // Handle raw map data
                      final url = p['url'] ?? p['thumbnail_url'];
                      return url is String && url.isNotEmpty ? url : null;
                    }
                    return null;
                  })
                  .where((url) => url != null && url.isNotEmpty)
                  .cast<String>()
                  .toList();
                  
                  // Process the URLs
                  final processedUrls = photoUrls.map((url) {
                    final cacheBuster = DateTime.now().millisecondsSinceEpoch;
                    return url.contains('?') ? '$url&t=$cacheBuster' : '$url?t=$cacheBuster';
                  }).toList();
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.photo_library, color: _getLadyModeColor(context)),
                            const SizedBox(width: 8),
                            Text(
                              'Ruck Shots',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (isPhotosLoading || isUploading)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 40),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (processedUrls.isNotEmpty)
                          PhotoCarousel(
                            photoUrls: processedUrls,
                            height: 240,
                            showDeleteButtons: true,
                            isEditable: true,
                            onPhotoTap: (index) {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => PhotoViewer(
                                    photoUrls: processedUrls,
                                    initialIndex: index,
                                    title: 'Your Ruck Shots',
                                  ),
                                ),
                              );
                            },
                            onDeleteRequest: (index) {
                              if (photos.length > index) {
                                final photoToDelete = photos[index];
                                context.read<ActiveSessionBloc>().add(
                                  DeleteSessionPhotoRequested(
                                    sessionId: widget.session.id!,
                                    photo: photoToDelete,
                                  ),
                                );
                              }
                            },
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: PhotoUploadSection(
                              ruckId: widget.session.id!,
                              onPhotosSelected: (photos) {
                                AppLogger.info('[PHOTO_DEBUG] Session Detail: Preparing to dispatch UploadSessionPhotosRequested event with ${photos.length} photos');
                                AppLogger.info('[PHOTO_DEBUG] Session ID: ${widget.session.id!}');
                                
                                final bloc = context.read<ActiveSessionBloc>();
                                AppLogger.info('[PHOTO_DEBUG] ActiveSessionBloc instance: ${bloc.hashCode}, Current state: ${bloc.state.runtimeType}');
                                
                                bloc.add(
                                  UploadSessionPhotosRequested(
                                    sessionId: widget.session.id!,
                                    photos: photos,
                                  ),
                                );
                                AppLogger.info('[PHOTO_DEBUG] Event dispatched to bloc');
                              },
                              isUploading: isUploading,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),

              // Detail stats
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Stats',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    _buildDetailRow(
                      context,
                      'Calories Burned',
                      '${widget.session.caloriesBurned}',
                      Icons.local_fire_department,
                    ),
                    _buildDetailRow(
                      context,
                      'Ruck Weight',
                      widget.session.ruckWeightKg == 0.0 ? 'Hike' : MeasurementUtils.formatWeight(widget.session.ruckWeightKg, metric: preferMetric),
                      Icons.fitness_center,
                    ),
                    // Elevation Gain/Loss rows
                    if (widget.session.elevationGain > 0)
                      _buildDetailRow(
                        context,
                        'Elevation Gain',
                        MeasurementUtils.formatSingleElevation(widget.session.elevationGain, metric: preferMetric),
                        Icons.trending_up,
                      ),
                    if (widget.session.elevationLoss > 0)
                      _buildDetailRow(
                        context,
                        'Elevation Loss',
                        MeasurementUtils.formatSingleElevation(-widget.session.elevationLoss, metric: preferMetric),
                        Icons.trending_down,
                      ),
                    if (widget.session.elevationGain == 0.0 && widget.session.elevationLoss == 0.0)
                      _buildDetailRow(
                        context,
                        'Elevation',
                        '--',
                        Icons.landscape,
                      ),   
                    // Rating stars moved to the header
                    if (widget.session.notes?.isNotEmpty == true) ...[
                      const SizedBox(height: 24),
                      Text(
                        'Notes',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Text(
                          widget.session.notes!,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                    
                    // Heart Rate Card with diagnostic logging
                    Builder(builder: (context) {
                      // Log all heart rate data for debugging
                      AppLogger.debug('[HEARTRATE DEBUG RENDER] About to render heart rate section with:');
                      AppLogger.debug('[HEARTRATE DEBUG RENDER] avgHeartRate: ${widget.session.avgHeartRate}');
                      AppLogger.debug('[HEARTRATE DEBUG RENDER] maxHeartRate: ${widget.session.maxHeartRate}');
                      AppLogger.debug('[HEARTRATE DEBUG RENDER] minHeartRate: ${widget.session.minHeartRate}');
                      AppLogger.debug('[HEARTRATE DEBUG RENDER] Has samples: ${widget.session.heartRateSamples != null}');
                      if (widget.session.heartRateSamples != null) {
                        AppLogger.debug('[HEARTRATE DEBUG RENDER] Sample count: ${widget.session.heartRateSamples!.length}');
                      }
                      
                      // Always show the heart rate card regardless of data availability
                      return _buildStatCard(
                        context,
                        'Heart Rate',
                        [
                          if (widget.session.avgHeartRate != null && widget.session.avgHeartRate! > 0 || (widget.session.heartRateSamples != null && widget.session.heartRateSamples!.isNotEmpty)) 
                            _buildStatItem(
                              context,
                              'Average HR',
                              '${widget.session.avgHeartRate ?? _calculateAvgHeartRate(widget.session.heartRateSamples ?? [])} bpm',
                              Icons.favorite,
                              iconColor: AppColors.error // Or a more neutral/positive color like Colors.pinkAccent
                            ),
                          if (widget.session.maxHeartRate != null && widget.session.maxHeartRate! > 0 || (widget.session.heartRateSamples != null && widget.session.heartRateSamples!.isNotEmpty))
                            _buildStatItem(
                              context,
                              'Max HR',
                              '${widget.session.maxHeartRate ?? _calculateMaxHeartRate(widget.session.heartRateSamples ?? [])} bpm',
                              Icons.whatshot, // Alternative: Icons.arrow_upward or FontAwesomeIcons.heartPulse
                              iconColor: AppColors.error // Or a specific color for max HR
                            ),
                          if (_getMinHeartRate(widget.session) != null)
                            _buildStatItem(
                              context,
                              'Min HR',
                              '${_getMinHeartRate(widget.session)} bpm',
                              Icons.arrow_downward, // Alternative: FontAwesomeIcons.heartbeat with a different style
                              iconColor: Colors.blueAccent // Or a specific color for min HR
                            ),
                          // Heart rate graph
                          BlocBuilder<ActiveSessionBloc, ActiveSessionState>(
                            buildWhen: (previous, current) {
                              // Only rebuild when the session contains heart rate samples
                              if (current is SessionSummaryGenerated) {
                                return current.session.heartRateSamples != null;
                              }
                              return false;
                            },
                            builder: (context, state) {
                              // Get heart rate samples from the updated state if available
                              List<HeartRateSample>? heartRateSamples = widget.session.heartRateSamples;
                              
                              // Check if we have updated session data in the state
                              if (state is SessionSummaryGenerated && state.session.id == widget.session.id) {
                                if (state.session.heartRateSamples != null && state.session.heartRateSamples!.isNotEmpty) {
                                  heartRateSamples = state.session.heartRateSamples;
                                  AppLogger.debug('[HEARTRATE_DEBUG] Using ${heartRateSamples!.length} heart rate samples from updated state');
                                }
                              }
                              
                              if (heartRateSamples != null && heartRateSamples.isNotEmpty) {
                                return HeartRateGraph(
                                  samples: heartRateSamples,
                                  height: 150,
                                  showLabels: true,
                                  showTooltips: true,
                                );
                              } else {
                                return Container(
                                  height: 150,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(8.0),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.timeline_outlined, size: 36, color: Colors.grey.shade400),
                                      const SizedBox(height: 8),
                                      Text(
                                        'No heart rate data available',
                                        style: TextStyle(color: Colors.grey.shade600),
                                      ),
                                    ],
                                  ),
                                );
                              }
                            },
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              ),
              // Comments Section
              if (widget.session.id != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.comment, color: _getLadyModeColor(context)),
                          const SizedBox(width: 8),
                          Text(
                            'Comments',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      BlocProvider.value(
                        value: getIt<SocialBloc>(),
                        child: CommentsSection(
                          ruckId: widget.session.id!,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildHeaderStat(
    BuildContext context, 
    IconData icon, 
    String label, 
    String value,
  ) {
    return Column(
      children: [
        Icon(
          icon,
          color: _getLadyModeColor(context),
          size: 24,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium!.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }
  
  Widget _buildDetailRow(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(
            icon,
            color: _getLadyModeColor(context),
            size: 24,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium!.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }

  // Build a card containing a title and a list of stat items
  Widget _buildStatCard(
    BuildContext context,
    String title,
    List<Widget> statItems,
  ) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ...statItems,
          ],
        ),
      ),
    );
  }
  
  // Build an individual stat item row inside a stat card
  Widget _buildStatItem(
    BuildContext context,
    String label,
    String value,
    IconData? icon, {
    Color? iconColor
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (icon != null) ...[  
                Icon(icon, size: 16, color: iconColor ?? Colors.grey[600]),
                const SizedBox(width: 8),
              ],
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
              // We no longer have a valueColor parameter, just use the default text color
            ),
          ),
        ],
      ),
    );
  }
  
  void _shareSession(BuildContext context) {
    AppLogger.info('Sharing session ${widget.session.id}');
    
    // Get user preferences for metric/imperial
    final authState = context.read<AuthBloc>().state;
    final bool preferMetric = authState is Authenticated ? authState.user.preferMetric : true;
    
    // Format date using MeasurementUtils for timezone conversion
    final formattedDate = MeasurementUtils.formatDate(widget.session.startTime);
    
    // Create message with emoji for style points
    final shareText = '''🏋️ Go Rucky Yourself - Session Completed!
📅 $formattedDate
🔄 ${widget.session.formattedDuration}
📏 ${MeasurementUtils.formatDistance(widget.session.distance, metric: preferMetric)}
🔥 ${widget.session.caloriesBurned} calories
⚖️ ${widget.session.ruckWeightKg == 0.0 ? 'Hike' : MeasurementUtils.formatWeight(widget.session.ruckWeightKg, metric: preferMetric)}

Download Go Rucky Yourself from the App Store!
''';

    // This would use a share plugin in a real implementation
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sharing not implemented in this version'),
      ),
    );
  }
  
  /// Shows a confirmation dialog before deleting a session
  void _showDeleteConfirmationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Session?'),
          content: const Text(
            'Are you sure you want to delete this session? This action cannot be undone and all session data will be permanently removed.'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(), // Cancel
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                // Close the dialog
                Navigator.of(dialogContext).pop();
                
                // Execute the delete operation
                _deleteSession();
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  /// Handles the actual deletion of the session
  void _deleteSession() {
    // Verify session has an ID
    if (widget.session.id == null) {
      StyledSnackBar.showError(
        context: context,
        message: 'Error: Session ID is missing',
        duration: const Duration(seconds: 3),
      );
      return;
    }

    // Directly dispatch the delete event to the injected SessionBloc
    AppLogger.info('DEBUGGING: Deleting session ${widget.session.id}');
    context.read<SessionBloc>().add(DeleteSessionEvent(sessionId: widget.session.id!));
  }

  void _showAddPhotoOptions(BuildContext context) {
    // Show option to choose camera or gallery
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Photo Gallery'),
                onTap: () async {
                  Navigator.pop(context);
                  await _getImageFromGallery(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Camera'),
                onTap: () async {
                  Navigator.pop(context);
                  await _getImageFromCamera(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }
  
  Future<void> _getImageFromGallery(BuildContext context) async {
    final ImagePicker imagePicker = ImagePicker();
    
    try {
      AppLogger.info('[PHOTO_UPLOAD] Attempting to pick multiple images from gallery');
      
      // Select multiple photos
      final List<XFile> pickedFiles = await imagePicker.pickMultiImage(
        // Don't set imageQuality for PNG files as it's not supported
        // and causes issues on iOS
        imageQuality: 80,
      );
      
      AppLogger.info('[PHOTO_UPLOAD] Picked ${pickedFiles.length} images from gallery');
      
      if (pickedFiles.isNotEmpty && widget.session.id != null) {
        // Convert XFiles to File objects and log their info
        final List<File> photos = [];
        
        for (var xFile in pickedFiles) {
          final file = File(xFile.path);
          photos.add(file);
          
          // Log each photo's details
          AppLogger.info('[PHOTO_UPLOAD] Photo details: path=${xFile.path}, size=${await file.length()} bytes, name=${xFile.name}');
        }
        
        // Check if context is still mounted before showing snackbar
        if (context.mounted) {
          // Show a loading indicator
          StyledSnackBar.show(
            context: context,
            message: 'Uploading ${photos.length} ${photos.length == 1 ? 'photo' : 'photos'}...',
            duration: const Duration(seconds: 2),
          );
        }
        
        AppLogger.info('[PHOTO_UPLOAD] Adding UploadSessionPhotosRequested event for ${photos.length} photos');
        
        // Store these variables for use after async operations
        final String sessionId = widget.session.id!;
        
        // Don't use the context here - get the bloc directly from GetIt
        // This avoids any issues with context being disposed
        try {
          // Get the bloc directly from the service locator
          final activeSessionBloc = GetIt.instance<ActiveSessionBloc>();
          
          // Upload the photos
          activeSessionBloc.add(
            UploadSessionPhotosRequested(
              sessionId: sessionId,
              photos: photos,
            ),
          );
          
          // Start polling for photo updates
          if (mounted) {
            AppLogger.info('[PHOTO_UPLOAD] Starting polling for photo updates');
            _startPhotoRefreshPolling();
          }
          
          AppLogger.info('[PHOTO_UPLOAD] Successfully added upload event to bloc using GetIt');
        } catch (e) {
          AppLogger.error('[PHOTO_UPLOAD] Error uploading photos: $e');
        }
      } else {
        AppLogger.info('[PHOTO_UPLOAD] No photos selected or session ID is null: sessionId=${widget.session.id}');
      }
    } catch (e, stackTrace) {
      AppLogger.error('[PHOTO_UPLOAD] Error selecting images: $e');
      AppLogger.error('[PHOTO_UPLOAD] Stack trace: $stackTrace');
      
      if (!context.mounted) return;
      StyledSnackBar.showError(
        context: context,
        message: 'Error selecting images: $e',
        duration: const Duration(seconds: 3),
      );
    }
  }
  
  Future<void> _getImageFromCamera(BuildContext context) async {
    final ImagePicker imagePicker = ImagePicker();
    
    try {
      AppLogger.info('[PHOTO_UPLOAD] Attempting to take photo from camera');
      
      final XFile? pickedFile = await imagePicker.pickImage(
        source: ImageSource.camera,
        // Don't set imageQuality for PNG files as it's not supported
        // and causes issues on iOS
        imageQuality: 80,
      );
      
      AppLogger.info('[PHOTO_UPLOAD] Photo captured: ${pickedFile != null}');
      
      if (pickedFile != null && widget.session.id != null) {
        // Convert XFile to File
        final File photo = File(pickedFile.path);
        
        // Log photo details
        AppLogger.info('[PHOTO_UPLOAD] Camera photo details: path=${pickedFile.path}, size=${await photo.length()} bytes, name=${pickedFile.name}');
        
        // Check if context is still mounted before showing snackbar
        if (context.mounted) {
          // Show a loading indicator
          StyledSnackBar.show(
            context: context,
            message: 'Uploading photo...',
            duration: const Duration(seconds: 2),
          );
        }
        
        AppLogger.info('[PHOTO_UPLOAD] Adding UploadSessionPhotosRequested event for camera photo');
        
        // Store these variables for use after async operations
        final String sessionId = widget.session.id!;
        final File capturedPhoto = photo;
        
        // Don't use the context here - get the bloc directly from GetIt
        // This avoids any issues with context being disposed
        try {
          // Get the bloc directly from the service locator
          final activeSessionBloc = GetIt.instance<ActiveSessionBloc>();
          
          // Upload the photo
          activeSessionBloc.add(
            UploadSessionPhotosRequested(
              sessionId: sessionId,
              photos: [capturedPhoto],
            ),
          );
          
          // Start polling for photo updates
          if (mounted) {
            AppLogger.info('[PHOTO_UPLOAD] Starting polling for photo updates after camera upload');
            _startPhotoRefreshPolling();
          }
          
          AppLogger.info('[PHOTO_UPLOAD] Successfully added camera photo upload event using GetIt');
        } catch (e) {
          AppLogger.error('[PHOTO_UPLOAD] Error uploading camera photo: $e');
        }
      } else {
        AppLogger.info('[PHOTO_UPLOAD] No photo taken or session ID is null: sessionId=${widget.session.id}');
      }
    } catch (e, stackTrace) {
      AppLogger.error('[PHOTO_UPLOAD] Error taking photo: $e');
      AppLogger.error('[PHOTO_UPLOAD] Stack trace: $stackTrace');
      
      if (!context.mounted) return;
      StyledSnackBar.showError(
        context: context,
        message: 'Error taking photo: $e',
        duration: const Duration(seconds: 3),
      );
    }
  }
}

// Route map preview widget for session details
class _SessionRouteMap extends StatelessWidget {
  final RuckSession session;
  
  const _SessionRouteMap({required this.session});
  
  List<LatLng> _getRoutePoints() {
    final points = <LatLng>[];
    // Try locationPoints (preferred in model)
    if (session.locationPoints != null && session.locationPoints!.isNotEmpty) {
      for (final p in session.locationPoints!) {
        if (p.containsKey('lat') && p.containsKey('lng')) {
          points.add(LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()));
        }
      }
    }
    return points;
  }

  @override
  Widget build(BuildContext context) {
    final points = _getRoutePoints();
    final center = points.isNotEmpty
        ? LatLng(
            points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length,
            points.map((p) => p.longitude).reduce((a, b) => a + b) / points.length,
          )
        : LatLng(40.421, -3.678); // Default center
    final zoom = points.isEmpty
        ? 16.0
        : (points.length == 1
            ? 17.5
            : (() {
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
              })()
          );

    if (points.isEmpty) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text('No route data available', style: Theme.of(context).textTheme.bodyMedium),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 180,
        width: double.infinity,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: center,
            initialZoom: zoom,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
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
                  points: points,
                  color: AppColors.secondary,
                  strokeWidth: 4,
                ),
              ],

            ),
          ],
        ),
      ),
    );
  }
}