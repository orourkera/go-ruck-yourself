import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rucking_app/core/utils/measurement_utils.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_session.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/session_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:rucking_app/shared/widgets/styled_snackbar.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/widgets/photo/photo_carousel.dart';
import 'package:rucking_app/shared/widgets/photo/photo_viewer.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_photo.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';
import 'package:rucking_app/features/ruck_session/presentation/widgets/photo_upload_section.dart';

// Social features imports
import 'package:rucking_app/core/services/service_locator.dart';
import 'package:rucking_app/features/social/presentation/bloc/social_bloc.dart';
import 'package:rucking_app/features/social/presentation/bloc/social_event.dart';
import 'package:rucking_app/features/social/presentation/widgets/like_button.dart';
import 'package:rucking_app/features/social/presentation/widgets/comments_section.dart';

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

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.session.id != null) {
      // Load photos
      context.read<ActiveSessionBloc>().add(FetchSessionPhotosRequested(widget.session.id!));
      
      // Load social data (likes and comments)
      final socialBloc = getIt<SocialBloc>();
      socialBloc.add(LoadRuckLikes(int.parse(widget.session.id!)));
      socialBloc.add(LoadRuckComments(int.parse(widget.session.id!)));
    }
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

  @override
  Widget build(BuildContext context) {
    // Get user preferences for metric/imperial
    final authState = context.read<AuthBloc>().state;
    final bool preferMetric = authState is Authenticated ? authState.user.preferMetric : true;
    
    // Format date and time using MeasurementUtils to handle timezone conversion
    final formattedDate = MeasurementUtils.formatDate(widget.session.startTime);
    final formattedStartTime = MeasurementUtils.formatTime(widget.session.startTime);
    final formattedEndTime = MeasurementUtils.formatTime(widget.session.endTime);
    
    // Format distance using MeasurementUtils
    final distanceValue = MeasurementUtils.formatDistance(widget.session.distance, metric: preferMetric);
    
    // Format pace
    final paceValue = MeasurementUtils.formatPace(
      widget.session.averagePace,
      metric: preferMetric,
    );
    
    // Format elevation
    final elevationDisplay = MeasurementUtils.formatElevation(
      widget.session.elevationGain,
      widget.session.elevationLoss.abs(),
      metric: preferMetric,
    );
    
    // Format weight using MeasurementUtils
    final weight = MeasurementUtils.formatWeight(widget.session.ruckWeightKg, metric: preferMetric);
    
    return BlocListener<SessionBloc, SessionState>(
      listener: (context, state) {
        if (state is SessionOperationInProgress) {
          // Show loading indicator with styled snackbar
          StyledSnackBar.show(
            context: context,
            message: 'Deleting session...',
            duration: const Duration(seconds: 1),
          );
        } else if (state is SessionDeleteSuccess) {
          // Show success message and navigate back with refresh result
          StyledSnackBar.showSuccess(
            context: context,
            message: 'The session is gone, rucker. Gone forever.',
            duration: const Duration(seconds: 2),
          );
          // Pop with result to trigger refresh on the home screen
          Navigator.of(context).pop(true); // true indicates refresh needed
        } else if (state is SessionOperationFailure) {
          // Show error message
          StyledSnackBar.showError(
            context: context,
            message: 'Error: ${state.message}',
            duration: const Duration(seconds: 3),
          );
        }
      },
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
                            Text(
                              formattedDate,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "${formattedStartTime} - ${formattedEndTime}",
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
                          distanceValue,
                        ),
                        _buildHeaderStat(
                          context,
                          Icons.speed,
                          'Pace',
                          paceValue,
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
                  if (state is ActiveSessionRunning) {
                    // Only show if there are photos or if they're still loading
                    final photoUrls = state.photos
                        .map((p) => p.url)
                        .where((url) => url != null && url.isNotEmpty)
                        .cast<String>()
                        .toList();
                    
                    // DETAILED PHOTO DEBUG LOGGING
                    print('===== PHOTO DEBUG INFO =====');
                    print('* Photo loading state:');
                    print('  - isPhotosLoading: ${state.isPhotosLoading}');
                    print('  - isUploading: ${state.isUploading}');
                    print('  - photosError: ${state.photosError}');
                    print('  - uploadSuccess: ${state.uploadSuccess}');
                    print('  - Photo count in state: ${state.photos.length}');
                    print('  - PhotoURLs count: ${photoUrls.length}');
                    print('\n* Photo details:');
                    for (var i = 0; i < state.photos.length; i++) {
                      final photo = state.photos[i];
                      print('  [$i] ID: ${photo.id}, URL: ${photo.url}');
                    }
                    print('==========================');
                    
                    final bool shouldShowPhotoSection = photoUrls.isNotEmpty || state.isPhotosLoading || state.isUploading;
                    
                    if (shouldShowPhotoSection) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.photo_library, color: _getLadyModeColor(context)),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Ruck Shots',
                                      style: Theme.of(context).textTheme.titleMedium,
                                    ),
                                  ],
                                ),
                                // Add photo button removed since we're using PhotoUploadSection
                                if (photoUrls.isNotEmpty) TextButton.icon(
                                  onPressed: () {
                                    _showAddPhotoOptions(context);
                                  },
                                  icon: const Icon(Icons.add_photo_alternate),
                                  label: const Text('Add Photos'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: _getLadyModeColor(context),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            // Show loading state during uploads and loading
                            if (state.isPhotosLoading || state.isUploading)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 40),
                                child: Center(child: CircularProgressIndicator()),
                              )
                            // Show photos carousel when available and not in loading/uploading state
                            else if (photoUrls.isNotEmpty)
                              PhotoCarousel(
                                photoUrls: photoUrls,
                                height: 240,
                                showDeleteButtons: true,
                                isEditable: true,
                                onPhotoTap: (index) {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) => PhotoViewer(
                                        photoUrls: photoUrls,
                                        initialIndex: index,
                                        title: 'Your Ruck Shots',
                                      ),
                                    ),
                                  );
                                },
                                onDeleteRequest: (index) {
                                  if (state.photos.length > index) {
                                    // Properly delete the photo using the full photo object
                                    final photoToDelete = state.photos[index];
                                    context.read<ActiveSessionBloc>().add(
                                      DeleteSessionPhotoRequested(
                                        sessionId: widget.session.id!,
                                        photo: photoToDelete,
                                      ),
                                    );
                                  }
                                },
                              )
                            // Show PhotoUploadSection for empty state
                            else
                              PhotoUploadSection(
                                ruckId: widget.session.id!,
                                onPhotosSelected: (photos) {
                                  // Upload photos using the ActiveSessionBloc
                                  context.read<ActiveSessionBloc>().add(
                                    UploadSessionPhotosRequested(
                                      sessionId: widget.session.id!,
                                      photos: photos,
                                    ),
                                  );
                                },
                                isUploading: state.isUploading,
                              ),
                          ],
                        ),
                      );
                    }
                  }
                  
                  // Add a floating action button for adding photos when there are none
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () {
                            _showAddPhotoOptions(context);
                          },
                          icon: const Icon(Icons.add_photo_alternate),
                          label: const Text('Add Photos'),
                          style: TextButton.styleFrom(
                            foregroundColor: _getLadyModeColor(context),
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
                      weight,
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
                          ruckId: int.parse(widget.session.id!),
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
⚖️ ${MeasurementUtils.formatWeight(widget.session.ruckWeightKg, metric: preferMetric)}

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
      builder: (BuildContext dialogContext) {
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
                _deleteSession(context);
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
  void _deleteSession(BuildContext context) {
    // Verify session has an ID
    if (widget.session.id == null) {
      StyledSnackBar.showError(
        context: context,
        message: 'Error: Session ID is missing',
        duration: const Duration(seconds: 3),
      );
      return;
    }

    // Dispatch the delete event to the SessionBloc
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
        
        // Upload the photos
        context.read<ActiveSessionBloc>().add(
          UploadSessionPhotosRequested(
            sessionId: widget.session.id!,
            photos: photos,
          ),
        );
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
        
        // Upload the photo
        context.read<ActiveSessionBloc>().add(
          UploadSessionPhotosRequested(
            sessionId: widget.session.id!,
            photos: [photo],
          ),
        );
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