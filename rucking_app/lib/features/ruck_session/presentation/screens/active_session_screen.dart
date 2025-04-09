import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/location_service.dart';
import 'package:rucking_app/core/models/location_point.dart';
import 'package:rucking_app/features/ruck_session/data/models/ruck_session.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/session_complete_screen.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/custom_button.dart';
import 'package:rucking_app/shared/widgets/stat_card.dart';
import 'package:get_it/get_it.dart';

/// Screen for tracking an active ruck session
class ActiveSessionScreen extends StatefulWidget {
  final String ruckId;
  final double ruckWeight;
  final int? plannedDuration;
  final String? notes;

  const ActiveSessionScreen({
    Key? key,
    required this.ruckId,
    required this.ruckWeight,
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
    
    // Start session timer
    _stopwatch = Stopwatch()..start();
    _timer = Timer.periodic(const Duration(seconds: 1), _updateTime);
    
    // Start location tracking
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
  
  /// Calculate session statistics based on location data
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
      
      // Estimate calories burned based on weight, distance, and elevation
      // This is a simplified formula - real apps would use more accurate models
      _caloriesBurned = (_distance * 
          (widget.ruckWeight * 0.1 + 60) / 10) + 
          (_elevationGain * 0.05 * (widget.ruckWeight + 60));
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start session: $e'))
      );
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
    setState(() {
      _isEnding = true;
    });
    
    try {
      // Complete session on backend
      await _apiClient.post('/rucks/${widget.ruckId}/complete', {
        'notes': widget.notes,
      });
      
      // Navigate to completion screen
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => SessionCompleteScreen(
              ruckId: widget.ruckId,
              duration: _elapsed,
              distance: _distance,
              caloriesBurned: _caloriesBurned.round(),
              elevationGain: _elevationGain,
              elevationLoss: _elevationLoss,
              ruckWeight: widget.ruckWeight,
            ),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isEnding = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to end session: $e'))
      );
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Active Session'),
        centerTitle: true,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Timer display
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              color: AppColors.primary.withOpacity(0.1),
              child: Center(
                child: Column(
                  children: [
                    Text(
                      _formatDuration(_elapsed),
                      style: AppTextStyles.headline3.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Ruck weight: ${widget.ruckWeight} kg',
                      style: AppTextStyles.body1,
                    ),
                  ],
                ),
              ),
            ),
            
            // Stats grid
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                padding: const EdgeInsets.all(16),
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.5,
                children: [
                  StatCard(
                    title: 'Distance',
                    value: '${_distance.toStringAsFixed(2)} km',
                    icon: Icons.straighten,
                    color: AppColors.primary,
                  ),
                  StatCard(
                    title: 'Pace',
                    value: '${_pace.toStringAsFixed(2)} min/km',
                    icon: Icons.speed,
                    color: AppColors.secondary,
                  ),
                  StatCard(
                    title: 'Calories',
                    value: '${_caloriesBurned.round()}',
                    icon: Icons.local_fire_department,
                    color: Colors.orange,
                  ),
                  StatCard(
                    title: 'Elevation',
                    value: '+${_elevationGain.toStringAsFixed(1)} m',
                    secondaryValue: '-${_elevationLoss.toStringAsFixed(1)} m',
                    icon: Icons.terrain,
                    color: Colors.green,
                  ),
                ],
              ),
            ),
            
            // Controls
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Pause/Resume button
                  CustomButton(
                    onPressed: _togglePause,
                    text: _isPaused ? 'Resume' : 'Pause',
                    icon: _isPaused ? Icons.play_arrow : Icons.pause,
                    color: _isPaused 
                        ? Colors.green 
                        : AppColors.primary,
                    isLoading: false,
                    width: 150,
                  ),
                  
                  // End session button
                  CustomButton(
                    onPressed: _isEnding ? (){} : _showEndConfirmationDialog,
                    text: 'End Session',
                    icon: Icons.stop,
                    color: Colors.red,
                    isLoading: _isEnding,
                    width: 150,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
} 