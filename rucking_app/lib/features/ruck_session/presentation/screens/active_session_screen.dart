import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
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
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

LatLng _getRouteCenter(List locationPoints) {
  if (locationPoints.isEmpty) return LatLng(40.421, -3.678);
  double avgLat = locationPoints.map((p) => p.latitude).reduce((a, b) => a + b) / locationPoints.length;
  double avgLng = locationPoints.map((p) => p.longitude).reduce((a, b) => a + b) / locationPoints.length;
  return LatLng(avgLat, avgLng);
}

double _getFitZoom(List locationPoints) {
  if (locationPoints.length < 2) return 15.5;
  final points = locationPoints.map((p) => LatLng(p.latitude, p.longitude)).toList();
  final bounds = LatLngBounds.fromPoints(points);
  final latDiff = (bounds.north - bounds.south).abs();
  final lngDiff = (bounds.east - bounds.west).abs();
  final maxDiff = [latDiff, lngDiff].reduce((a, b) => a > b ? a : b);
  if (maxDiff < 0.001) return 17.0;
  if (maxDiff < 0.01) return 15.0;
  if (maxDiff < 0.05) return 13.0;
  if (maxDiff < 0.1) return 11.0;
  return 9.0;
}

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
  // Countdown for planned duration
  Duration? _plannedCountdownStart;
  
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
    
    // Reset all session stats to ensure a clean start
    _distance = 0.0;
    _pace = 0.0;
    _caloriesBurned = 0.0;
    _elevationGain = 0.0;
    _elevationLoss = 0.0;
    _elapsed = Duration.zero;
    _locationPoints.clear();
    _lastLocationUpdate = null;
    
    // Request location permission at startup
    _requestLocationPermission();
    
    // Start session timer
    _stopwatch = Stopwatch()..start();
    _timer = Timer.periodic(const Duration(seconds: 1), _updateTime);
    
    // Start location tracking (will only run if permission granted)
    _initLocationTracking();
    
    // Notify API that session has started
    _startSession();
    
    // Set planned countdown if provided
    if (widget.plannedDuration != null && widget.plannedDuration! > 0) {
      _plannedCountdownStart = Duration(minutes: widget.plannedDuration!);
    }
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
    // No automatic pause on background; session continues unless user explicitly pauses or ends.
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
    if (!_isPaused) {
      setState(() {
        _elapsed = Duration(seconds: _stopwatch.elapsed.inSeconds);
        // Recalculate pace and calories in real time
        if (_distance > 0 && _elapsed.inSeconds > 0) {
          _pace = _elapsed.inMinutes / _distance; // min/km
        }
        // Calories calculation (repeat logic from _calculateStats)
        final authState = context.read<AuthBloc>().state;
        final bool preferMetric = authState is Authenticated ? authState.user.preferMetric : false;
        double ruckWeightKg = preferMetric 
            ? widget.ruckWeight 
            : widget.ruckWeight / 2.20462; // Convert lbs to kg
        double userWeightKg = preferMetric
            ? widget.userWeight
            : widget.userWeight / 2.20462; // Convert lbs to kg
        _caloriesBurned = (_distance * 
            (ruckWeightKg * 0.1 + userWeightKg) / 10) + 
            (_elevationGain * 0.05 * (ruckWeightKg + userWeightKg));
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
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Map at the very top below header (fixed size, not in scroll view)
            Container(
              width: double.infinity,
              height: 240,
              child: FlutterMap(
                options: MapOptions(
                  center: _locationPoints.isNotEmpty
                      ? _getRouteCenter(_locationPoints)
                      : LatLng(40.421, -3.678),
                  zoom: _locationPoints.length > 1 ? _getFitZoom(_locationPoints) : 15.5,
                  interactiveFlags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                  bounds: _locationPoints.length > 1 ? LatLngBounds.fromPoints(_locationPoints.map((p) => LatLng(p.latitude, p.longitude)).toList()) : null,
                  boundsOptions: const FitBoundsOptions(padding: EdgeInsets.all(20)),
                ),
                children: [
                  TileLayer(
                    urlTemplate: "https://tiles.stadiamaps.com/tiles/stamen_terrain/{z}/{x}/{y}{r}.png?api_key=${dotenv.env['STADIA_MAPS_API_KEY']}",
                    userAgentPackageName: 'com.getrucky.gfy',
                  ),
                  if (_locationPoints.isNotEmpty)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _locationPoints.map((p) => LatLng(p.latitude, p.longitude)).toList(),
                          color: AppColors.primary,
                          strokeWidth: 4.0,
                        ),
                      ],
                    ),
                  if (_locationPoints.isNotEmpty)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(_locationPoints.last.latitude, _locationPoints.last.longitude),
                          width: 30,
                          height: 30,
                          builder: (ctx) => const Icon(Icons.location_pin, color: Colors.red, size: 30),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // The rest of the content is scrollable
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Timer and ruck weight
                    Padding(
                      padding: const EdgeInsets.only(top: 16, left: 16, right: 16),
                      child: Column(
                        children: [
                          // Timer
                          Text(
                            _formatDuration(_elapsed),
                            style: AppTextStyles.timerDisplay,
                            textAlign: TextAlign.center,
                          ),
                          if (_plannedCountdownStart != null && widget.plannedDuration != null && widget.plannedDuration! > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
                              child: Text(
                                _plannedCountdownStart!.inSeconds - _elapsed.inSeconds > 0
                                  ? _formatDuration(Duration(seconds: _plannedCountdownStart!.inSeconds - _elapsed.inSeconds))
                                  : '00:00:00',
                                style: AppTextStyles.headline3.copyWith(
                                  fontSize: 20,
                                  color: AppColors.secondary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          // Ruck weight (smaller, neutral color, less vertical space)
                          Text(
                            weightDisplay,
                            style: AppTextStyles.body2.copyWith(fontSize: 18, color: AppColors.textDarkSecondary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Stats grid (fix overflow, calories up)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              // Distance card
                              Expanded(
                                child: StatCard(
                                  title: 'Distance',
                                  value: distanceDisplay,
                                  icon: Icons.straighten,
                                  color: AppColors.primary,
                                  centerContent: true,
                                  valueFontSize: 28,
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Calories card (moved up)
                              Expanded(
                                child: StatCard(
                                  title: 'Calories',
                                  value: _caloriesBurned.toInt().toString(),
                                  icon: Icons.local_fire_department,
                                  color: AppColors.accent,
                                  centerContent: true,
                                  valueFontSize: 28,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              // Pace card
                              Expanded(
                                child: StatCard(
                                  title: 'Pace',
                                  value: paceDisplay,
                                  icon: Icons.speed,
                                  color: AppColors.secondary,
                                  centerContent: true,
                                  valueFontSize: 28,
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Elevation card
                              Expanded(
                                child: StatCard(
                                  title: 'Elevation',
                                  value: elevationGainDisplay,
                                  secondaryValue: elevationLossDisplay,
                                  icon: Icons.terrain,
                                  color: AppColors.success,
                                  centerContent: true,
                                  valueFontSize: 28,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Controls section (unchanged)
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}