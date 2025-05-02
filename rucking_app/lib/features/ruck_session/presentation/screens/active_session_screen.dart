import 'dart:async';
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
import 'package:rucking_app/core/services/watch_service.dart';

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
  late WatchService _watchService;
  
  // Session state
  bool _isPaused = false;
  bool _isEnding = false;
  String? _validationMessage;
  bool _showValidationMessage = false;
  bool _hasAppleWatch = true; // Track if user has Apple Watch
  bool _isSessionEnded = false; // New flag
  String? _ruckId; // Add variable to hold ruckId from args or widget
  Map<String, dynamic>? _initialSessionData; // Add variable to hold args
  
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

  // Variable to store heart rate message for user notification
  String _heartRateMessage = '';

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
    _watchService = GetIt.instance<WatchService>();
    
    // Check if user has an Apple Watch
    _checkHasAppleWatch();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Get arguments passed via navigation if _initialSessionData is null
    if (_initialSessionData == null) {
      final arguments = ModalRoute.of(context)?.settings.arguments;
      if (arguments != null && arguments is Map<String, dynamic>) {
        _initialSessionData = arguments;
        // Extract needed data from arguments
        // The actual ruckId from the backend response might be under 'id' or 'ruck_id'
        _ruckId = _initialSessionData!['id'] as String? ?? _initialSessionData!['ruck_id'] as String?;
        debugPrint('Received session data from arguments: $_initialSessionData');
        debugPrint('Extracted ruckId from arguments: $_ruckId');
      }
    }

    // Ensure ruckId is set either from arguments or widget
    _ruckId ??= widget.ruckId;
    debugPrint('Final ruckId for session: $_ruckId');

    // --- Initialization that DEPENDS on arguments/widget props ---
    // This part needs to run *after* arguments are potentially processed
    _loadDataAndStartSession();
  }

  // New method to contain logic previously in initState that depends on props/args
  void _loadDataAndStartSession() {
    // Get user preference and weight
    final authState = context.read<AuthBloc>().state;
    if (authState is Authenticated) {
      _preferMetric = authState.user.preferMetric;
      // Prioritize argument/state value if available, else use widget prop
      _userWeightKg = authState.user.weightKg ?? widget.userWeight;
    } else {
      _userWeightKg = widget.userWeight;
    }
    // Prioritize argument/state value if available, else use widget prop
    // Use the ruckWeight passed via constructor as WatchService doesn't include it in API response
    ruckWeightKg = widget.ruckWeight; 
    // Potentially extract from _initialSessionData if API response includes it:
    // ruckWeightKg = _initialSessionData?['ruck_weight_kg'] as double? ?? widget.ruckWeight;

    // Initialize stopwatch
    _stopwatch = Stopwatch();

    // Start map/location tracking
    _initLocationTracking();

    // Initialize stats
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

    // Initialize session weights for BLoC using the determined ruckId
    _initializeSessionWeights();
    _startSession(); // Start the timers and stopwatch

    // Set planned countdown if provided (use widget prop here)
    // Check _initialSessionData if watch can send planned duration
    int? plannedDurationMinutes = _initialSessionData?['planned_duration_minutes'] as int? ?? widget.plannedDuration;
    if (plannedDurationMinutes != null && plannedDurationMinutes > 0) {
      _plannedCountdownStart = Duration(minutes: plannedDurationMinutes);
    }

    // Load custom marker icon
    _loadCustomMarker();
  }

  void _initializeSessionWeights() {
    if (_ruckId == null) {
      debugPrint("Error: Ruck ID is null, cannot initialize session weights in BLoC.");
      _showErrorSnackBar("Failed to initialize session: Missing Ruck ID.");
      // Optionally navigate back or handle error
      // Navigator.of(context).pop(); 
      return;
    }
    // Start session in BLoC with weights
    context.read<ActiveSessionBloc>().add(
      SessionStarted(
        ruckId: _ruckId!, // Use the state variable _ruckId
        userWeightKg: _userWeightKg,
        ruckWeightKg: ruckWeightKg,
      ),
    );
    debugPrint('Session weights initialized in BLoC for ruckId: $_ruckId');
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _heartRateTimer?.cancel();
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
      debugPrint('Starting location tracking...');
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
          print('Location error: $error');
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
        debugPrint('Failed to get initial location: $e');
      }
      debugPrint('Location tracking started successfully.');
    } catch (e) {
      debugPrint('Error starting location tracking: $e');
    }
  }
  
  /// Handle incoming location updates
  void _handleLocationUpdate(LocationPoint locationPoint) {
    if (_isSessionEnded) {
      debugPrint('Session ended. Ignoring location update.');
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
      
      // Calculate pace (min/km) - time taken for this segment / distance in km
      double segmentPace = 0.0;
      if (distanceMeters > 0) {
        segmentPace = (DateTime.now().difference(previousPoint.timestamp).inSeconds) / (distanceMeters / 1000);
        _recentPaces.add(segmentPace);
        // Keep only the most recent 30 paces for initial trimming
        if (_recentPaces.length > 30) {
          _recentPaces.removeAt(0);
        }
        
        // Step 1: trimmed-mean to reduce outliers
        final double trimmedPace =
            _validationService.getSmoothedPace(segmentPace, _recentPaces);
        
        // Step 2: exponential moving average for smooth yet responsive update
        if (_pace == 0) {
          _pace = trimmedPace;
        } else {
          _pace = _pace * (1 - _paceAlpha) + trimmedPace * _paceAlpha;
        }
      }
      
      // Calculate MET value using the correct method
      final double speedKmh = segmentPace > 0 ? 3600 / segmentPace : 0.0;
      final double speedMph = MetCalculator.kmhToMph(speedKmh);
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
      debugPrint('Sending location update payload: $payload');
      await _apiClient.post(
        '/rucks/${widget.ruckId}/location',
        payload,
      ).catchError((e) {
        debugPrint('Failed to send location update: $e');
        return; // Ensure a return even in error case
      });
    } catch (e) {
      debugPrint('Error in _sendLocationUpdate: $e');
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
      _showErrorSnackBar(sessionLocationPermissionDenied);
      return;
    }
    
    // Start location tracking (extracted helper)
    await _initLocationTracking();
    
    try {
      await _apiClient.put('/rucks/${widget.ruckId}/start', {});
    } catch (e) {
      print('Failed to start session: $e');
      
      // Handle unauthorized errors specifically
      if (e is UnauthorizedException) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(serverUnauthorized),
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
        // Log non-critical error without showing an error message
        debugPrint('Non-critical error on session start: $e');
      }
    }
    
    // Listen for real-time heart rate updates from WatchService
    _watchService.onHeartRateUpdate.listen((heartRateData) {
      if (mounted && !_isPaused) {
        debugPrint('Real-time heart rate update from Watch: $heartRateData bpm');
        debugPrint('Debug: Watch update received - confirm WCSession data: $heartRateData');
        setState(() {
          _heartRate = heartRateData['heartRate'] as double? ?? _heartRate;
        });
      }
    });
  }
  
  /// Updates the elapsed time display
  void _updateTime(Timer timer) {
    if (!mounted) return;
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
            .catchError((e) => print('Failed to resume session: $e'));
        // Notify Watch
        if (_hasAppleWatch) {
          _watchService.resumeSessionOnWatch();
        }
      } else {
        _stopwatch.stop();
        _isPaused = true;
        // Pause location tracking
        _locationSubscription?.pause();
        // Notify API
        _apiClient.post('/rucks/${widget.ruckId}/pause', {})
            .catchError((e) => print('Failed to pause session: $e'));
        // Notify Watch
        if (_hasAppleWatch) {
          _watchService.pauseSessionOnWatch();
        }
      }
    });
  }
  
  /// Ends the current session
  Future<void> _endSession() async {
    debugPrint('Ending session...');
    _isSessionEnded = true; // Set flag
    // Stop tracking before processing end of session
    _stopwatch.stop();
    _timer?.cancel();
    _stopLocationTracking(); // Explicitly stop location tracking
    debugPrint('Timers and location tracking stopped for session end.');

    // Notify Watch
    if (_hasAppleWatch) {
      _watchService.endSessionOnWatch();
    }
    
    // Check if we have a valid session to save
    if (_locationPoints.isEmpty || _distance < 0.05) {
      debugPrint('Session too short to save: distance $_distance km');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(sessionTooShortError.replaceAll('{minutes}', '3')), backgroundColor: Colors.red),
        );
        Navigator.of(context).pop();
      }
      return;
    }

    // Capture end-session timestamp
    final DateTime completedAt = DateTime.now();
    
    try {
      // Get final session distance
      final distanceMeters = _distance * 1000; // Convert km to meters
      
      // Validate session before saving - ensure at least 3 minutes of activity
      final Duration minDuration = Duration(minutes: 3);
      bool isValid = _elapsed.inSeconds >= minDuration.inSeconds;
      
      if (!isValid) {
        // Remove the session from backend if it's too short or invalid
        try {
          await _apiClient.delete('/rucks/${widget.ruckId}');
          debugPrint('Deleted short session ${widget.ruckId} from backend');
        } catch (e) {
          debugPrint('Failed to delete short session: $e');
        }
        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(sessionTooShortError.replaceAll('{minutes}', '3')),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.pop(context);
        return;
      }
      
      // Create route coordinates string for API
      List<Map<String, dynamic>> routeCoordinates = [];
      
      // Use only valid location points that met our criteria
      if (_locationPoints.isNotEmpty) {
        for (final point in _locationPoints) {
          routeCoordinates.add({
            'latitude': point.latitude,
            'longitude': point.longitude,
            'elevation': point.elevation,
            'timestamp': point.timestamp.toIso8601String(),
          });
        }
      }
      
      // Determine user's unit preference
      final authState = context.read<AuthBloc>().state;
      final bool preferMetric = authState is Authenticated ? authState.user.preferMetric : true;

      // Write data to Apple Health if available and enabled in app config
      if (AppConfig.enableHealthSync) {
        try {
          // Get the last heart rate reading if available
          final heartRateReading = (_heartRate != null && _heartRate! > 0) ? _heartRate : null;
          
          // Convert weight from pounds to kg if needed
          double? ruckWeightKg;
          if (widget.ruckWeight != null && widget.ruckWeight! > 0) {
            ruckWeightKg = preferMetric ? widget.ruckWeight : widget.ruckWeight! * 0.453592;
          }
          
          // End time is now, start time is calculated by subtracting elapsed time
          final endTime = DateTime.now();
          final startTime = endTime.subtract(Duration(seconds: _elapsed.inSeconds));
          
          // Save as a complete workout with all metadata
          context.read<HealthBloc>().add(SaveRuckWorkout(
            distanceMeters: distanceMeters,
            caloriesBurned: _caloriesBurned,
            startTime: startTime,
            endTime: endTime,
            ruckWeightKg: ruckWeightKg,
            elevationGainMeters: _elevationGain,
            elevationLossMeters: _elevationLoss,
            heartRate: heartRateReading,
          ));
          
          // For backwards compatibility, also write as individual health records
          context.read<HealthBloc>().add(WriteHealthData(
            distanceMeters: distanceMeters,
            caloriesBurned: _caloriesBurned,
            startTime: startTime,
            endTime: endTime,
          ));
        } catch (e) {
          // Log error but don't block session completion
          debugPrint('Failed to write to Apple Health: $e');
        }
      }
      
      // Navigate to completion screen, passing final calculated stats
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => SessionCompleteScreen(
            completedAt: completedAt,
            ruckId: widget.ruckId,
            duration: _elapsed, // Pass final elapsed time
            distance: _distance, // Pass final calculated distance
            caloriesBurned: _caloriesBurned.round(), // Pass final calculated calories
            elevationGain: _elevationGain,
            elevationLoss: _elevationLoss,
            ruckWeight: widget.ruckWeight, // Pass numeric value instead of formatted string
            // Pass initial notes if available, SessionCompleteScreen allows editing
            initialNotes: widget.notes, 
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error in _endSession: $e');
    }
  }
  
  /// Shows a confirmation dialog for ending the session
  void _showEndConfirmationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          title: const Text('End Session'),
          content: Text(
            'Are you sure you want to end this session?',
            style: TextStyle(
              color: isDark ? Colors.black : null,
            ),
          ),
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
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
            ),
          ],
        );
      },
    );
  }

  /// Shows a confirmation dialog for ending session due to idle time
  void _showIdleEndConfirmationDialog() {
    if (_isEnding) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).dialogBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'NO ACTIVITY DETECTED',
                style: AppTextStyles.headline6.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                "You've been idle for over 2 minutes. Would you like to end this session?",
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      if (_isPaused) _togglePause();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.secondary,
                      textStyle: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    child: const Text('CONTINUE SESSION'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _endSession();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                      textStyle: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    child: const Text('END SESSION'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
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
  Future<void> _startHeartRateMonitoring() async {
    debugPrint('Starting heart rate monitoring...');
    // Request initial heart rate
    final initialHeartRate = await _healthService.getCurrentHeartRate();
    if (!mounted) return;
    if (initialHeartRate != null) {
      debugPrint('Initial heart rate received: $initialHeartRate bpm');
      setState(() {
        _heartRate = initialHeartRate;
      });
    } else {
      debugPrint('No heart rate data received; using fallback value 70 bpm');
      debugPrint('Debug: Check HealthKit permissions or recent data availability.');
      debugPrint('Debug: Heart rate is null - HealthKit may lack recent data or permissions are denied.');
      setState(() {
        _heartRate = 70;
        _heartRateMessage = 'No recent heart rate data available. Please ensure your Apple Watch is active and Health permissions are granted.';
      });
      // Show a snackbar to inform the user
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_heartRateMessage),
              duration: Duration(seconds: 5),
            ),
          );
        }
      });
    }

    // Start a periodic timer to poll heart rate every 15 seconds
    _heartRateTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (!mounted) return;
      if (_isPaused) return; // Skip update if session is paused
      debugPrint('Polling for heart rate update...');
      final heartRate = await _healthService.getCurrentHeartRate();
      if (!mounted) return;
      if (heartRate != null) {
        debugPrint('Heart rate updated: $heartRate bpm');
        setState(() {
          _heartRate = heartRate;
        });
      } else {
        debugPrint('No heart rate data received on poll; using fallback value 70 bpm');
        debugPrint('Debug: Polling failed - ensure HealthKit data or permissions.');
        debugPrint('Debug: Heart rate is null on poll - no recent data in last 5 minutes or permission issue.');
        setState(() {
          _heartRate = 70;
        });
      }
    });
    debugPrint('Heart rate timer started with 15-second interval.');
  }

  /// Stop heart rate monitoring
  void _stopHeartRateMonitoring() {
    _heartRateTimer?.cancel();
    _heartRateTimer = null;
  }

  /// Check if user has an Apple Watch
  void _checkHasAppleWatch() async {
    final hasWatch = await _healthService.hasAppleWatch();
    setState(() {
      _hasAppleWatch = hasWatch;
    });
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
      debugPrint('Error loading custom marker: $e');
    }
  }

  void _stopLocationTracking() {
    debugPrint('Stopping location tracking...');
    _locationSubscription?.cancel();
    _locationSubscription = null;
    debugPrint('Location tracking stopped.');
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('ActiveSessionScreen.build: _heartRate=$_heartRate');
    return BlocBuilder<ActiveSessionBloc, ActiveSessionState>(
      builder: (context, state) {
        if (state is ActiveSessionError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Error: ${state.message}', style: TextStyle(color: Colors.red, fontSize: 18)),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Go Back'),
                  ),
                ],
              ),
            ),
          );
        } else if (state is ActiveSessionInProgress || state is ActiveSessionPaused) {
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
            body: BlocListener<ActiveSessionBloc, ActiveSessionState>(
              listener: (context, state) {
                if (state is ActiveSessionCompleted) {
                  print("[ActiveSessionScreen] Detected ActiveSessionCompleted state. Navigating...");
                  // Navigate to the session summary screen, clearing the stack
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/sessionComplete', // Ensure this route is defined in your main router
                    (route) => false, // Remove all previous routes
                    arguments: state, // Pass the completed state which contains final metrics
                  );
                } else if (state is ActiveSessionError) {
                  // Optional: Show a snackbar or dialog for errors
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Session Error: ${state.message}')),
                  );
                }
              },
              child: Column(
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
                            
                            // Heart rate pill (only shown if user has an Apple Watch)
                            if (_hasAppleWatch)
                              Container(
                                margin: const EdgeInsets.only(left: 16),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).brightness == Brightness.dark 
                                    ? Colors.black 
                                    : Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                  border: Border.all(
                                    color: Theme.of(context).brightness == Brightness.dark 
                                      ? Colors.grey[800]! 
                                      : Colors.grey[300]!,
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.favorite,
                                      color: Colors.red[400],
                                      size: 24,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _heartRate != null ? '${_heartRate!.toInt()}' : '--',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                        color: Theme.of(context).brightness == Brightness.dark 
                                          ? Colors.white
                                          : Colors.black,
                                      ),
                                    ),
                                  ],
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
                  // Add heart rate display below the metrics container
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Heart Rate: ${_heartRate != null ? _heartRate.toString() + " bpm" : "--"}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
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
            ),
          );
        } else {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Initializing Session...'),
                ],
              ),
            ),
          );
        }
      },
    );
  }
}