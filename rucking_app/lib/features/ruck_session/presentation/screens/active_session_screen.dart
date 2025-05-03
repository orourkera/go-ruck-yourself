import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:rucking_app/core/models/location_point.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/location_service.dart';
import 'package:rucking_app/core/utils/met_calculator.dart';
import 'package:rucking_app/features/health_integration/bloc/health_bloc.dart';
import 'package:rucking_app/features/health_integration/domain/health_service.dart';
import 'package:rucking_app/features/ruck_session/domain/services/session_validation_service.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/session_complete_screen.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:rucking_app/core/api/api_exceptions.dart';
import 'package:rucking_app/features/ruck_session/data/models/ruck_session.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/core/config/app_config.dart';
import 'package:rucking_app/core/utils/measurement_utils.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:rucking_app/core/error_messages.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/utils/error_handler.dart';

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
  final double displayRuckWeight;
  final bool preferMetric;
  final int? plannedDuration;
  final String? notes;

  const ActiveSessionScreen({
    Key? key,
    required this.ruckId,
    required this.ruckWeight,
    required this.userWeight,
    required this.displayRuckWeight,
    required this.preferMetric,
    this.plannedDuration,
    this.notes,
  }) : super(key: key);

  @override
  State<ActiveSessionScreen> createState() => _ActiveSessionScreenState();
}

class _ActiveSessionScreenState extends State<ActiveSessionScreen> with WidgetsBindingObserver {
  // Services
  late LocationService _locationService;
  late ApiClient _apiClient;
  late SessionValidationService _validationService;
  late HealthService _healthService;
  
  // Session state
  bool _isPaused = false;
  bool _isEnding = false;
  String? _validationMessage;
  bool _showValidationMessage = false;
  bool _isSessionEnded = false; // New flag
  
  // Timer variables
  late Stopwatch _stopwatch;
  Timer? _timer;
  Timer? _heartRateTimer;
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
  double? _heartRate; // Current heart rate from health kit
  List<double> _recentPaces = [];
  // Exponential moving-average smoothing factor for pace (0 = no smoothing, 1 = no lag)
  static const double _paceAlpha = 0.05;
  bool _canShowStats = false;
  double _uncountedDistance = 0.0;
  
  // User preferences
  bool _preferMetric = true; // Default, will be overridden
  double _userWeightKg = 75.0; // Default, will be overridden
  double ruckWeightKg = 0.0;

  // Custom marker icon data
  Uint8List? _customMarkerIcon;

  DateTime _startTime = DateTime.now();

  /// Shows an error message in a SnackBar
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initialize services
    _apiClient = GetIt.instance<ApiClient>();
    _locationService = GetIt.instance<LocationService>();
    _validationService = SessionValidationService();
    _healthService = HealthService();
    
    // Get user preference and weight
    final authState = context.read<AuthBloc>().state;
    if (authState is Authenticated) {
      _preferMetric = authState.user.preferMetric;
      _userWeightKg = authState.user.weightKg ?? widget.userWeight;
    } else {
      _userWeightKg = widget.userWeight;
    }
    ruckWeightKg = widget.ruckWeight;
    
    // Initialize stopwatch
    _stopwatch = Stopwatch();
    
    // --- MAP AND LOCATION LOAD FIRST ---
    _initLocationTracking(); // Always load map and location as first thing

    _distance = 0.0;
    _pace = 0.0;
    _caloriesBurned = 0.0;
    _elevationGain = 0.0;
    _elevationLoss = 0.0;
    _elapsed = Duration.zero;
    _locationPoints.clear();
    _lastLocationUpdate = null;
    _recentPaces.clear();
    _canShowStats = false;
    _uncountedDistance = 0.0;
    
    // Initialize session weights for BLoC
    _initializeSessionWeights();
    _startSession(); // Start the timers and stopwatch
    
    // Set planned countdown if provided
    if (widget.plannedDuration != null && widget.plannedDuration! > 0) {
      _plannedCountdownStart = Duration(minutes: widget.plannedDuration!);
    }

    // Load custom marker icon
    _loadCustomMarker();
  }

  void _initializeSessionWeights() {
    // Start session in BLoC with weights
    context.read<ActiveSessionBloc>().add(
      SessionStarted(
        ruckWeightKg: ruckWeightKg,
        notes: 'Session started with ${ruckWeightKg}kg ruck weight',
      ),
    );
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _stopwatch.stop();
    _stopLocationTracking(); // Explicitly stop location tracking
    _stopHeartRateMonitoring();
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Removed automatic pausing on background/lock so the timer keeps running.
    // If you need to react to termination, handle AppLifecycleState.detached here.
  }
  
  /// Initialize location tracking service
  Future<void> _initLocationTracking() async {
    try {
      AppLogger.info('Starting location tracking...');
      final hasPermission = await _locationService.hasLocationPermission();
      if (!hasPermission) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(sessionLocationPermissionDenied), backgroundColor: Colors.red),
        );
        return;
      }
      
      // Start listening to location updates and get initial position for map
      _locationSubscription = _locationService.startLocationTracking().listen(
        _handleLocationUpdate,
        onError: (error) {
          AppLogger.error('Location tracking error: $error');
        }
      );
      
      // Get current location to initialize map immediately
      try {
        final initialLocation = await _locationService.getCurrentLocation();
        if (initialLocation != null) {
          _locationPoints.add(initialLocation);
          setState(() {}); // Update UI with initial position
        }
      } catch (e) {
        AppLogger.error('Failed to get initial location: $e');
      }
      AppLogger.info('Location tracking started successfully.');
    } catch (e) {
      AppLogger.error('Error starting location tracking: $e');
    }
  }
  
  /// Handle incoming location updates
  void _handleLocationUpdate(LocationPoint locationPoint) {
    if (_isSessionEnded) {
      AppLogger.info('Session ended. Ignoring location update.');
      return;
    }
    
    if (_isPaused) return;
    
    if (_locationPoints.isNotEmpty) {
      // Validate the location point
      final previousPoint = _locationPoints.last;
      final validation = _validationService.validateLocationPoint(
        locationPoint, 
        previousPoint, 
      );
      
      // Handle invalid points
      if (!validation['isValid']) {
        // Show error message
        setState(() {
          _validationMessage = validation['message'];
          _showValidationMessage = true;
        });
        
        // Hide message after 5 seconds
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted) {
            setState(() {
              _showValidationMessage = false;
            });
          }
        });
        
        // Don't process invalid points
        return;
      }
      
      // Check if session should end due to long idle time
      if (validation['shouldEnd'] == true) {
        setState(() {
          _validationMessage = validation['message'];
          _showValidationMessage = true;
        });
        
        // Show a dialog asking the user if they want to end the session
        _showIdleEndConfirmationDialog();
        return;
      }
      
      // Auto-pause if needed
      if (validation['shouldPause'] && !_isPaused) {
        setState(() {
          _validationMessage = sessionAutoPaused;
          _showValidationMessage = true;
        });
        _togglePause();
        return;
      }
      
      // Check if initial distance threshold has been reached
      if (validation.containsKey('initialDistanceReached') && 
          validation['initialDistanceReached'] == true && 
          !_canShowStats) {
        setState(() {
          _canShowStats = true;
          // Transfer accumulated untracked distance to official distance
          _uncountedDistance = _validationService.getAccumulatedDistanceMeters();
          _distance = _uncountedDistance / 1000; // Convert to km
        });
      }
    }
    
    // Add point to route
    _locationPoints.add(locationPoint);
    _lastLocationUpdate = DateTime.now();
    
    // Only calculate stats if we're past initial threshold or this is first couple of points
    if (_canShowStats || _locationPoints.length <= 2) {
      _calculateStats(locationPoint);
    }
    
    // Update the UI
    if (mounted) setState(() {});
    
    // Send point to API in the background
    _sendLocationUpdate(locationPoint);
  }

  /// Calculate new stats based on new location point
  void _calculateStats(LocationPoint newPoint) {
    // Only process if we have at least two points
    if (_locationPoints.length < 2) return;
    
    // Get previous point for calculations
    final previousPoint = _locationPoints[_locationPoints.length - 2];
    
    // Calculate distance between points in kilometers
    final distanceMeters = _locationService.calculateDistance(previousPoint, newPoint) * 1000;
    
    // Only update stats if we're past the initial threshold or collecting initial data
    if (_canShowStats) {
      // Update distance
      _distance += distanceMeters / 1000; // Convert to km
      
      // Calculate elevation changes
      final elevationChange = newPoint.elevation - previousPoint.elevation;
      if (elevationChange > 0) {
        _elevationGain += elevationChange;
      } else {
        _elevationLoss += elevationChange.abs();
      }
      
      // Calculate overall average pace (seconds per km)
      if (_distance > 0 && _elapsed.inSeconds > 0) {
        _pace = _elapsed.inSeconds / _distance; 
      } else {
        _pace = 0.0;
      }

      // Calculate MET value using the correct method - based on segment pace for accuracy
      // Need segment pace calculation here, even if not used for the main _pace variable
      double segmentSpeedKmh = 0.0;
      if (distanceMeters > 0) {
        final segmentSeconds = DateTime.now().difference(previousPoint.timestamp).inSeconds;
        if (segmentSeconds > 0) {
           final segmentPaceSecPerKm = segmentSeconds / (distanceMeters / 1000);
           segmentSpeedKmh = 3600 / segmentPaceSecPerKm;
        }
      }
      final double speedMph = MetCalculator.kmhToMph(segmentSpeedKmh);
      final double ruckWeightKg = widget.ruckWeight;
      final double ruckWeightLbs = ruckWeightKg * AppConfig.kgToLbs;

      final grade = MetCalculator.calculateGrade(
        elevationChangeMeters: elevationChange,
        distanceMeters: distanceMeters,
      );

      final metValue = MetCalculator.calculateRuckingMetByGrade(
        speedMph: speedMph,
        grade: grade,
        ruckWeightLbs: ruckWeightLbs, 
      );

      // Calculate segment time in minutes
      final segmentTimeMinutes = DateTime.now().difference(previousPoint.timestamp).inSeconds / 60;

      // Calculate calories burned for this segment
      final segmentCalories = MetCalculator.calculateCaloriesBurned(
        weightKg: _userWeightKg + (ruckWeightKg * 0.75), // Count 75% of ruck weight
        durationMinutes: segmentTimeMinutes, // Use fractional minutes
        metValue: metValue,
      );
      
      _caloriesBurned += segmentCalories;
      
    } else {
      // Still in initial distance collection phase
      _uncountedDistance = _validationService.getAccumulatedDistanceMeters();
    }
  }
  
  /// Send location update to API
  Future<void> _sendLocationUpdate(LocationPoint locationPoint) async {
    try {
      // Ensure all numeric values are doubles
      final payload = {
        'latitude': locationPoint.latitude.toDouble(),
        'longitude': locationPoint.longitude.toDouble(),
        'elevation_meters': locationPoint.elevation.toDouble(),
        'timestamp': locationPoint.timestamp.toIso8601String(),
        'accuracy_meters': locationPoint.accuracy.toDouble(),
      };
      AppLogger.info('Sending location update payload: $payload');
      await _apiClient.post(
        '/rucks/${widget.ruckId}/location',
        payload,
      ).catchError((e) {
        AppLogger.error('Failed to send location update: $e');
        return; // Ensure a return even in error case
      });
    } catch (e) {
      AppLogger.error('Error in _sendLocationUpdate: $e');
    }
  }
  
  /// Start session on the backend
  Future<void> _startSession() async {
    // Start stopwatch
    _stopwatch.start();
    _timer = Timer.periodic(const Duration(seconds: 1), _updateTime);
    
    // Start heart rate monitoring if health integration is available
    _startHeartRateMonitoring();
    
    // Request location permissions if needed
    bool hasPermission = await _locationService.hasLocationPermission();
    if (!hasPermission) {
      hasPermission = await _locationService.requestLocationPermission();
    }
    
    if (!hasPermission) {
      setState(() {
        _isPaused = true;
        _stopwatch.stop();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(sessionLocationPermissionDenied), backgroundColor: Colors.red),
      );
      return;
    }
    
    // Start location tracking
    await _initLocationTracking();
    
    try {
      await _apiClient.post('/rucks/${widget.ruckId}/start', {});
    } catch (e) {
      AppLogger.error('Failed to start session: $e');
      
      // Handle unauthorized errors specifically
      if (e is UnauthorizedException) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Your session has expired. Please login again.'),
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
          SnackBar(content: Text(ErrorHandler.getUserFriendlyMessage(e, 'Start Session')))
        );
      }
    }
  }
  
  /// Updates the elapsed time display
  void _updateTime(Timer timer) {
    if (!_isPaused) {
      setState(() {
        _elapsed = Duration(seconds: _stopwatch.elapsed.inSeconds);
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
        _locationSubscription?.resume();
        // Notify API
        _apiClient.post('/rucks/${widget.ruckId}/resume', {})
            .catchError((e) => AppLogger.error('Failed to resume session: $e'));
      } else {
        _stopwatch.stop();
        _isPaused = true;
        // Pause location tracking
        _locationSubscription?.pause();
        // Notify API
        _apiClient.post('/rucks/${widget.ruckId}/pause', {})
            .catchError((e) => AppLogger.error('Failed to pause session: $e'));
      }
    });
  }
  
  /// Ends the current session
  Future<void> _endSession() async {
    if (_isEnding) return;
    setState(() => _isEnding = true);

    try {
      // Stop tracking location
      await _locationService.stopLocationTracking();
      _timer?.cancel();
      // Removed erroneous: setState(() => _isTracking = false);

      // Check if session is too short
      if (_elapsed.inSeconds < 60) {
        _showShortSessionDialog();
        setState(() => _isEnding = false);
        return;
      }

      // Calculate final values
      final double finalDistanceKm = _distance;
      final String ruckId = widget.ruckId ?? 'temp-id';
      
      // Navigate to SessionCompleteScreen
      Navigator.of(context).pushNamed(
        '/session_complete',
        arguments: {
          'completedAt': DateTime.now(),
          'ruckId': ruckId,
          'duration': _elapsed,
          'distance': finalDistanceKm,
          'caloriesBurned': _calculateCalories().toInt(),
          'elevationGain': _elevationGain,
          'elevationLoss': _elevationLoss,
          'ruckWeight': widget.ruckWeight,
        },
      );
    } catch (e) {
      AppLogger.error('Error ending session: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to end session. Please try again.'),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: _endSession,
            ),
          ),
        );
      }
    } finally {
      if (_isEnding) {
        setState(() => _isEnding = false);
      }
    }
  }
  
  /// Show dialog for completed session to gather rating and notes
  void _showCompletionDialog({
    required double distanceKm,
    required int durationSeconds,
    required double caloriesBurned,
    required double avgPaceMinPerKm,
    required double elevationGain,
    required double elevationLoss,
  }) {
    // Navigate to SessionCompleteScreen instead of showing a dialog
    final String ruckId = widget.ruckId ?? 'temp-id';
    Navigator.of(context).pushNamed(
      '/session_complete',
      arguments: {
        'completedAt': DateTime.now(),
        'ruckId': ruckId,
        'duration': Duration(seconds: durationSeconds),
        'distance': distanceKm,
        'caloriesBurned': caloriesBurned.toInt(),
        'elevationGain': elevationGain,
        'elevationLoss': elevationLoss,
        'ruckWeight': widget.ruckWeight,
      },
    );
  }
  
  /// Show dialog for session that is too short
  void _showShortSessionDialog() {
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Session Too Short'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your session is too short to save.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Distance: ${_distance.toStringAsFixed(2)} km (minimum 0.1 km)'),
            Text('Duration: ${_formatDuration(_elapsed)} (minimum 2 min)'),
            const SizedBox(height: 12),
            const Text(
              'To save your workout, please make sure to ruck for at least 100 meters and 2 minutes.',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            child: const Text('OK'),
            onPressed: () {
              Navigator.of(context).pop(); // Close dialog
              Navigator.of(context).pop(); // Return to previous screen
            },
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
          const SnackBar(content: Text(sessionLocationPermissionDenied), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Start heart rate monitoring
  void _startHeartRateMonitoring() async {
    // Check if health integration is enabled
    final isEnabled = await _healthService.isHealthIntegrationEnabled();
    if (!isEnabled) {
      return;
    }
    
    // Request authorization for heart rate monitoring
    await _healthService.requestAuthorization();
    
    // Start periodic heart rate updates every 15 seconds
    _heartRateTimer = Timer.periodic(const Duration(seconds: 15), (timer) async {
      if (_isPaused) return; // Don't update during pause
      
      final heartRate = await _healthService.getHeartRate();
      if (heartRate != null) {
        setState(() {
          _heartRate = heartRate;
        });
      }
    });
    
    // Fetch initial heart rate
    final initialHeartRate = await _healthService.getHeartRate();
    if (initialHeartRate != null) {
      setState(() {
        _heartRate = initialHeartRate;
      });
    }
  }

  /// Stop heart rate monitoring
  void _stopHeartRateMonitoring() {
    _heartRateTimer?.cancel();
    _heartRateTimer = null;
  }

  /// Get formatted weight string
  String _getDisplayWeight() {
    if (widget.preferMetric) {
      return '${widget.displayRuckWeight.toStringAsFixed(1)} kg';
    } else {
      return '${widget.displayRuckWeight.round()} lbs';
    }
  }

  // Method to load custom marker icon
  Future<void> _loadCustomMarker() async {
    try {
      final ByteData data = await rootBundle.load('assets/images/map marker.png');
      final Uint8List bytes = data.buffer.asUint8List();
      setState(() {
        _customMarkerIcon = bytes;
      });
    } catch (e) {
      AppLogger.error('Error loading custom marker: $e');
    }
  }

  void _stopLocationTracking() {
    AppLogger.info('Stopping location tracking...');
    _locationSubscription?.cancel();
    _locationSubscription = null;
    AppLogger.info('Location tracking stopped.');
  }

  /// Shows a confirmation dialog when user attempts to exit the active session
  Future<void> _showEndConfirmationDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('End Session?'),
        content: const Text(
          'Are you sure you want to end your ruck session? This will save your current progress.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('End Session'),
          ),
        ],
      ),
    );
    
    if (result == true) {
      _endSession();
    }
  }

  /// Show a dialog when the session appears to be idle for too long
  Future<void> _showIdleEndConfirmationDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Session Inactive'),
        content: const Text(
          'It looks like you haven\'t moved in a while. Would you like to end your session?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Continue Session'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('End Session'),
          ),
        ],
      ),
    );
    
    if (result == true) {
      _endSession();
    }
  }

  /// Calculate calories based on distance, duration, and weight
  double _calculateCalories() {
    // MET values (Metabolic Equivalent of Task):
    // - Walking with weighted backpack (10-20kg): ~7.0 MET
    // - Walking with very heavy backpack (>20kg): ~8.5 MET
    double metValue = widget.ruckWeight < 20 ? 7.0 : 8.5;
    
    // Calculate calories using the MetCalculator
    double durationMinutes = _elapsed.inSeconds / 60.0; // Convert seconds to minutes
    
    return MetCalculator.calculateCaloriesBurned(
      weightKg: widget.userWeight + widget.ruckWeight, // Total weight is user + ruck
      durationMinutes: durationMinutes,
      metValue: metValue,
    );
  }

  @override
  Widget build(BuildContext context) {
    AppLogger.info('ActiveSessionScreen.build: _heartRate=$_heartRate');
    // Format display values
    final String durationDisplay = _formatDuration(_elapsed);
    final String? distanceDisplay = _canShowStats
      ? MeasurementUtils.formatDistance(_distance, metric: widget.preferMetric)
      : null;
    
    // pace is stored as seconds per km; adjust display based on user preference
    double _displayPaceSec = _pace; // Base pace in seconds per km
    final String? paceDisplay = _canShowStats
      ? MeasurementUtils.formatPace(_displayPaceSec, metric: widget.preferMetric)
      : null;
    
    final String? caloriesDisplay = _canShowStats
      ? _caloriesBurned.toStringAsFixed(0)
      : null;
    final String elevationDisplay = _canShowStats
      ? MeasurementUtils.formatElevationCompact(_elevationGain, _elevationLoss, metric: widget.preferMetric)
      : '+0/-0';
    
    // Calculate remaining time if planned duration was set
    String? remainingTimeDisplay;
    if (widget.plannedDuration != null && _plannedCountdownStart != null) {
      final elapsedSeconds = _elapsed.inSeconds;
      final plannedSeconds = widget.plannedDuration! * 60;
      final remainingSeconds = plannedSeconds - elapsedSeconds;
      
      if (remainingSeconds > 0) {
        final remainingMinutes = (remainingSeconds / 60).floor();
        final secondsLeft = remainingSeconds % 60;
        remainingTimeDisplay = '$remainingMinutes:${secondsLeft.toString().padLeft(2, '0')}';
      } else {
        remainingTimeDisplay = 'Completed!';
      }
    }
    
    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.black : AppColors.backgroundLight,
      appBar: AppBar(
        title: Text('Active Session', style: AppTextStyles.headline6.copyWith(color: Colors.white)),
        backgroundColor: AppColors.primary,
        centerTitle: true,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _showEndConfirmationDialog,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              // Menu options
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Map section
          Expanded(
            flex: 2,
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _locationPoints.length >= 2
                    ? FlutterMap(
                        options: MapOptions(
                          initialCenter: _getRouteCenter(_locationPoints.map((p) => LatLng(p.latitude, p.longitude)).toList()),
                          initialZoom: _getFitZoom(_locationPoints.map((p) => LatLng(p.latitude, p.longitude)).toList()),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.rucking.app',
                          ),
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: _locationPoints
                                    .map((p) => LatLng(p.latitude, p.longitude))
                                    .toList(),
                                color: AppColors.primary,
                                strokeWidth: 4.0,
                              ),
                            ],
                          ),
                          MarkerLayer(
                            markers: [
                              if (_locationPoints.isNotEmpty)
                                Marker(
                                  point: LatLng(_locationPoints.first.latitude, _locationPoints.first.longitude),
                                  child: const Icon(Icons.location_on, color: Colors.blue, size: 25),
                                ),
                              if (_locationPoints.length > 1)
                                Marker(
                                  point: LatLng(_locationPoints.last.latitude, _locationPoints.last.longitude),
                                  child: _customMarkerIcon != null
                                      ? Image.memory(_customMarkerIcon!, width: 25, height: 25)
                                      : const Icon(
                                          Icons.location_on,
                                          color: Colors.green,
                                          size: 25,
                                        ),
                                ),
                            ],
                          ),
                        ],
                      )
                    : const Center(
                        child: Text(
                          'Start moving to see your route...',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
              ),
            ),
          ),
          
          // Validation message
          if (_showValidationMessage && _validationMessage != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _validationMessage!,
                      style: const TextStyle(color: Colors.deepOrange),
                    ),
                  ),
                ],
              ),
            ),
            
          // Timer and weight display
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Timer display
                Text(
                  durationDisplay,
                  style: AppTextStyles.headline1.copyWith(
                    fontWeight: FontWeight.bold,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Ruck weight
                    Text(
                      _getDisplayWeight(),
                      style: AppTextStyles.headline6.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                
                // Remaining time if planned duration
                if (widget.plannedDuration != null && remainingTimeDisplay != null)
                  Text(
                    'Remaining: $remainingTimeDisplay',
                    style: AppTextStyles.subtitle1.copyWith(
                      color: remainingTimeDisplay == 'Completed!' ? Colors.green : Colors.grey.shade600,
                    ),
                  ),
              ],
            ),
          ),
          
          // Stats section
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  // First row: Distance and Pace
                  Expanded(
                    child: Row(
                      children: [
                        // Distance card
                        Expanded(
                          child: Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.straighten, color: AppColors.primary, size: 20),
                                      SizedBox(width: 6),
                                      Text('Distance', style: AppTextStyles.subtitle2),
                                    ],
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    distanceDisplay != null
                                        ? distanceDisplay
                                        : '',
                                    style: AppTextStyles.headline5.copyWith(
                                      color: Theme.of(context).brightness == Brightness.dark 
                                          ? AppColors.primaryLight 
                                          : null,
                                    ),
                                  ),
                                  if (distanceDisplay == null)
                                    SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary)),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        // Pace card
                        Expanded(
                          child: Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.speed, color: AppColors.secondary, size: 20),
                                      SizedBox(width: 6),
                                      Text('Pace', style: AppTextStyles.subtitle2),
                                    ],
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    paceDisplay != null
                                        ? paceDisplay
                                        : '',
                                    style: AppTextStyles.headline5.copyWith(
                                      color: Theme.of(context).brightness == Brightness.dark 
                                          ? AppColors.success 
                                          : null,
                                    ),
                                  ),
                                  if (paceDisplay == null)
                                    SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(AppColors.success)),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Second row: Calories and Elevation
                  Expanded(
                    child: Row(
                      children: [
                        // Calories card
                        Expanded(
                          child: Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.local_fire_department, color: AppColors.success, size: 20),
                                      SizedBox(width: 6),
                                      Text('Calories', style: AppTextStyles.subtitle2),
                                    ],
                                  ),
                                  SizedBox(height: 8),
                                  caloriesDisplay != null
                                    ? Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            caloriesDisplay,
                                            style: AppTextStyles.headline5.copyWith(
                                              color: Theme.of(context).brightness == Brightness.dark 
                                                  ? AppColors.warning 
                                                  : null,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'kCal',
                                            style: AppTextStyles.headline5.copyWith(
                                              color: Theme.of(context).brightness == Brightness.dark 
                                                  ? AppColors.warning 
                                                  : null,
                                            ),
                                          ),
                                        ],
                                      )
                                    : SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(AppColors.success)),
                                      ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        // Elevation card
                        Expanded(
                          child: Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.terrain, color: AppColors.success, size: 20),
                                      SizedBox(width: 6),
                                      Text('Elevation', style: AppTextStyles.subtitle2),
                                    ],
                                  ),
                                  SizedBox(height: 8),
                                  elevationDisplay != '+0/-0'
                                    ? Text(
                                        elevationDisplay,
                                        style: AppTextStyles.headline5.copyWith(
                                          color: Theme.of(context).brightness == Brightness.dark 
                                              ? AppColors.primaryLight 
                                              : null,
                                        ),
                                      )
                                    : SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(AppColors.success)),
                                      ),
                                ],
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
          
          // Control buttons
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