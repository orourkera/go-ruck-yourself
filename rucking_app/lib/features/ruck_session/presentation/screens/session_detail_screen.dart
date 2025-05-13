import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:rucking_app/core/utils/measurement_utils.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_session.dart';
import 'package:rucking_app/features/ruck_session/domain/models/heart_rate_sample.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/session_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:rucking_app/shared/widgets/styled_snackbar.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/widgets/charts/heart_rate_graph.dart';
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

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  // Get direct references to required services and blocs
  late final AuthBloc _authBloc;
  late final SessionBloc _sessionBloc;
  late final bool _preferMetric;
  
  @override
  void initState() {
    super.initState();
    // Direct dependency injection
    _authBloc = GetIt.I<AuthBloc>();
    _sessionBloc = GetIt.I<SessionBloc>();
    
    // Get user preferences from auth state
    final authState = _authBloc.state;
    _preferMetric = authState is Authenticated ? authState.user.preferMetric : true;
    
    AppLogger.info('DEBUGGING: SessionDetailScreen initialized with session ${widget.session.id}');
    AppLogger.info('DEBUGGING: Heart rate samples count: ${widget.session.heartRateSamples?.length ?? 0}');
  }
  
  // Heart rate calculation helper methods
  int _calculateAvgHeartRate(List<HeartRateSample> samples) {
    if (samples.isEmpty) return 0;
    final sum = samples.fold(0, (sum, sample) => sum + sample.bpm);
    return (sum / samples.length).round();
  }

  int _calculateMaxHeartRate(List<HeartRateSample> samples) {
    if (samples.isEmpty) return 0;
    return samples.map((e) => e.bpm).reduce((max, bpm) => bpm > max ? bpm : max);
  }
  
  @override
  Widget build(BuildContext context) {
    // Format date
    final dateFormat = DateFormat('MMMM d, yyyy');
    final timeFormat = DateFormat('h:mm a');
    final formattedDate = dateFormat.format(widget.session.startTime);
    final formattedStartTime = timeFormat.format(widget.session.startTime);
    final formattedEndTime = timeFormat.format(widget.session.endTime);
    
    // Format distance
    final distanceValue = _preferMetric 
        ? '${widget.session.distance.toStringAsFixed(2)} km'
        : '${(widget.session.distance * 0.621371).toStringAsFixed(2)} mi';
    
    // Format pace
    final paceValue = MeasurementUtils.formatPace(
      widget.session.averagePace,
      metric: _preferMetric,
    );
    
    // Format elevation
    final elevationDisplay = MeasurementUtils.formatElevation(
      widget.session.elevationGain,
      widget.session.elevationLoss,
      metric: _preferMetric,
    );
    
    // Format weight
    final weight = _preferMetric
        ? '${widget.session.ruckWeightKg.toStringAsFixed(1)} kg'
        : '${(widget.session.ruckWeightKg * 2.20462).toStringAsFixed(1)} lb';
    
    // Set up a stream listener for session bloc states
    return StreamBuilder<SessionState>(
      stream: _sessionBloc.stream,
      initialData: _sessionBloc.state,
      builder: (context, snapshot) {
        // Handle session bloc state changes
        final state = snapshot.data;
        
        // Handle snackbar display for delete operations
        if (state is SessionOperationInProgress) {
          // Show loading indicator with styled snackbar
          WidgetsBinding.instance.addPostFrameCallback((_) {
            StyledSnackBar.show(
              context: context,
              message: 'Deleting session...',
              duration: const Duration(seconds: 1),
            );
          });
        } else if (state is SessionDeleteSuccess) {
          // Show success message and navigate back with refresh result
          WidgetsBinding.instance.addPostFrameCallback((_) {
            StyledSnackBar.showSuccess(
              context: context,
              message: 'The session is gone, rucker. Gone forever.',
              duration: const Duration(seconds: 2),
            );
            // Pop with result to trigger refresh on the home screen
            Navigator.of(context).pop(true); // true indicates refresh needed
          });
        } else if (state is SessionOperationFailure) {
          // Show error message
          WidgetsBinding.instance.addPostFrameCallback((_) {
            StyledSnackBar.showError(
              context: context,
              message: 'Error: ${state.message}',
              duration: const Duration(seconds: 3),
            );
          });
        }
        
        // Build the UI
        return Scaffold(
          appBar: AppBar(
            title: const Text('Session Details'),
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
                      // Date, time and rating on same row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Date and time column
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                formattedDate,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '$formattedStartTime - $formattedEndTime',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                          // Rating display (moved from below)
                          if (widget.session.rating != null)
                            Row(
                              children: List.generate(5, (index) {
                                return Icon(
                                  index < (widget.session.rating ?? 0) 
                                      ? Icons.star 
                                      : Icons.star_border,
                                  color: Theme.of(context).primaryColor,
                                  size: 20,
                                );
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildHeaderStat(
                            context, 
                            Icons.straighten, 
                            'Distance', 
                            distanceValue,
                          ),
                          _buildHeaderStat(
                            context, 
                            Icons.timer, 
                            'Duration', 
                            widget.session.formattedDuration,
                          ),
                          _buildHeaderStat(
                            context, 
                            Icons.speed, 
                            'Pace', 
                            paceValue,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Route map preview
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  child: _SessionRouteMap(session: widget.session),
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
                          MeasurementUtils.formatSingleElevation(widget.session.elevationGain, metric: _preferMetric),
                          Icons.trending_up,
                        ),
                      if (widget.session.elevationLoss > 0)
                        _buildDetailRow(
                          context,
                          'Elevation Loss',
                          MeasurementUtils.formatSingleElevation(-widget.session.elevationLoss, metric: _preferMetric),
                          Icons.trending_down,
                        ),
                      if (widget.session.elevationGain == 0.0 && widget.session.elevationLoss == 0.0)
                        _buildDetailRow(
                          context,
                          'Elevation',
                          '--',
                          Icons.landscape,
                        ),   
                      // Heart Rate Section (added after stats)
                      if (widget.session.heartRateSamples != null && widget.session.heartRateSamples!.isNotEmpty ||
                          widget.session.avgHeartRate != null ||
                          widget.session.maxHeartRate != null ||
                          widget.session.minHeartRate != null) ...[
                        const SizedBox(height: 24),
                        Text(
                          'Heart Rate',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        AppLogger.info('DEBUG: Rendering Heart Rate section. Samples: ${widget.session.heartRateSamples?.length ?? 0}'),
                        const SizedBox(height: 16),
                        // Average Heart Rate
                        _buildDetailRow(
                          context,
                          'Average Heart Rate',
                          '${widget.session.avgHeartRate ?? 
                             (widget.session.heartRateSamples != null && widget.session.heartRateSamples!.isNotEmpty 
                              ? _calculateAvgHeartRate(widget.session.heartRateSamples!) 
                              : 0)} bpm',
                          Icons.favorite,
                        ),
                        // Maximum Heart Rate
                        _buildDetailRow(
                          context,
                          'Maximum Heart Rate',
                          '${widget.session.maxHeartRate ?? 
                             (widget.session.heartRateSamples != null && widget.session.heartRateSamples!.isNotEmpty 
                              ? _calculateMaxHeartRate(widget.session.heartRateSamples!) 
                              : 0)} bpm',
                          Icons.favorite_border,
                        ),
                        // Minimum Heart Rate (if available)
                        if (widget.session.minHeartRate != null)
                          _buildDetailRow(
                            context,
                            'Minimum Heart Rate',
                            '${widget.session.minHeartRate} bpm',
                            Icons.trending_down,
                          ),
                        const SizedBox(height: 16),
                        // Heart Rate Graph - only show if we have samples
                        if (widget.session.heartRateSamples != null && widget.session.heartRateSamples!.isNotEmpty)
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                Text('Debug: HR samples count: ${widget.session.heartRateSamples!.length}'),
                                HeartRateGraph(
                                  samples: widget.session.heartRateSamples!,
                                  height: 160,
                                  showLabels: true,
                                  showTooltips: true,
                                ),
                              ],
                            ),
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
              ],
            ),
          ),
        );
      },
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
          color: Theme.of(context).primaryColor,
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
            color: Theme.of(context).primaryColor,
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
    // Log session sharing
    AppLogger.info('Sharing session ${widget.session.id}');
    
    // Create shareable text
    final dateFormat = DateFormat('MMMM d, yyyy');
    final formattedDate = dateFormat.format(widget.session.startTime);
    
    // Create message with emoji for style points
    final shareText = '''🏋️ Go Rucky Yourself - Session Completed!
📅 $formattedDate
🔄 ${widget.session.formattedDuration}
📏 ${widget.session.distance.toStringAsFixed(2)} km
🔥 ${widget.session.caloriesBurned} calories
⚖️ ${widget.session.ruckWeightKg.toStringAsFixed(1)} kg weight

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
    _sessionBloc.add(DeleteSessionEvent(sessionId: widget.session.id!));
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
            if (points.isNotEmpty)
              MarkerLayer(
                markers: [
                  // Start marker
                  Marker(
                    point: points.first,
                    width: 32,
                    height: 32,
                    child: Image.asset('assets/images/map marker.png'),
                  ),
                  // End marker
                  Marker(
                    point: points.last,
                    width: 32,
                    height: 32,
                    child: Image.asset('assets/images/home pin.png'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}