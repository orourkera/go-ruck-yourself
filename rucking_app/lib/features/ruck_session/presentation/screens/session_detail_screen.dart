import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) { 
      if (mounted && widget.session.id != null) {
        AppLogger.info('--- SessionDetailScreen initState: Dispatching LoadSessionForViewing for session ${widget.session.id} ---');
        context.read<ActiveSessionBloc>().add(LoadSessionForViewing(
          sessionId: widget.session.id!,
          session: widget.session,
        ));
      }
    }); 
  }

  // Builds the photo section - either showing photos or empty state
  Widget _buildPhotoSection() {
    return BlocBuilder<ActiveSessionBloc, ActiveSessionState>(
      builder: (context, state) {
        if (state is ActiveSessionRunning) {
          // Only show loading indicator during initial photo load if we know photos exist
          if (state.isPhotosLoading) {
            // Check if we have photos in the state that are loading (like during refresh)
            // If we do have existing photos we know about, show the spinner, otherwise don't
            if (state.photos.isNotEmpty) {
              return const Center(child: CircularProgressIndicator());
            } else {
              // No need to show anything if we're loading but don't know of any photos yet
              return const SizedBox.shrink();
            }
          }

          // Only show error if we have a specific error related to photos
          if (state.photosError != null && state.photosError!.isNotEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  state.photosError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          // Debug photo URLs
        AppLogger.info('DEBUG: Photos in state: ${state.photos.length}');
        state.photos.forEach((photo) {
          AppLogger.info('DEBUG: Photo ${photo.id} URL: ${photo.url}');
        });
        
        // Process URLs to ensure proper formatting and accessibility
        final photoUrls = state.photos.map((p) {
          String? url = p.url;
          if (url != null && url.isNotEmpty) {
            // Remove trailing question mark if present
            if (url.endsWith('?')) {
              url = url.substring(0, url.length - 1);
              AppLogger.info('DEBUG: Fixed URL by removing trailing ?: $url');
            }
            
            // Make sure the URL is publicly accessible by ensuring it has the right access flag
            if (!url.contains('public=true') && !url.contains('download=true') && url.contains('supabase')) {
              // Add download=true parameter to force public access
              url = url.contains('?') 
                ? '$url&download=true' 
                : '$url?download=true';
              AppLogger.info('DEBUG: Added download flag to URL: $url');
            }
            
            return url;
          }
          return null;
        }).where((url) => url != null && url.isNotEmpty).cast<String>().toList();
        
        AppLogger.info('DEBUG: Valid photo URLs: ${photoUrls.length}');

          // Only show photo carousel if we actually have photos
          if (photoUrls.isNotEmpty) {
            return PhotoCarousel(
              photoUrls: photoUrls,
              height: 240,
              showDeleteButtons: true, // This might need to be conditional based on ownership in future
              isEditable: true, // This might need to be conditional based on ownership in future
              onPhotoTap: (index) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => PhotoViewer(
                      photoUrls: photoUrls,
                      initialIndex: index,
                    ),
                  ),
                );
              },
              onDeleteRequest: (index) {
                // Get the photo object from the state's photos list
                if (index < state.photos.length) {
                  final photo = state.photos[index];
                  if (photo.id != null) {
                    // Dispatch delete event
                    context.read<ActiveSessionBloc>().add(
                      DeleteSessionPhotoRequested(
                        sessionId: widget.session.id!,
                        photo: photo,
                      ),
                    );
                  }
                }
              },
            );
          } else {
            // No photos, return empty widget instead of a placeholder
            return const SizedBox.shrink();
          }
        }
        
        // Initial state or other states - don't show a placeholder
        return const SizedBox.shrink();
      },
    );
  }

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
              // Header section with date and overview
              Container(
                padding: const EdgeInsets.all(16),
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                child: Column(
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
              ),

              // Map Section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                child: _SessionRouteMap(session: widget.session),
              ),

              // Photo Gallery Section
              Padding(
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
                              'Photos',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ],
                        ),
                        // Add photo button
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
                    const SizedBox(height: 16),
                    // DEMO: Show the photo carousel with sample photos or empty state
                    // This is just for UI development and will be replaced with real data
                    _buildPhotoSection(),
                  ],
                ),
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
                    if (widget.session.rating != null) ...[
                      const SizedBox(height: 24),
                      Text(
                        'Rating',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: List.generate(5, (index) {
                          return Icon(
                            index < (widget.session.rating ?? 0) 
                                ? Icons.star 
                                : Icons.star_border,
                            color: Theme.of(context).primaryColor,
                            size: 28,
                          );
                        }),
                      ),
                    ],
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
    AppLogger.info('=== _showAddPhotoOptions called for session ${widget.session.id} ===');
    // Show a snackbar to confirm the method is being called
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Opening photo options...')),
    );
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Take Photo'),
                onTap: () {
                  Navigator.pop(context);
                  _takePhotoWithCamera(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickPhotoFromGallery(context);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // Take a photo with the camera
  void _takePhotoWithCamera(BuildContext context) {
    if (widget.session.id == null) {
      AppLogger.error('Session ID is null, cannot take photo.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: Session ID is missing.')),
      );
      return;
    }
    
    final currentState = BlocProvider.of<ActiveSessionBloc>(context).state;
    AppLogger.info('--- PHOTO DEBUG: _takePhotoWithCamera called ---');
    AppLogger.info('--- PHOTO DEBUG: Session ID: ${widget.session.id} ---');
    AppLogger.info('--- PHOTO DEBUG: BLoC state type: ${currentState.runtimeType} ---');
    if (currentState is ActiveSessionRunning) {
      AppLogger.info('--- PHOTO DEBUG: State is ActiveSessionRunning, sessionId: ${currentState.sessionId} ---');
    } else {
      AppLogger.info('--- PHOTO DEBUG: State is NOT ActiveSessionRunning ---');
    }
    
    // Show a snackbar to confirm the event is being dispatched
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Opening camera...')),
    );
    
    BlocProvider.of<ActiveSessionBloc>(context).add(TakePhotoRequested(sessionId: widget.session.id!));
  }

  // Pick a photo from the gallery
  void _pickPhotoFromGallery(BuildContext context) {
    if (widget.session.id == null) {
      AppLogger.error('Session ID is null, cannot pick photo.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: Session ID is missing.')),
      );
      return;
    }
    
    final currentState = BlocProvider.of<ActiveSessionBloc>(context).state;
    AppLogger.info('--- PHOTO DEBUG: _pickPhotoFromGallery called ---');
    AppLogger.info('--- PHOTO DEBUG: Session ID: ${widget.session.id} ---');
    AppLogger.info('--- PHOTO DEBUG: BLoC state type: ${currentState.runtimeType} ---');
    if (currentState is ActiveSessionRunning) {
      AppLogger.info('--- PHOTO DEBUG: State is ActiveSessionRunning, sessionId: ${currentState.sessionId} ---');
    } else {
      AppLogger.info('--- PHOTO DEBUG: State is NOT ActiveSessionRunning ---');
    }
    
    // Show a snackbar to confirm the event is being dispatched
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Opening gallery...')),
    );
    
    BlocProvider.of<ActiveSessionBloc>(context).add(PickPhotoRequested(sessionId: widget.session.id!));
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