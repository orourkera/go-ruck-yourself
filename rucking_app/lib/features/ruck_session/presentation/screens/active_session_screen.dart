import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/location_service.dart';
import 'package:rucking_app/core/models/location_point.dart';
import 'package:rucking_app/core/api/api_exceptions.dart';
import 'package:rucking_app/features/ruck_session/data/models/ruck_session.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/session_complete_screen.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/custom_button.dart';
import 'package:rucking_app/shared/widgets/stat_card.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';

/// Screen for tracking an active ruck session
class ActiveSessionScreen extends StatefulWidget {
  final String ruckId;
  final double ruckWeight;
  final double userWeight;
  final int? plannedDuration;
  final String? notes;

  const ActiveSessionScreen({
    Key? key,
    required this.ruckId,
    required this.ruckWeight,
    required this.userWeight,
    this.plannedDuration,
    this.notes,
  }) : super(key: key);

  @override
  State<ActiveSessionScreen> createState() => _ActiveSessionScreenState();
}

class _ActiveSessionScreenState extends State<ActiveSessionScreen> with WidgetsBindingObserver {
  // Services
  late final LocationServiceImpl _locationService;
  late final ApiClient _apiClient;
  
  // Session state
  bool _isPaused = false;
  bool _isEnding = false;
  
  // Timer variables
  late Stopwatch _stopwatch;
  late Timer _timer;
  Duration _elapsed = Duration.zero;
  
  // Location tracking
  StreamSubscription<LocationPoint>? _locationSubscription;
  final List<LocationPoint> _locationPoints = [];
  DateTime? _lastLocationUpdate;
  
  // Session stats
  double _distance = 0.0;
  double _pace = 0.0;
  double _caloriesBurned = 0.0;
  double _elevationGain = 0.0;
  double _elevationLoss = 0.0;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Initialize services
    _locationService = LocationServiceImpl();
    _apiClient = GetIt.instance<ApiClient>();
    
    // Request location permission at startup
    _requestLocationPermission();
    
    // Start session timer
    _stopwatch = Stopwatch()..start();
    _timer = Timer.periodic(const Duration(seconds: 1), _updateTime);
    
    // Start location tracking (will only run if permission granted)
    _initLocationTracking();
    
    // Notify API that session has started
    _startSession();
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer.cancel();
    _stopwatch.stop();
    _locationSubscription?.cancel();
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle app background/foreground transitions
    if (state == AppLifecycleState.paused && !_isPaused) {
      // App going to background, pause session
      _togglePause();
    }
  }
  
  /// Initialize location tracking service
  Future<void> _initLocationTracking() async {
    try {
      final hasPermission = await _locationService.hasLocationPermission();
      if (!hasPermission) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission is required for tracking'))
        );
        return;
      }
      
      // Start listening to location updates
      _locationSubscription = _locationService.startLocationTracking().listen(
        _handleLocationUpdate,
        onError: (error) {
          print('Location error: $error');
        }
      );
    } catch (e) {
      print('Failed to initialize location tracking: $e');
    }
  }
  
  /// Handle incoming location updates
  void _handleLocationUpdate(LocationPoint locationPoint) {
    if (_isPaused) return;
    
    final now = DateTime.now();
    
    // Add point to local list
    setState(() {
      _locationPoints.add(locationPoint);
    });
    
    // Calculate stats based on new point
    _calculateStats(locationPoint);
    
    // Send update to API every 10 seconds
    if (_lastLocationUpdate == null || 
        now.difference(_lastLocationUpdate!).inSeconds >= 10) {
      _sendLocationUpdate(locationPoint);
      _lastLocationUpdate = now;
    }
  }
  
  /// Calculate new stats based on new location point
  void _calculateStats(LocationPoint newPoint) {
    if (_locationPoints.length < 2) return;
    
    final previousPoint = _locationPoints[_locationPoints.length - 2];
    
    // Calculate distance increment
    final double distanceIncrement = _locationService.calculateDistance(
      previousPoint, 
      newPoint,
    );
    
    // Calculate elevation changes
    double elevationChange = newPoint.elevation - previousPoint.elevation;
    double elevationGainIncrement = elevationChange > 0 ? elevationChange : 0;
    double elevationLossIncrement = elevationChange < 0 ? -elevationChange : 0;
    
    setState(() {
      // Update distance
      _distance += distanceIncrement;
      
      // Update pace (minutes per km)
      _pace = _distance > 0
          ? (_elapsed.inSeconds / 60) / _distance
          : 0.0;
      
      // Update elevation metrics
      _elevationGain += elevationGainIncrement;
      _elevationLoss += elevationLossIncrement;
      
      // Get weight in kg for calculations - convert from lbs if needed
      final authState = context.read<AuthBloc>().state;
      bool preferMetric = authState is Authenticated ? authState.user.preferMetric : false;
      double ruckWeightKg = preferMetric 
          ? widget.ruckWeight 
          : widget.ruckWeight / 2.20462; // Convert lbs to kg
          
      // Convert user weight to kg if needed
      double userWeightKg = preferMetric
          ? widget.userWeight
          : widget.userWeight / 2.20462; // Convert lbs to kg
      
      // Estimate calories burned based on weight, distance, and elevation
      // This is a more accurate formula using actual body weight
      _caloriesBurned = (_distance * 
          (ruckWeightKg * 0.1 + userWeightKg) / 10) + 
          (_elevationGain * 0.05 * (ruckWeightKg + userWeightKg));
    });
  }
  
  /// Send location update to API
  Future<void> _sendLocationUpdate(LocationPoint point) async {
    try {
      final response = await _apiClient.post(
        '/rucks/${widget.ruckId}/location',
        {
          'latitude': point.latitude,
          'longitude': point.longitude,
          'elevation_meters': point.elevation,
          'timestamp': point.timestamp.toIso8601String(),
          'accuracy_meters': point.accuracy,
        },
      );
      
      // Update stats from server if available
      if (response.containsKey('current_stats')) {
        final stats = response['current_stats'];
        setState(() {
          _distance = stats['distance_km'] ?? _distance;
          _caloriesBurned = stats['calories_burned']?.toDouble() ?? _caloriesBurned;
          _elevationGain = stats['elevation_gain_meters'] ?? _elevationGain;
          _elevationLoss = stats['elevation_loss_meters'] ?? _elevationLoss;
          
          // Calculate pace from duration and distance
          if (stats['average_pace_min_km'] != null) {
            _pace = stats['average_pace_min_km'];
          }
        });
      }
    } catch (e) {
      // Handle error silently to avoid disturbing the user
      print('Failed to send location update: $e');
    }
  }
  
  /// Start session on the backend
  Future<void> _startSession() async {
    try {
      await _apiClient.post('/rucks/${widget.ruckId}/start', {});
    } catch (e) {
      print('Failed to start session: $e');
      
      // Handle unauthorized errors specifically
      if (e is UnauthorizedException) {
        // More specific error message for auth issues
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('You must be logged in to track sessions. Please log in.'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Close',
              onPressed: () {
                Navigator.of(context).pop(); // Go back to previous screen
              },
            ),
          )
        );
      } else {
        // Generic error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start session: $e'))
        );
      }
    }
  }
  
  /// Updates the elapsed time display
  void _updateTime(Timer timer) {
    if (mounted) {
      setState(() {
        _elapsed = _stopwatch.elapsed;
      });
    }
  }
  
  /// Toggles pause/resume state
  Future<void> _togglePause() async {
    setState(() {
      if (_isPaused) {
        _stopwatch.start();
        _isPaused = false;
        
        // Resume location tracking
        _initLocationTracking();
        
        // Notify API
        _apiClient.post('/rucks/${widget.ruckId}/resume', {})
            .catchError((e) => print('Failed to resume session: $e'));
      } else {
        _stopwatch.stop();
        _isPaused = true;
        
        // Pause location tracking
        _locationSubscription?.pause();
        
        // Notify API
        _apiClient.post('/rucks/${widget.ruckId}/pause', {})
            .catchError((e) => print('Failed to pause session: $e'));
      }
    });
  }
  
  /// Ends the current session
  Future<void> _endSession() async {
    // Stop timers and tracking immediately
    _timer.cancel();
    _stopwatch.stop();
    _locationSubscription?.cancel();
    
    setState(() {
      _isEnding = true; // Keep UI disabled while navigating
    });
    
    // Navigate to completion screen, passing final calculated stats
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => SessionCompleteScreen(
            ruckId: widget.ruckId,
            duration: _elapsed, // Pass final elapsed time
            distance: _distance, // Pass final calculated distance
            caloriesBurned: _caloriesBurned.round(), // Pass final calculated calories
            elevationGain: _elevationGain,
            elevationLoss: _elevationLoss,
            ruckWeight: widget.ruckWeight,
            // Pass initial notes if available, SessionCompleteScreen allows editing
            initialNotes: widget.notes, 
          ),
        ),
      );
    } 
    // No need for try-catch or setting _isEnding=false if only navigating
  }
  
  /// Shows a confirmation dialog for ending the session
  void _showEndConfirmationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End Session'),
        content: const Text('Are you sure you want to end this session?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _endSession();
            },
            child: const Text('End Session'),
          ),
        ],
      ),
    );
  }

  /// Format duration as HH:MM:SS
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$hours:$minutes:$seconds";
  }

  /// Request location permission
  Future<void> _requestLocationPermission() async {
    final hasPermission = await _locationService.hasLocationPermission();
    if (!hasPermission) {
      final granted = await _locationService.requestLocationPermission();
      if (!granted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission is required for tracking. Please enable it in settings.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get user's unit preference
    final authState = context.read<AuthBloc>().state;
    final bool preferMetric = authState is Authenticated ? authState.user.preferMetric : false;
    
    // Format ruck weight based on user preference
    final String weightDisplay = preferMetric 
        ? '${widget.ruckWeight.toStringAsFixed(1)} kg'
        : '${widget.ruckWeight.toStringAsFixed(1)} lbs';
    
    // Format distance based on user preference
    final String distanceDisplay = preferMetric
        ? '${_distance.toStringAsFixed(2)} km'
        : '${(_distance * 0.621371).toStringAsFixed(2)} mi';
    
    // Format pace based on user preference
    final String paceDisplay = preferMetric
        ? '${_pace.toStringAsFixed(2)} min/km'
        : '${(_pace / 0.621371).toStringAsFixed(2)} min/mi';
        
    // Format elevation gain based on user preference
    final String elevationGainDisplay = preferMetric
        ? '+${_elevationGain.toStringAsFixed(1)} m'
        : '+${(_elevationGain * 3.28084).toStringAsFixed(1)} ft';
        
    // Format elevation loss based on user preference
    final String elevationLossDisplay = preferMetric
        ? '-${_elevationLoss.toStringAsFixed(1)} m'
        : '-${(_elevationLoss * 3.28084).toStringAsFixed(1)} ft';
    
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        title: const Text('ACTIVE SESSION'),
        centerTitle: true,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Timer display
          Container(
            color: AppColors.backgroundLight,
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(
              children: [
                // Time display
                Text(
                  _formatDuration(_elapsed),
                  style: AppTextStyles.headline3.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                // Weight display 
                Text(
                  'Ruck weight: $weightDisplay',
                  style: AppTextStyles.subtitle1.copyWith(
                    color: AppColors.textDarkSecondary,
                  ),
                ),
              ],
            ),
          ),
          
          // Stats grid
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // First row of stats
                  Expanded(
                    child: Row(
                      children: [
                        // Distance card
                        Expanded(
                          child: StatCard(
                            title: 'Distance',
                            value: distanceDisplay,
                            icon: Icons.straighten,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Pace card
                        Expanded(
                          child: StatCard(
                            title: 'Pace',
                            value: paceDisplay,
                            icon: Icons.speed,
                            color: AppColors.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Second row of stats
                  Expanded(
                    child: Row(
                      children: [
                        // Calories card
                        Expanded(
                          child: StatCard(
                            title: 'Calories',
                            value: _caloriesBurned.toInt().toString(),
                            icon: Icons.local_fire_department,
                            color: AppColors.accent,
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Elevation card
                        Expanded(
                          child: StatCard(
                            title: 'Elevation',
                            value: elevationGainDisplay,
                            secondaryValue: elevationLossDisplay,
                            icon: Icons.terrain,
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Controls section
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Pause/Resume Button
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _togglePause,
                    icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause),
                    label: Text(
                      _isPaused ? 'RESUME' : 'PAUSE',
                      style: AppTextStyles.button.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // End session button
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isEnding ? null : _showEndConfirmationDialog,
                    icon: const Icon(Icons.stop),
                    label: const Text(
                      'END SESSION',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
} 