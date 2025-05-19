import 'dart:math' as math;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/ruck_session/data/repositories/session_repository.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/home_screen.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/custom_button.dart';
import 'package:rucking_app/shared/widgets/custom_text_field.dart';
import 'package:rucking_app/shared/widgets/stat_card.dart';
import 'package:rucking_app/shared/widgets/styled_snackbar.dart';
import 'package:get_it/get_it.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/core/utils/measurement_utils.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:rucking_app/features/ruck_session/domain/models/heart_rate_sample.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_photo.dart'; 
import 'package:rucking_app/features/ruck_session/domain/services/session_validation_service.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/session_bloc.dart';
import 'package:rucking_app/features/health_integration/bloc/health_bloc.dart';
import 'package:rucking_app/features/ruck_session/presentation/widgets/photo_upload_section.dart';
import 'package:rucking_app/features/ruck_session/presentation/widgets/photo_carousel.dart';

/// Screen displayed after a ruck session is completed, showing summary statistics
/// and allowing the user to rate and add notes about the session
class SessionCompleteScreen extends StatefulWidget {
  /// Timestamp when the user ended the session
  final DateTime completedAt;
  final String ruckId;
  final Duration duration;
  final double distance;
  final int caloriesBurned;
  final double elevationGain;
  final double elevationLoss;
  final double ruckWeight;
  final String? initialNotes;
  final List<HeartRateSample>? heartRateSamples;

  const SessionCompleteScreen({
    required this.completedAt,
    Key? key,
    required this.ruckId,
    required this.duration,
    required this.distance,
    required this.caloriesBurned,
    required this.elevationGain,
    required this.elevationLoss,
    required this.ruckWeight,
    this.initialNotes,
    this.heartRateSamples,
  }) : super(key: key);

  @override
  State<SessionCompleteScreen> createState() => _SessionCompleteScreenState();
}

class _SessionCompleteScreenState extends State<SessionCompleteScreen> {
  late final ApiClient _apiClient;
  
  int _rating = 3;
  int _perceivedExertion = 5;
  String _notes = '';
  List<String> _selectedTags = [];
  
  final List<String> _availableTags = [
    'morning', 'afternoon', 'evening',
    'urban', 'trail', 'hills', 'flat',
    'easy', 'moderate', 'hard',
    'recovery', 'training'
  ];
  
  bool _isSaving = false;
  
  // Form controllers and state
  final TextEditingController _notesController = TextEditingController();
  
  // Photo upload state
  final List<File> _selectedPhotos = [];
  bool _isUploadingPhotos = false;
  
  List<HeartRateSample>? _heartRateSamples;
  int? _avgHeartRate;
  int? _maxHeartRate;
  int? _minHeartRate;

  void setHeartRateSamples(List<HeartRateSample> samples) {
    if (!mounted) return;
    setState(() {
      _heartRateSamples = samples;
      if (samples.isNotEmpty) {
        _avgHeartRate = (samples.map((e) => e.bpm).reduce((a, b) => a + b) / samples.length).round();
        _maxHeartRate = samples.map((e) => e.bpm).reduce((a, b) => a > b ? a : b);
        _minHeartRate = samples.map((e) => e.bpm).reduce((a, b) => a < b ? a : b);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    
    // Initialize API client
    _apiClient = GetIt.instance<ApiClient>();
    
    // Initialize notes controller with initial notes if provided
    _notesController.text = widget.initialNotes ?? '';
    
    // Debug heart rate data
    debugPrint('[SESSION-COMPLETE] Heart rate samples from widget: ${widget.heartRateSamples?.length ?? 0}');
    if (widget.heartRateSamples == null) {
      debugPrint('[SESSION-COMPLETE] No heart rate samples passed to session complete screen');
    } else if (widget.heartRateSamples!.isEmpty) {
      debugPrint('[SESSION-COMPLETE] Empty heart rate samples list passed to session complete screen');
    } else {
      debugPrint('[SESSION-COMPLETE] First heart rate sample: ${widget.heartRateSamples![0].bpm} BPM at ${widget.heartRateSamples![0].timestamp}');
    }
    
    // --- Heart Rate: get samples from arguments if present
    if (widget.heartRateSamples != null) {
      setHeartRateSamples(widget.heartRateSamples!);
      debugPrint('[SESSION-COMPLETE] Heart rate samples set with ${widget.heartRateSamples!.length} samples');
    }
  }
  
  /// Format duration as HH:MM:SS
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$hours:$minutes:$seconds";
  }
  
  /// Format pace based on user preference (metric/imperial)
  String _formatPace(bool preferMetric) {
    // Ensure distance is positive to avoid division by zero or negative pace
    if (widget.distance <= 0 || widget.duration.inSeconds <= 0) return '--:--';
    
    // Calculate pace in seconds per kilometer (assuming widget.distance is in km)
    final paceSecondsPerKm = widget.duration.inSeconds / widget.distance;
    
    // Use formatPaceSeconds which correctly handles metric/imperial conversion
    return MeasurementUtils.formatPaceSeconds(paceSecondsPerKm, metric: preferMetric);
  }
  
  /// Toggle a tag's selection status
  void _toggleTag(String tag) {
    setState(() {
      if (_selectedTags.contains(tag)) {
        _selectedTags.remove(tag);
      } else {
        _selectedTags.add(tag);
      }
    });
  }
  
  /// Saves the session review/notes and navigates home
  Future<void> _saveAndContinue() async {
    if (_isSaving) return; // Prevent multiple submissions
  
    setState(() {
      _isSaving = true;
    });
    
    // Send heart rate samples to backend if available
    if (_heartRateSamples != null && _heartRateSamples!.isNotEmpty) {
      try {
        await _apiClient.post(
          '/rucks/${widget.ruckId}/heart_rate',
          _heartRateSamples!.map((e) => e.toJson()).toList(),
        );
      } catch (e) {
        // Ignore errors, do not block session completion
      }
    }
    
    // No session validation - allow saving all sessions regardless of distance
    
    // Prepare data for the completion
    final Map<String, dynamic> updateData = {
      'completed_at': widget.completedAt.toIso8601String(),
      'notes': _notesController.text.trim(),
      // Backend expects these exact keys:
      'distance_km': widget.distance, // always send for compatibility
      'final_distance_km': widget.distance, // for final summary
      'distance_meters': (widget.distance * 1000).round(),
      'calories_burned': widget.caloriesBurned,
      'final_calories_burned': widget.caloriesBurned,
      'elevation_gain_m': widget.elevationGain,
      'elevation_loss_m': widget.elevationLoss,
      'final_elevation_gain': widget.elevationGain,
      'final_elevation_loss': widget.elevationLoss,
      'final_average_pace': (widget.distance > 0) ? (widget.duration.inSeconds / widget.distance) : null, // seconds per km
      'rating': _rating,
      'perceived_exertion': _perceivedExertion,
      'tags': _selectedTags.isNotEmpty ? _selectedTags : null,
    };

    // Log the values being sent
    print('[SESSION_UPDATE] Sending values:');
    print('[SESSION_UPDATE]   notes: ${updateData['notes']}');
    print('[SESSION_UPDATE]   rating: ${updateData['rating']}');
    print('[SESSION_UPDATE]   perceived_exertion: ${updateData['perceived_exertion']}');
    print('[SESSION_UPDATE]   tags: ${updateData['tags']}');

    // Make a PATCH request to update notes, rating, perceived exertion, and tags after completion
    try {
      await _apiClient.patch('/rucks/${widget.ruckId}', updateData);
      
      // Handle photo uploads if any are selected
      if (_selectedPhotos.isNotEmpty) {
        setState(() {
          _isUploadingPhotos = true;
        });
        
        try {
          AppLogger.info('Uploading ${_selectedPhotos.length} photos for session ${widget.ruckId}');
          
          // Create session repository for photo uploads
          final sessionRepo = SessionRepository(apiClient: _apiClient);
          
          // Upload photos
          final uploadedPhotos = await sessionRepo.uploadSessionPhotos(
            widget.ruckId, 
            _selectedPhotos,
          );
          
          AppLogger.info('Uploaded ${uploadedPhotos.length} photos successfully');
          
          // Update session to indicate it has photos
          if (uploadedPhotos.isNotEmpty) {
            await _apiClient.patch(
              '/rucks/${widget.ruckId}',
              {'has_photos': true},
            );
          }
        } catch (e) {
          AppLogger.error('Error uploading photos: $e');
          // Show message but don't block navigation - user can try again later
          StyledSnackBar.show(
            context: context,
            message: 'Session saved, but there was an issue uploading photos. You can try again from the session details screen.',
            duration: const Duration(seconds: 3),
          );
        } finally {
          setState(() {
            _isUploadingPhotos = false;
          });
        }
      }
      
      // Navigate home on success
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
        (route) => false,
      );
    } catch (error) {
      AppLogger.error('[SESSION_UPDATE] Error: $error');
      // Show error and reset saving state
      StyledSnackBar.showError(
        context: context,
        message: 'Error saving session details: ${error.toString()}',
        duration: const Duration(seconds: 3),
      );
      setState(() {
        _isSaving = false;
      });
    }
  }

  /// Populate stats from widget parameters
  void _populateStats() {
    // Stats are already provided as parameters to the widget
    // No need to fetch from API in this case
  }

  // Helper method to get heart rate widgets as a list for spreading into the column
  List<Widget> _getHeartRateWidgets() {
    debugPrint('[SESSION-COMPLETE] _getHeartRateWidgets called, samples: ${_heartRateSamples?.length ?? 0}');
    if (_heartRateSamples == null || _heartRateSamples!.isEmpty) {
      debugPrint('[SESSION-COMPLETE] No heart rate samples to show');
      return [];
    }
    
    return [
      const SizedBox(height: 16),
      Text('Heart Rate', style: AppTextStyles.titleMedium),
      const SizedBox(height: 16),
      // Enhanced heart rate chart with larger height and padding
      Container(
        height: 240, // 20% larger than standard 200
        child: ClipRect(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: _AnimatedHeartRateChart(
              heartRateSamples: _heartRateSamples!,
              avgHeartRate: _avgHeartRate,
              maxHeartRate: _maxHeartRate,
              minHeartRate: _minHeartRate,
              getLadyModeColor: _getLadyModeColor,
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
      // Heart rate stats below chart
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildHeartRateStat('Average', _avgHeartRate),
          _buildHeartRateStat('Maximum', _maxHeartRate),
          _buildHeartRateStat('Minimum', _minHeartRate),
        ],
      ),
      const SizedBox(height: 8),
    ];
  }
  
  // Keep this for backward compatibility
  Widget _buildHeartRateSection() {
    debugPrint('[SESSION-COMPLETE] _buildHeartRateSection called, samples: ${_heartRateSamples?.length ?? 0}');
    if (_heartRateSamples == null || _heartRateSamples!.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _getHeartRateWidgets(),
    );
  }

  Widget _buildStatCard(String label, String value, String unit) {
    return Card(
      color: _getLadyModeColor(context).withOpacity(0.08),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            Text(label, style: AppTextStyles.bodySmall),
            Text(value, style: AppTextStyles.headlineMedium),
            Text(unit, style: AppTextStyles.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _buildHeartRateStat(String label, int? value) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 14, color: Colors.black54),
        ),
        Text(
          value != null ? '$value bpm' : '--',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  LineChartData _buildHeartRateChart() {
    debugPrint('[SESSION-COMPLETE] Building heart rate chart with ${_heartRateSamples?.length ?? 0} samples');
    
    if (_heartRateSamples == null || _heartRateSamples!.isEmpty) {
      debugPrint('[SESSION-COMPLETE] No heart rate samples, returning empty chart');
      return LineChartData();
    }
    
    final firstTimestamp = _heartRateSamples!.first.timestamp.millisecondsSinceEpoch.toDouble();
    
    // Find the sample with maximum heart rate for visual emphasis
    HeartRateSample maxSample = _heartRateSamples!.reduce((a, b) => a.bpm > b.bpm ? a : b);
    final maxTimeOffset = (maxSample.timestamp.millisecondsSinceEpoch - firstTimestamp) / (1000 * 60);
    
    final spots = _heartRateSamples!.map((sample) {
      // Convert timestamp to minutes from session start for x-axis
      final timeOffset = (sample.timestamp.millisecondsSinceEpoch - firstTimestamp) / (1000 * 60);
      return FlSpot(timeOffset, sample.bpm.toDouble());
    }).toList();
    
    debugPrint('[SESSION-COMPLETE] Created ${spots.length} chart spots');
    
    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        horizontalInterval: 30,
        verticalInterval: 5,
        getDrawingHorizontalLine: (value) {
          return FlLine(
            color: Colors.grey[300],
            strokeWidth: 1,
          );
        },
        getDrawingVerticalLine: (value) {
          return FlLine(
            color: Colors.grey[300],
            strokeWidth: 1,
          );
        },
      ),
      titlesData: FlTitlesData(
        show: true,
        // Remove top titles
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        // Remove right titles
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            getTitlesWidget: (value, meta) {
              // Round to nearest integer
              return SideTitleWidget(
                axisSide: meta.axisSide,
                child: Text(
                  '${value.round()}m',
                  style: TextStyle(fontSize: 10),
                ),
              );
            },
            interval: 5,
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (value, meta) {
              return SideTitleWidget(
                axisSide: meta.axisSide,
                child: Text(
                  '${value.toInt()}',
                  style: TextStyle(fontSize: 10),
                ),
              );
            },
            reservedSize: 30,
          ),
        ),
      ),
      borderData: FlBorderData(show: true),
      minX: 0,
      maxX: spots.isEmpty ? 10 : spots.last.x,
      minY: (_minHeartRate?.toDouble() ?? 60.0) - 10.0,
      maxY: (_maxHeartRate?.toDouble() ?? 180.0) + 10.0,
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: _getLadyModeColor(context),
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: FlDotData(show: false),
          belowBarData: BarAreaData(show: true, color: _getLadyModeColor(context).withOpacity(0.2)),
        ),
      ],
      // Add a marker for the maximum heart rate
      extraLinesData: ExtraLinesData(
        horizontalLines: [
          HorizontalLine(
            y: _maxHeartRate?.toDouble() ?? 0.0,
            color: Colors.red.withOpacity(0.8),
            strokeWidth: 1,
            dashArray: [5, 5],
            label: HorizontalLineLabel(
              show: true,
              alignment: Alignment.topRight,
              padding: const EdgeInsets.only(right: 5, bottom: 5),
              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 10),
              labelResolver: (line) => 'Max: ${_maxHeartRate ?? 0} bpm',
            ),
          ),
        ],
      ),
    );
  }

  // Show delete confirmation dialog
  void _showDeleteConfirmationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard Ruck?'),
        content: const Text(
          'This will delete this ruck session and all associated data including heart rate and location points. This action cannot be undone, rucker.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(true);
              _discardSession(context);
            },
            child: Text(
              'Discard',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  // Handle session discard/deletion
  void _discardSession(BuildContext context) {
    // Verify session has an ID
    if (widget.ruckId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error: Session ID is missing'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Dispatch delete event to SessionBloc
    context.read<SessionBloc>().add(DeleteSessionEvent(sessionId: widget.ruckId));
  }

  @override
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

  Widget build(BuildContext context) {
    // Get user measurement preference
    bool preferMetric = true;
    String? userGender;
    final authState = context.read<AuthBloc>().state;
    if (authState is Authenticated) {
      preferMetric = authState.user.preferMetric;
      userGender = authState.user.gender;
    }

    return MultiBlocListener(
      listeners: [
        BlocListener<SessionBloc, SessionState>(
          listener: (context, state) {
            if (state is SessionOperationInProgress) {
              // Show loading indicator
              StyledSnackBar.show(
                context: context,
                message: 'Discarding session...',
                duration: const Duration(seconds: 1),
              );
            } else if (state is SessionDeleteSuccess) {
              // Show success message and navigate back to home
              StyledSnackBar.showSuccess(
                context: context,
                message: 'The session is gone, rucker. Gone forever.',
                duration: const Duration(seconds: 2),
              );
              Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
            } else if (state is SessionOperationFailure) {
              // Show error message
              StyledSnackBar.showError(
                context: context,
                message: 'Error: ${state.message}',
                duration: const Duration(seconds: 3),
              );
            }
          },
        ),
        BlocListener<HealthBloc, HealthState>(
          listener: (context, state) {
            if (state is HealthDataWriteStatus) {
              if (state.success) {
                StyledSnackBar.showSuccess(
                  context: context,
                  message: 'Session data successfully saved to Apple Health',
                  duration: const Duration(seconds: 2),
                );
              } else {
                StyledSnackBar.showError(
                  context: context,
                  message: 'Failed to save session data to Apple Health',
                  duration: const Duration(seconds: 3),
                );
              }
            }
          },
        ),
      ],
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Session Complete'),
          centerTitle: true,
          backgroundColor: _getLadyModeColor(context),
          foregroundColor: Colors.white,
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Congratulations header
                  Center(
                    child: Column(
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                          size: 72,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Great job rucker!',
                        style: AppTextStyles.headlineLarge.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'You completed your ruck',
                        style: AppTextStyles.titleLarge,
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Session stats
                GridView.count(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.1,
                  children: [
                    StatCard(
                      title: 'Time',
                      value: _formatDuration(widget.duration),
                      icon: Icons.timer,
                      color: _getLadyModeColor(context),
                      centerContent: true,
                      valueFontSize: 36,
                    ),
                    StatCard(
                      title: 'Distance',
                      value: MeasurementUtils.formatDistance(widget.distance, metric: preferMetric),
                      icon: Icons.straighten,
                      color: _getLadyModeColor(context),
                      centerContent: true,
                      valueFontSize: 36,
                    ),
                    StatCard(
                      title: 'Calories',
                      value: widget.caloriesBurned.toString(),
                      icon: Icons.local_fire_department,
                      color: AppColors.accent,
                      centerContent: true,
                      valueFontSize: 36,
                    ),
                    StatCard(
                      title: 'Pace',
                      value: _formatPace(preferMetric),
                      icon: Icons.speed,
                      color: AppColors.secondary,
                      centerContent: true,
                      valueFontSize: 36,
                    ),
                    StatCard(
                      title: 'Elevation',
                      value: MeasurementUtils.formatElevationCompact(widget.elevationGain, widget.elevationLoss, metric: preferMetric),
                      icon: Icons.terrain,
                      color: AppColors.success,
                      centerContent: true,
                      valueFontSize: 28,
                    ),
                    StatCard(
                      title: 'Ruck Weight',
                      value: MeasurementUtils.formatWeight(widget.ruckWeight, metric: preferMetric),
                      icon: Icons.fitness_center,
                      color: AppColors.secondary,
                      centerContent: true,
                      valueFontSize: 36,
                    ),
                    // Heart Rate summary (if available)
                    if (_heartRateSamples != null && _heartRateSamples!.isNotEmpty) ...[
                      StatCard(
                        title: 'Avg HR',
                        value: _avgHeartRate?.toString() ?? '--',
                        icon: Icons.favorite,
                        color: AppColors.error,
                        centerContent: true,
                        valueFontSize: 36,
                      ),
                      StatCard(
                        title: 'Max HR',
                        value: _maxHeartRate?.toString() ?? '--',
                        icon: Icons.favorite_border,
                        color: AppColors.error,
                        centerContent: true,
                        valueFontSize: 36,
                      ),
                    ],
                  ],
                ),
                
                // Heart Rate Section 
                if (_heartRateSamples != null && _heartRateSamples!.isNotEmpty)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.favorite, color: AppColors.error, size: 20),
                          const SizedBox(width: 8),
                          Text('Heart Rate', style: AppTextStyles.titleMedium),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildStatCard('Avg', _avgHeartRate?.toString() ?? '--', 'bpm'),
                          _buildStatCard('Max', _maxHeartRate?.toString() ?? '--', 'bpm'),
                          _buildStatCard('Min', _minHeartRate?.toString() ?? '--', 'bpm'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 180,
                        child: _heartRateSamples!.isNotEmpty
                          ? LineChart(_buildHeartRateChart())
                          : Center(child: Text('No heart rate data available', style: TextStyle(color: Colors.grey[600]))),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Ruck Shots Photo Section
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 0.0),
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: PhotoUploadSection(
                    ruckId: widget.ruckId,
                    onPhotosSelected: (photos) {
                      setState(() {
                        _selectedPhotos.clear();
                        _selectedPhotos.addAll(photos);
                      });
                    },
                    isUploading: _isUploadingPhotos,
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Rating
                Text(
                  'How would you rate this session?',
                  style: AppTextStyles.titleMedium,
                ),
                const SizedBox(height: 8),
                Center(
                  child: RatingBar.builder(
                    initialRating: _rating.toDouble(),
                    minRating: 1,
                    direction: Axis.horizontal,
                    allowHalfRating: false,
                    itemCount: 5,
                    itemPadding: const EdgeInsets.symmetric(horizontal: 4.0),
                    itemBuilder: (context, _) => const Icon(
                      Icons.star,
                      color: Colors.amber,
                    ),
                    onRatingUpdate: (rating) {
                      setState(() {
                        _rating = rating.toInt();
                      });
                    },
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Perceived exertion
                Text(
                  'How difficult was this session? (1-10)',
                  style: AppTextStyles.titleMedium,
                ),
                const SizedBox(height: 8),
                Slider(
                  value: _perceivedExertion.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  label: _perceivedExertion.toString(),
                  onChanged: (value) {
                    setState(() {
                      _perceivedExertion = value.toInt();
                    });
                  },
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Easy', style: AppTextStyles.bodyMedium),
                    Text('Hard', style: AppTextStyles.bodyMedium),
                  ],
                ),
                
                const SizedBox(height: 24),
                
                // Tags section removed
                const SizedBox(height: 12),
                
                // Notes
                Text(
                  'Notes',
                  style: AppTextStyles.titleMedium,
                ),
                const SizedBox(height: 8),
                CustomTextField(
                  controller: _notesController,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => FocusScope.of(context).unfocus(),
                  label: 'Add notes about this session',
                  hint: 'How did it feel? What went well? What could be improved?',
                  maxLines: 4,
                  keyboardType: TextInputType.multiline,
                ),
                
                const SizedBox(height: 24),
                
                // Photo upload section moved above
                
                const SizedBox(height: 32),
                
                // Save button
                Center(
                  child: CustomButton(
                    onPressed: () {
                      if (!_isSaving) {
                        _saveAndContinue();
                      }
                    },
                    text: 'Save and Continue',
                    icon: Icons.save,
                    color: _getLadyModeColor(context),
                    isLoading: _isSaving,
                    width: 250,
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Discard this ruck option (red text, centered)
                Center(
                  child: TextButton(
                    onPressed: () => _showDeleteConfirmationDialog(context),
                    child: const Text(
                      'Discard this ruck',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    ));
  }
}

// Animated heart rate chart that draws from left to right
class _AnimatedHeartRateChart extends StatefulWidget {
  final List<HeartRateSample> heartRateSamples;
  final int? avgHeartRate;
  final int? maxHeartRate;
  final int? minHeartRate;
  final Color Function(BuildContext) getLadyModeColor;

  const _AnimatedHeartRateChart({
    required this.heartRateSamples,
    required this.avgHeartRate,
    required this.maxHeartRate,
    required this.minHeartRate,
    required this.getLadyModeColor,
  });

  @override
  State<_AnimatedHeartRateChart> createState() => _AnimatedHeartRateChartState();
}

class _AnimatedHeartRateChartState extends State<_AnimatedHeartRateChart> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    
    // Set up animation controller to run for 2 seconds - slower for smoother animation
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    
    // Create animation that goes from 0.0 to 1.0 with a smoother curve
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutQuad, // Using a smoother curve for animation
    );
    
    // Start the animation when widget is built
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return LineChart(
          _buildHeartRateChart(_animation.value),
        );
      },
    );
  }

  LineChartData _buildHeartRateChart(double animationValue) {
    if (widget.heartRateSamples.isEmpty) {
      return LineChartData();
    }
    
    // Calculate how many points to show based on animation value
    int pointsToShow = (widget.heartRateSamples.length * animationValue).round();
    pointsToShow = pointsToShow.clamp(1, widget.heartRateSamples.length);
    
    // Get the subset of samples to show for the current animation frame
    final visibleSamples = widget.heartRateSamples.sublist(0, pointsToShow);
    
    final firstTimestamp = widget.heartRateSamples.first.timestamp.millisecondsSinceEpoch.toDouble();
    
    final spots = visibleSamples.map((sample) {
      // Convert timestamp to minutes from session start for x-axis
      final timeOffset = (sample.timestamp.millisecondsSinceEpoch - firstTimestamp) / (1000 * 60);
      return FlSpot(timeOffset, sample.bpm.toDouble());
    }).toList();
    
    // debugPrint('[SESSION-COMPLETE] Created ${spots.length} spots for the heart rate chart'); // This debug line can be removed if not needed
    
    // Add safety checks for min/max values using widget properties
    final safeMinY = (widget.minHeartRate?.toDouble() ?? 60.0) - 10.0;
    final safeMaxY = (widget.maxHeartRate?.toDouble() ?? 180.0) + 10.0;
    final safeMaxX = spots.isNotEmpty ? spots.last.x : 10.0; // Ensure spots is not empty before accessing last.x
    
    // debugPrint('[SESSION-COMPLETE] Chart Y range: $safeMinY to $safeMaxY'); // These debug lines can be removed
    // debugPrint('[SESSION-COMPLETE] Chart X range: 0 to $safeMaxX');
    
    final lineColor = widget.getLadyModeColor(context);
    
    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        horizontalInterval: 30,
        verticalInterval: 5,
        getDrawingHorizontalLine: (value) {
          return FlLine(
            color: Colors.grey.shade300,
            strokeWidth: 1,
          );
        },
        getDrawingVerticalLine: (value) {
          return FlLine(
            color: Colors.grey.shade300,
            strokeWidth: 1,
          );
        },
      ),
      titlesData: FlTitlesData(
        show: true,
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 22, // Adjusted for better fit
            getTitlesWidget: (value, meta) {
              return SideTitleWidget(
                axisSide: meta.axisSide,
                child: Text(
                  '${value.round()}m',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                ),
              );
            },
            // Dynamic interval based on data range, clamped for sanity
            interval: spots.isNotEmpty && spots.last.x > 10 
                      ? (spots.last.x / 5).roundToDouble().clamp(1.0, 20.0) 
                      : 5,
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (value, meta) {
              return SideTitleWidget(
                axisSide: meta.axisSide,
                child: Text(
                  '${value.toInt()}',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                ),
              );
            },
            reservedSize: 30, // Adjusted for better fit
            interval: 30,
          ),
        ),
      ),
      borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey.shade300)),
      minX: 0,
      maxX: safeMaxX,
      minY: safeMinY,
      maxY: safeMaxY,
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          curveSmoothness: 0.25, // Adjust curve smoothness to match session detail
          color: lineColor,
          barWidth: 3.5, // Slightly thicker to match session detail
          isStrokeCapRound: true,
          dotData: FlDotData(show: false),
          belowBarData: BarAreaData(show: true, color: lineColor.withOpacity(0.2)),
        ),
      ],
      extraLinesData: ExtraLinesData(
        horizontalLines: [
          if (widget.maxHeartRate != null) // Ensure maxHeartRate is not null before using it
            HorizontalLine(
              y: widget.maxHeartRate!.toDouble(), // Use ! because of the null check
              color: Colors.red.withOpacity(0.6),
              strokeWidth: 1,
              dashArray: [5, 5],
              label: HorizontalLineLabel(
                show: true,
                alignment: Alignment.topRight,
                padding: const EdgeInsets.only(right: 5, bottom: 5),
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 10),
                labelResolver: (line) => 'Max: ${widget.maxHeartRate} bpm', // Add bpm unit to match session detail screen
              ),
            ),
        ],
      ),
    );
  }
}