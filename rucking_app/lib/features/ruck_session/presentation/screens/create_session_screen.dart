import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:keyboard_actions/keyboard_actions.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:provider/provider.dart';
import 'package:rucking_app/core/config/app_config.dart';
import 'package:rucking_app/core/services/connectivity_service.dart';
import 'package:rucking_app/core/services/battery_optimization_service.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/active_session_page.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/countdown_page.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/instant_start_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/location_service.dart';
import 'package:rucking_app/features/health_integration/domain/health_service.dart';
import 'package:rucking_app/shared/widgets/custom_text_field.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/styled_snackbar.dart';
import 'package:rucking_app/core/error_messages.dart';
import 'package:flutter/services.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_session.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/session_complete_screen.dart';
import 'package:rucking_app/features/ruck_session/data/repositories/session_repository.dart';
import 'package:latlong2/latlong.dart' as latlong;
import '../widgets/active_session_dialog.dart';
import 'package:rucking_app/features/coaching/presentation/widgets/plan_session_recommendations.dart';
import 'package:rucking_app/features/coaching/presentation/widgets/ai_coaching_session_widget.dart';
import 'package:rucking_app/features/coaching/data/services/coaching_service.dart';

/// Screen for creating a new ruck session
class CreateSessionScreen extends StatefulWidget {
  final String? eventId;
  final String? eventTitle;
  final String? routeId;
  final String? routeName;
  final dynamic routeData;
  final String? plannedRuckId;

  const CreateSessionScreen({
    Key? key,
    this.eventId,
    this.eventTitle,
    this.routeId,
    this.routeName,
    this.routeData,
    this.plannedRuckId,
  }) : super(key: key);

  @override
  _CreateSessionScreenState createState() => _CreateSessionScreenState();
}

class _CreateSessionScreenState extends State<CreateSessionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _userWeightController = TextEditingController();
  final _durationController = TextEditingController();
  final FocusNode _durationFocusNode = FocusNode();

  final ScrollController _weightScrollController = ScrollController();

  double _ruckWeight = AppConfig.defaultRuckWeight;
  double _displayRuckWeight =
      0.0; // Will be set in kg or lbs based on preference
  int? _plannedDuration; // Default is now empty
  bool _preferMetric = false; // Default to standard

  // Controller and flag for custom ruck weight input
  final TextEditingController _customRuckWeightController =
      TextEditingController();
  bool _showCustomRuckWeightInput = false;

  // Add loading state variable
  bool _isCreating = false;
  bool _isLoading = true;
  double _selectedRuckWeight = 0.0;

  // Event context state variables
  String? _eventId;
  String? _eventTitle;

  late final VoidCallback _durationListener;

  bool _isOfflineMode = false;
  bool _allowLiveFollowing = true; // Default to enabled

  // Coaching plan data
  Map<String, dynamic>? _coachingPlan;
  Map<String, dynamic>? _nextSession;
  Map<String, dynamic>? _coachingProgress;
  final TextEditingController _offlineDurationMinutesController =
      TextEditingController();
  final TextEditingController _offlineDurationSecondsController =
      TextEditingController();
  final TextEditingController _offlineDistanceController =
      TextEditingController();
  final TextEditingController _offlineElevationGainController =
      TextEditingController();
  final TextEditingController _offlineElevationLossController =
      TextEditingController();

  // AI Cheerleader state variables
  bool _aiCheerleaderEnabled = true; // Default to enabled
  String _aiCheerleaderPersonality = 'Drill Sergeant'; // Best performing personality
  bool _aiCheerleaderExplicitContent = true; // Users prefer authentic voice

  /// Loads preferences and last used values (ruck weight and duration)
  Future<void> _loadDefaults() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      // Do not override _preferMetric if it will be set by AuthBloc
      if (!(context.read<AuthBloc>().state is Authenticated)) {
        _preferMetric = prefs.getBool('preferMetric') ?? false;
      }

      // Load last used weight (KG)
      double lastWeightKg =
          prefs.getDouble('lastRuckWeightKg') ?? AppConfig.defaultRuckWeight;
      _ruckWeight = lastWeightKg;
      _selectedRuckWeight =
          lastWeightKg; // Ensure selectedRuckWeight is synced with ruckWeight

      // Update display weight based on preference
      if (_preferMetric) {
        _displayRuckWeight = _ruckWeight;
      } else {
        _displayRuckWeight = _ruckWeight * AppConfig.kgToLbs;
      }

      // Load coaching plan data for recommendations
      await _loadCoachingPlanData();

      // Load last used duration (might be null if not previously set)
      int? lastDurationMinutes = prefs.getInt('lastSessionDurationMinutes');
      _plannedDuration = lastDurationMinutes;
      if (lastDurationMinutes != null) {
        _durationController.text = lastDurationMinutes.toString();
      }

      // Load user's body weight (if previously saved)
      String? lastUserWeight = prefs.getString('lastUserWeight');
      if (lastUserWeight != null && lastUserWeight.isNotEmpty) {
        _userWeightController.text = lastUserWeight;
      }

      // Load AI Cheerleader preferences (default to true for new users)
      _aiCheerleaderEnabled = prefs.getBool('aiCheerleaderEnabled') ?? true;

      // Validate saved personality exists in current options
      final savedPersonality =
          prefs.getString('aiCheerleaderPersonality') ?? 'Drill Sergeant';
      const availablePersonalities = [
        'Supportive Friend',
        'Drill Sergeant',
        'Southern Redneck',
        'Yoga Instructor',
        'British Butler',
        'Sports Commentator',
        'Cowboy/Cowgirl',
        'Nature Lover',
        'Burt Reynolds',
        'Tom Selleck'
      ];

      _aiCheerleaderPersonality =
          availablePersonalities.contains(savedPersonality)
              ? savedPersonality
              : availablePersonalities[
                  Random().nextInt(availablePersonalities.length)];

      _aiCheerleaderExplicitContent =
          prefs.getBool('aiCheerleaderExplicitContent') ?? true;
    } catch (e) {
      // Fallback to defaults on error
      _ruckWeight = AppConfig.defaultRuckWeight;
      _durationController.text = '30'; // Default duration on error
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      // Make sure we trigger a UI update with the loaded weights
      Future.delayed(Duration.zero, () {
        if (mounted) {
          setState(() {
            // Force synchronization
            _selectedRuckWeight = _ruckWeight;
          });
        }
      });
    }
  }

  /// Saves the last used ruck weight to SharedPreferences
  Future<void> _saveLastWeight(double weightKg) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('lastRuckWeightKg', weightKg);
  }

  /// Load coaching plan data for session recommendations
  Future<void> _loadCoachingPlanData() async {
    try {
      final coachingService = GetIt.instance<CoachingService>();

      final plan = await coachingService.getActiveCoachingPlan();

      // Explicitly check for null or empty plan
      if (plan != null && plan.isNotEmpty) {
        _coachingPlan = Map<String, dynamic>.from(plan);

        final progressResponse =
            await coachingService.getCoachingPlanProgress();
        final progress = progressResponse['progress'] is Map
            ? Map<String, dynamic>.from(progressResponse['progress'])
            : null;
        final nextSession = progressResponse['next_session'] is Map
            ? Map<String, dynamic>.from(progressResponse['next_session'])
            : null;

        _coachingProgress = progress;

        if (nextSession != null) {
          _nextSession = nextSession;
        }

        if (_coachingProgress != null) {
          _coachingPlan!['progress'] = _coachingProgress;
          _coachingPlan!['adherence_percentage'] ??=
              _coachingProgress!['adherence_percentage'];
          _coachingPlan!['is_on_track'] ??= _coachingProgress!['is_on_track'];
        }
        if (_nextSession != null) {
          _coachingPlan!['next_session'] = _nextSession;
        }
      } else {
        // Ensure coaching plan is null when no plan exists
        _coachingPlan = null;
        _nextSession = null;
        _coachingProgress = null;
      }
    } catch (e) {
      AppLogger.info(
          '[CREATE_SESSION] No active coaching plan or error loading: $e');
      // Ensure coaching plan is null on error
      _coachingPlan = null;
      _nextSession = null;
      _coachingProgress = null;
    }
  }

  /// Apply coaching plan recommended settings to the session
  void _applyCoachingRecommendations() {
    if (_nextSession == null) return;

    setState(() {
      // Apply recommended weight
      if (_nextSession!['weight_kg'] != null) {
        final recommendedWeightKg = (_nextSession!['weight_kg'] as double);
        _ruckWeight = recommendedWeightKg;
        _selectedRuckWeight = recommendedWeightKg;

        // Update display weight based on preference
        if (_preferMetric) {
          _displayRuckWeight = recommendedWeightKg;
        } else {
          _displayRuckWeight = recommendedWeightKg * AppConfig.kgToLbs;
        }
      }

      // Apply recommended duration
      if (_nextSession!['duration_minutes'] != null) {
        _plannedDuration = _nextSession!['duration_minutes'] as int;
        _durationController.text = _plannedDuration.toString();
      }
    });

    // Show confirmation
    StyledSnackBar.show(
      context: context,
      message: 'Applied coaching plan recommendations',
      type: SnackBarType.success,
    );
  }

  /// Saves the last used session duration to SharedPreferences
  Future<void> _saveLastDuration(int durationMinutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('lastSessionDurationMinutes', durationMinutes);
  }

  /// Saves the user's body weight to SharedPreferences
  Future<void> _saveUserWeight(String weight) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastUserWeight', weight);
  }

  /// Creates and starts a new ruck session
  void _createSession() async {
    if (_formKey.currentState!.validate()) {
      String? ruckId; // Declare ruckId variable at function scope
      final authState = context.read<AuthBloc>().state;
      if (authState is! Authenticated) {
        StyledSnackBar.showError(
          context: context,
          message: 'You must be logged in to create a session',
          duration: const Duration(seconds: 3),
        );
        // Navigate to login screen after a brief delay
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (!mounted) return;
          Navigator.of(context).pushNamed('/login');
        });
        return;
      }

      // Check location permissions BEFORE starting session creation
      try {
        final locationService = GetIt.instance<LocationService>();
        bool hasPermission = await locationService.hasLocationPermission();

        if (!hasPermission) {
          // Try to request permission with context for disclosure dialog
          hasPermission =
              await locationService.requestLocationPermission(context: context);
        }

        if (!hasPermission) {
          if (!mounted) return;
          StyledSnackBar.showError(
            context: context,
            message:
                'Location permission is required for ruck tracking. Please enable location access in Settings.',
            duration: const Duration(seconds: 5),
          );
          if (mounted) {
            setState(() {
              _isCreating = false;
            });
          }
          return;
        }

        AppLogger.info('Location permissions verified before session creation');

        // Check health permissions early to prevent permission pop-ups during session
        final healthService = GetIt.instance<HealthService>();
        try {
          // Check if health integration is available on this device
          bool isHealthAvailable = await healthService.isHealthDataAvailable();
          if (isHealthAvailable) {
            AppLogger.info('Health data available, requesting permissions...');

            // Request health permissions now instead of during session
            bool healthAuthorized = await healthService.requestAuthorization();
            if (!healthAuthorized) {
              AppLogger.warning(
                  'Health permissions denied, continuing without health integration');
              // Don't block session creation, just warn the user
              if (mounted) {
                StyledSnackBar.showError(
                  context: context,
                  message:
                      'Health permissions denied. Heart rate monitoring will be unavailable.',
                  duration: const Duration(seconds: 3),
                );
              }
            } else {
              AppLogger.info('Health permissions granted');
            }
          } else {
            AppLogger.info('Health data not available on this device');
          }
        } catch (e) {
          AppLogger.warning('Failed to check health permissions: $e');
          // Don't block session creation if health check fails
        }

        // Check battery optimization status for Android background location
        if (!mounted) return;
        if (Theme.of(context).platform == TargetPlatform.android) {
          try {
            // Use the proper modal dialog to explain and request battery optimization permissions
            final batteryOptimizationGranted = await BatteryOptimizationService
                .ensureBackgroundExecutionPermissions(context: context);

            if (!batteryOptimizationGranted) {
              AppLogger.info(
                  'Battery optimization permissions not granted, continuing anyway');
              // Don't block session creation - just log the status
            } else {
              AppLogger.info('Battery optimization permissions granted');
            }
          } catch (e) {
            AppLogger.warning('Failed to check battery optimization: $e');
            // Don't block session creation if this check fails
          }
        }
      } catch (e) {
        AppLogger.error('Failed to check location permissions', exception: e);
        if (mounted) {
          StyledSnackBar.showError(
            context: context,
            message:
                'Unable to verify location permissions. Please check your device settings.',
            duration: const Duration(seconds: 4),
          );
          setState(() {
            _isCreating = false;
          });
        }
        return;
      }
      // Set loading state immediately
      if (!mounted) return;
      setState(() {
        _isCreating = true;
      });

      try {
        // Weight is stored internally in KG
        // Double check the conversion for standard (imperial) weights is correct
        double weightForApiKg = _ruckWeight;

        // Debug log the exact weight being saved
        AppLogger.debug(
            'Creating session with ruck weight: ${weightForApiKg.toStringAsFixed(2)} kg');
        AppLogger.debug(
            'Original selection was: ${_displayRuckWeight} ${_preferMetric ? "kg" : "lbs"}');

        // Prepare request data for creation
        Map<String, dynamic> createRequestData = {
          'ruck_weight_kg': weightForApiKg,
          'is_manual': false, // Regular active sessions are not manual
          'allow_live_following': _allowLiveFollowing,
        };

        // Add event context if creating session for an event
        if (_eventId != null) {
          createRequestData['event_id'] = _eventId;
          createRequestData['session_type'] = 'event_ruck';
        }

        // Add route context if creating session from a planned route
        if (widget.routeId != null) {
          createRequestData['route_id'] = widget.routeId;
          createRequestData['session_type'] = 'route_ruck';
          if (widget.plannedRuckId != null) {
            createRequestData['planned_ruck_id'] = widget.plannedRuckId;
          }
        }

        // Add user's weight (required)
        final userWeightRaw = _userWeightController.text;
        if (userWeightRaw.isEmpty) {
          throw Exception(
              sessionUserWeightRequired); // Use centralized error message
        }
        double userWeightKg = _preferMetric
            ? double.parse(userWeightRaw)
            : double.parse(userWeightRaw) / 2.20462; // Convert lbs to kg
        createRequestData['weight_kg'] = userWeightKg;

        // --- Ensure planned duration is included ---
        if (_plannedDuration != null && _plannedDuration! > 0) {
          createRequestData['planned_duration_minutes'] = _plannedDuration;
        }
        // --- End planned duration addition ---

        // --- Add user_id for Supabase RLS ---
        createRequestData['user_id'] = authState.user.userId;
        // --- End user_id ---

        // ---- Step 1: Create session in the backend ----

        final apiClient = GetIt.instance<ApiClient>();

        // Try to create online session first, but handle active sessions
        try {
          AppLogger.info('Attempting to create online session...');
          final createResponse = await apiClient
              .post('/rucks', createRequestData)
              .timeout(Duration(
                  seconds: 30)); // Increased from 10s for better reliability

          if (!mounted) return;

          // Check if response indicates an active session exists
          if (createResponse != null &&
              createResponse['has_active_session'] == true) {
            // Show dialog to handle existing active session
            setState(() {
              _isCreating = false;
            });

            final choice = await showDialog<String>(
              context: context,
              barrierDismissible: false,
              builder: (context) => ActiveSessionDialog(
                activeSession: createResponse,
                onContinueExisting: () => Navigator.of(context).pop('continue'),
                onCancel: () => Navigator.of(context).pop('cancel'),
              ),
            );

            if (choice == 'cancel' || !mounted) {
              return;
            } else if (choice == 'continue') {
              // Continue with existing session - navigate to active session
              ruckId = createResponse['id'].toString();
              AppLogger.info('🔄 Continuing existing session: $ruckId');
              // Removed force_new option - users must complete or continue existing sessions
            }
          } else {
            // Normal session creation
            if (createResponse == null || createResponse['id'] == null) {
              throw Exception(
                  'Invalid response from server when creating session');
            }

            ruckId = createResponse['id'].toString();
            AppLogger.info('✅ Created online session: $ruckId');
          }
        } catch (e) {
          // Any error (network, timeout, etc.) immediately goes to offline mode
          AppLogger.warning(
              'Failed to create online session, proceeding offline: $e');

          // Create offline session ID
          ruckId = 'offline_${DateTime.now().millisecondsSinceEpoch}';
          AppLogger.info('🔄 Created offline session: $ruckId');
        }

        // Save the used weight (always in KG) to SharedPreferences on success
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('lastRuckWeightKg', weightForApiKg);

        // Save the user's entered body weight
        _saveUserWeight(_userWeightController.text);

        // Save duration if entered
        if (_durationController.text.isNotEmpty) {
          int duration = int.parse(_durationController.text);
          _plannedDuration = duration;
          await _saveLastDuration(duration);
        }

        // Perform session preparation/validation without resetting _ruckWeight or _displayRuckWeight
        // Log current state for debugging

        // Delay and then navigate without resetting chip state
        await Future.delayed(Duration(milliseconds: 500));
        // Convert planned duration (minutes) to seconds; null means no planned duration
        final int? plannedDuration =
            _plannedDuration != null ? _plannedDuration! * 60 : null;

        // Parse route data if available
        List<latlong.LatLng>? plannedRoute;
        double? plannedRouteDistance;
        int? plannedRouteDuration;

        if (widget.routeData != null) {
          try {
            AppLogger.info('Route data received: ${widget.routeData}');

            // Parse route polyline into LatLng points
            if (widget.routeData['route_polyline'] != null) {
              final polylineString =
                  widget.routeData['route_polyline'] as String;
              AppLogger.info('Route polyline string: $polylineString');
              AppLogger.info(
                  'Polyline string length: ${polylineString.length}');

              plannedRoute = _parsePolylineToLatLng(polylineString);
              AppLogger.info(
                  'Parsed ${plannedRoute.length} route points for session navigation');

              if (plannedRoute.isNotEmpty) {
                AppLogger.info('First route point: ${plannedRoute.first}');
                AppLogger.info('Last route point: ${plannedRoute.last}');
              } else {
                AppLogger.warning('No route points parsed from polyline!');
              }
            } else {
              AppLogger.warning('Route polyline is null in routeData!');
            }

            // Extract route distance (in km)
            if (widget.routeData['distance_km'] != null) {
              plannedRouteDistance =
                  (widget.routeData['distance_km'] as num).toDouble();
              AppLogger.info('Route distance: ${plannedRouteDistance}km');
            }

            // Extract estimated duration (in minutes)
            if (widget.routeData['estimated_duration_minutes'] != null) {
              plannedRouteDuration =
                  (widget.routeData['estimated_duration_minutes'] as num)
                      .toInt();
              AppLogger.info(
                  'Estimated route duration: ${plannedRouteDuration} minutes');
            }
          } catch (e) {
            AppLogger.warning('Failed to parse route data for session: $e');
          }
        }

        // Create session args that will be passed to both CountdownPage and later to ActiveSessionPage
        AppLogger.info('🚀 [CREATE_SESSION] Creating session args:');
        AppLogger.info(
            '🚀 [CREATE_SESSION]   plannedRoute length: ${plannedRoute?.length ?? 0}');
        AppLogger.info(
            '🚀 [CREATE_SESSION]   plannedRouteDistance: $plannedRouteDistance');
        AppLogger.info(
            '🚀 [CREATE_SESSION]   plannedRouteDuration: $plannedRouteDuration');

        debugPrint(
            '🚀🚀🚀 [CREATE_SESSION DEBUG] About to create ActiveSessionArgs with planned route:');
        debugPrint('🚀🚀🚀 Route points: ${plannedRoute?.length ?? 0} points');
        debugPrint('🚀🚀🚀 Route distance: $plannedRouteDistance');
        debugPrint('🚀🚀🚀 Route duration: $plannedRouteDuration');

        // Debug: Log first few route points if available
        if (plannedRoute != null && plannedRoute!.isNotEmpty) {
          AppLogger.info('  First route point: ${plannedRoute!.first}');
          if (plannedRoute!.length > 1) {
            AppLogger.info('  Last route point: ${plannedRoute!.last}');
          }
        } else {
          AppLogger.warning('  No planned route points available!');
        }

        AppLogger.sessionCompletion('Creating session with event context',
            context: {
              'event_id': _eventId,
              'event_title': _eventTitle,
              'ruck_weight_kg': _ruckWeight,
              'planned_duration_seconds': plannedDuration,
            });

        // Session was already created earlier in the function - ruckId should be set
        if (ruckId == null) {
          throw Exception('Session ID was not created properly');
        }
        AppLogger.error(
            '[CREATE_SESSION] 🔥 USING EXISTING SESSION ID: $ruckId');

        final sessionArgs = ActiveSessionArgs(
          ruckWeight: _ruckWeight,
          userWeightKg:
              userWeightKg, // Pass the calculated userWeightKg (double)
          notes:
              null, // Set to null, assuming no dedicated notes input for session args here. Adjust if a notes field exists.
          plannedDuration: plannedDuration,
          eventId:
              _eventId, // Use _eventId from route arguments, not widget.eventId
          plannedRoute: plannedRoute, // Pass the parsed route points
          plannedRouteDistance: plannedRouteDistance, // Pass route distance
          plannedRouteDuration: plannedRouteDuration, // Pass route duration
          aiCheerleaderEnabled: _aiCheerleaderEnabled, // AI Cheerleader toggle
          aiCheerleaderPersonality:
              _aiCheerleaderPersonality, // Selected personality
          aiCheerleaderExplicitContent:
              _aiCheerleaderExplicitContent, // Explicit language preference
          sessionId:
              ruckId, // Pass the created session ID to prevent duplicate creation
        );

        // CRITICAL DEBUG: Print the actual args being created
        print('🔥🔥🔥 [CREATE_SESSION] ActiveSessionArgs created with:');
        print('🔥🔥🔥   sessionId: $ruckId');
        print(
            '🔥🔥🔥   plannedRoute: ${sessionArgs.plannedRoute?.length ?? 0} points');
        print(
            '🔥🔥🔥   plannedRouteDistance: ${sessionArgs.plannedRouteDistance}');
        print(
            '🔥🔥🔥   plannedRouteDuration: ${sessionArgs.plannedRouteDuration}');
        if (sessionArgs.plannedRoute != null &&
            sessionArgs.plannedRoute!.isNotEmpty) {
          print(
              '🔥🔥🔥   First route point: ${sessionArgs.plannedRoute!.first}');
        }

        // Navigate to CountdownPage which will handle the countdown and transition
        if (!mounted) return;
        // Read skip countdown preference
        bool skipCountdown = false;
        try {
          final prefs = await SharedPreferences.getInstance();
          skipCountdown = prefs.getBool('skip_countdown') ?? false;
        } catch (_) {}

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => skipCountdown
                ? InstantStartPage(args: sessionArgs)
                : CountdownPage(args: sessionArgs),
          ),
        );
      } catch (e) {
        if (mounted) {
          StyledSnackBar.showError(
            context: context,
            message: e.toString().contains(sessionUserWeightRequired)
                ? sessionUserWeightRequired
                : 'Failed to create/start session: $e',
            duration: const Duration(seconds: 3),
          );
          // Only set creating to false on error, success leads to navigation
          setState(() {
            _isCreating = false;
          });
        }
      }
    }
  }

  void _saveOfflineRuck() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isCreating = true;
      });
      try {
        final authState = context.read<AuthBloc>().state;
        if (authState is! Authenticated) throw Exception('Must be logged in');

        double userWeightKg =
            double.tryParse(_userWeightController.text) ?? 70.0;
        if (!_preferMetric) userWeightKg /= 2.20462;

        final minutes = int.parse(_offlineDurationMinutesController.text);
        final seconds =
            int.tryParse(_offlineDurationSecondsController.text) ?? 0;
        final duration = Duration(minutes: minutes, seconds: seconds);
        final distance = double.parse(_offlineDistanceController.text);
        final distanceKm = _preferMetric ? distance : distance * 1.60934;
        final paceMinPerKm = duration.inSeconds / distanceKm;
        final calories = _calculateCalories(
            duration.inSeconds, distanceKm, _ruckWeight, userWeightKg);
        double elevationGainM =
            double.tryParse(_offlineElevationGainController.text) ?? 0.0;
        double elevationLossM =
            double.tryParse(_offlineElevationLossController.text) ?? 0.0;
        if (!_preferMetric) {
          elevationGainM *= 0.3048;
          elevationLossM *= 0.3048;
        }

        final now = DateTime.now();
        final session = RuckSession(
          id: 'manual_${now.millisecondsSinceEpoch}',
          startTime: now.subtract(duration),
          endTime: now,
          duration: duration,
          distance: distanceKm,
          elevationGain: elevationGainM,
          elevationLoss: elevationLossM,
          caloriesBurned: calories.toInt(),
          averagePace: paceMinPerKm,
          ruckWeightKg: _ruckWeight,
          status: RuckStatus.completed,
          isManual: true,
        );

        final repo = GetIt.I<SessionRepository>();
        final apiRuckId = await repo.createManualSession(session.toJson());

        // Invalidate cached session history so homepage refresh shows new ruck
        SessionRepository.clearSessionHistoryCache();

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => SessionCompleteScreen(
              completedAt: now,
              ruckId: apiRuckId,
              duration: duration,
              distance: distanceKm,
              caloriesBurned: calories.toInt(),
              elevationGain: elevationGainM,
              elevationLoss: elevationLossM,
              ruckWeight: _ruckWeight,
              isManual: true,
              aiCompletionInsight:
                  null, // Manual sessions don't have AI insights
            ),
          ),
        );
      } catch (e) {
        StyledSnackBar.showError(
            context: context, message: 'Failed to save offline ruck: $e');
      } finally {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }

  double _calculateCalories(int durationSeconds, double distanceKm,
      double ruckWeightKg, double userWeightKg) {
    final paceMinPerKm = (durationSeconds / 60) / distanceKm;
    double metValue =
        paceMinPerKm <= 8 ? 8.0 : (paceMinPerKm <= 12 ? 6.5 : 5.0);
    final timeHours = durationSeconds / 3600.0;
    return metValue * (userWeightKg + ruckWeightKg) * timeHours;
  }

  String _getDisplayWeight() {
    if (_preferMetric) {
      return '${_ruckWeight.toStringAsFixed(1)} kg';
    } else {
      final lbs = (_ruckWeight * AppConfig.kgToLbs).round();
      return '$lbs lbs';
    }
  }

  @override
  void initState() {
    super.initState();
    // Log the metric preference to verify it's set correctly

    _loadDefaults();
    _selectedRuckWeight =
        _ruckWeight; // initialize with default selected weight

    // Extract event and route context from constructor parameters
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Use constructor parameters instead of route arguments
      final eventId = widget.eventId;
      final eventTitle = widget.eventTitle;
      final routeId = widget.routeId;
      final routeName = widget.routeName;

      print(
          '📋 Create session screen received constructor args: eventId=$eventId, eventTitle=$eventTitle, routeId=$routeId, routeName=$routeName');

      if (eventId != null && eventTitle != null) {
        setState(() {
          _eventId = eventId;
          _eventTitle = eventTitle;
        });
        print(
            '📋 Set event context: _eventId = $_eventId, _eventTitle = $_eventTitle');
      } else if (routeId != null && routeName != null) {
        print(
            '📋 Set route context: routeId = $routeId, routeName = $routeName');
      } else {
        print('📋 No event or route arguments provided');
      }
    });

    // Load metric preference and **body weight** from AuthBloc state
    final authState = context.read<AuthBloc>().state;
    if (authState is Authenticated) {
      setState(() {
        _preferMetric = authState.user.preferMetric;
        // NEW: Pre-populate user weight from profile if available
        final double? profileWeightKg = authState.user.weightKg;
        if (profileWeightKg != null) {
          final String weightText = _preferMetric
              ? profileWeightKg.toStringAsFixed(1)
              : (profileWeightKg * 2.20462).toStringAsFixed(1);
          // Only assign if controller is empty so we don't override SharedPrefs load
          if (_userWeightController.text.isEmpty) {
            _userWeightController.text = weightText;
          }
        }
        // Update display weight based on new preference
        _displayRuckWeight =
            _preferMetric ? _ruckWeight : (_ruckWeight * AppConfig.kgToLbs);
      });

      // Ensure the last ruck weight is loaded and set as selected
      _loadLastRuckWeight();
    }
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _scrollToSelectedWeight());
    _durationFocusNode.addListener(() {});
    // Restore last selected ruck weight and ensure UI reflects it
    SharedPreferences.getInstance().then((prefs) {
      final lastWeightKg = prefs.getDouble('lastRuckWeightKg');
      if (lastWeightKg != null) {
        setState(() {
          _ruckWeight = lastWeightKg;
          _displayRuckWeight =
              _preferMetric ? lastWeightKg : (lastWeightKg * AppConfig.kgToLbs);
          // Explicitly log to verify state update
        });
        // Force a UI rebuild to ensure the chip is selected
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToSelectedWeight();
        });
      } else {}
    });
    // Attach listener after controllers are ready
    _durationListener = () {
      final text = _durationController.text;
      if (text.isEmpty) {
        setState(() {
          _plannedDuration = null;
        });
      } else {
        final minutes = int.tryParse(text);
        setState(() {
          _plannedDuration = (minutes != null && minutes > 0) ? minutes : null;
        });
      }
    };
    _durationController.addListener(_durationListener);
  }

  void _scrollToSelectedWeight() {
    final List<double> currentWeightOptions = _preferMetric
        ? AppConfig.metricWeightOptions
        : AppConfig.standardWeightOptions;
    final selectedIndex = currentWeightOptions.indexWhere((w) {
      final weightInKg = _preferMetric ? w : w / AppConfig.kgToLbs;
      return (weightInKg - _selectedRuckWeight).abs() <
          (_preferMetric ? 0.01 : 0.1);
    });
    if (selectedIndex != -1 && _weightScrollController.hasClients) {
      // Width of each chip item including separator spacing
      const double itemExtent =
          60.0; // 52 chip + 8 separator – keep in sync with separatorBuilder

      double offset;
      if (selectedIndex == currentWeightOptions.length - 1) {
        // Ensure we scroll completely to the end so last chip is fully visible
        offset = _weightScrollController.position.maxScrollExtent;
      } else {
        offset = (selectedIndex * itemExtent)
            .clamp(0.0, _weightScrollController.position.maxScrollExtent);
      }

      // Animate after current frame to avoid "jump" during first build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_weightScrollController.hasClients) {
          _weightScrollController.animateTo(
            offset,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut,
          );
        }
      });
    }
  }

  // Load last saved ruck weight from SharedPreferences
  Future<void> _loadLastRuckWeight() async {
    final prefs = await SharedPreferences.getInstance();
    final lastWeightKg = prefs.getDouble('lastRuckWeightKg');
    if (lastWeightKg != null) {
      setState(() {
        _ruckWeight = lastWeightKg;
        _selectedRuckWeight = lastWeightKg;
        _displayRuckWeight =
            _preferMetric ? lastWeightKg : (lastWeightKg * AppConfig.kgToLbs);
      });
    }
  }

  @override
  void dispose() {
    _weightScrollController.dispose();
    _userWeightController.dispose();
    _customRuckWeightController.dispose();
    _durationController.removeListener(_durationListener);
    _durationController.dispose();
    _durationFocusNode.dispose();
    super.dispose();
  }

  /// Snaps the current weight to the nearest predefined weight option
  void _snapToNearestWeight() {
    List<double> weightOptions = [];

    if (_preferMetric) {
      // Metric options (kg)
      weightOptions = AppConfig.metricWeightOptions;
    } else {
      // Imperial options (lbs)
      weightOptions = AppConfig.standardWeightOptions;
    }

    // Find the nearest weight option
    double? closestOption;
    double minDifference = double.infinity;

    for (var option in weightOptions) {
      final optionInKg = _preferMetric ? option : option / AppConfig.kgToLbs;
      // Use a slightly more forgiving comparison for imperial weights due to conversion rounding
      final difference = (optionInKg - _ruckWeight).abs();

      if (difference < minDifference) {
        minDifference = difference;
        closestOption = option;
      }
    }

    if (closestOption != null) {
      setState(() {
        if (_preferMetric) {
          _ruckWeight = closestOption!;
          _displayRuckWeight = closestOption!;
        } else {
          _ruckWeight = closestOption! / AppConfig.kgToLbs;
          _displayRuckWeight = closestOption!;
        }
        // Make sure _selectedRuckWeight is also updated
        _selectedRuckWeight = _ruckWeight;
      });
    }
  }

  Widget _buildWeightChip(double weightValue, bool isMetric) {
    double weightInKg =
        isMetric ? weightValue : weightValue / AppConfig.kgToLbs;
    final bool isSelected = isMetric
        ? (weightInKg - _selectedRuckWeight).abs() < 0.01
        : (weightInKg - _selectedRuckWeight).abs() < 0.1;

    return ChoiceChip(
      label: Container(
        height: 36,
        alignment: Alignment.center,
        child: Text(
          (weightValue == 0 && isSelected)
              ? 'HIKE'
              : (isMetric
                  ? (weightValue == 0
                      ? '0 kg'
                      : '${weightValue.toStringAsFixed(1)} kg')
                  : (weightValue == 0
                      ? '0 lbs'
                      : '${weightValue.round()} lbs')),
          textAlign: TextAlign.center,
          style: AppTextStyles.statValue.copyWith(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : (isSelected ? Colors.white : Colors.black),
            height: 1.0,
          ),
        ),
      ),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          HapticFeedback.heavyImpact();
          setState(() {
            // Store the correctly converted weight in kg for the API
            _selectedRuckWeight = weightInKg;
            _ruckWeight = weightInKg;
            // Store the display weight in the user's preferred unit
            _displayRuckWeight = weightValue;

            AppLogger.debug(
                'Selected weight chip: ${weightValue} ${isMetric ? "kg" : "lbs"}');
            AppLogger.debug(
                'Converted to: ${_ruckWeight.toStringAsFixed(2)} kg for storage');
          });
        }
      },
      selectedColor: Theme.of(context).primaryColor,
      backgroundColor: isSelected
          ? Theme.of(context).primaryColor
          : (Theme.of(context).brightness == Brightness.dark
              ? AppColors.error
              : AppColors.backgroundLight),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      labelStyle: TextStyle(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white
            : null,
        fontWeight: FontWeight.bold,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
    );
  }

  /// Parse route polyline string into LatLng coordinates
  List<latlong.LatLng> _parsePolylineToLatLng(String polylineString) {
    final List<latlong.LatLng> coordinates = [];

    try {
      // Expect polyline format: "lat1,lng1;lat2,lng2;lat3,lng3"
      final points = polylineString.split(';');

      for (final point in points) {
        if (point.trim().isEmpty) continue;

        final coords = point.split(',');
        if (coords.length == 2) {
          final lat = double.tryParse(coords[0].trim());
          final lng = double.tryParse(coords[1].trim());

          if (lat != null && lng != null) {
            coordinates.add(latlong.LatLng(lat, lng));
          }
        }
      }
    } catch (e) {
      AppLogger.error('Error parsing polyline: $e');
    }

    return coordinates;
  }

  @override
  Widget build(BuildContext context) {
    final String weightUnit = _preferMetric ? 'kg' : 'lbs';
    // Determine the correct list for the chips
    final List<double> currentWeightOptions = _preferMetric
        ? AppConfig.metricWeightOptions
        : AppConfig.standardWeightOptions;

    final keyboardActionsConfig = KeyboardActionsConfig(
      actions: [
        KeyboardActionsItem(
          focusNode: _durationFocusNode,
          toolbarButtons: [
            (node) => TextButton(
                  onPressed: () {
                    HapticFeedback.heavyImpact();
                    node.unfocus();
                    if (!_isCreating) _createSession();
                  },
                  child: const Text('Done'),
                ),
          ],
        ),
      ],
      nextFocus: false,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(_eventTitle != null
            ? 'Start Event Ruck'
            : widget.routeName != null
                ? 'Start Route Ruck'
                : 'New Ruck Session'),
        centerTitle: true,
      ),
      body: KeyboardActions(
        config: keyboardActionsConfig,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Event banner if creating session for an event
                if (_eventTitle != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: AppColors.primary.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.event,
                          color: AppColors.primary,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Event Ruck Session',
                                style: AppTextStyles.titleSmall.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _eventTitle!,
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.textDark,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Route banner if creating session for a route
                if (widget.routeName != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: AppColors.primary.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.route,
                          color: AppColors.primary,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Route Ruck Session',
                                style: AppTextStyles.titleSmall.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.routeName!,
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.textDark,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Section title
                Text(
                  'Session Details',
                  style: AppTextStyles.titleLarge, // headline6 -> titleLarge
                ),
                const SizedBox(height: 24),

                // AI Coaching guidance
                AICoachingSessionWidget(
                  coachingPlan: _coachingPlan,
                  nextSession: _nextSession,
                  progress: _coachingProgress,
                  preferMetric: _preferMetric,
                  coachingPersonality: _coachingPlan?['personality'],
                ),

                // Coaching plan recommendations
                PlanSessionRecommendations(
                  coachingPlan: _coachingPlan,
                  nextSession: _nextSession,
                  preferMetric: _preferMetric,
                  onUseRecommended: _applyCoachingRecommendations,
                ),

                // Quick ruck weight selection
                Text(
                  'Ruck Weight ($weightUnit)',
                  style: AppTextStyles.titleMedium.copyWith(
                      fontWeight: FontWeight.bold), // subtitle1 -> titleMedium
                ),
                const SizedBox(height: 8),
                Text(
                  'Weight is used to calculate calories burned during your ruck',
                  style: AppTextStyles.bodySmall.copyWith(
                    // caption -> bodySmall
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Color(0xFF728C69)
                        : AppColors.textDarkSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 40,
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(),
                        )
                      : ListView.separated(
                          controller: _weightScrollController,
                          scrollDirection: Axis.horizontal,
                          clipBehavior: Clip.none,
                          itemCount: currentWeightOptions.length,
                          itemBuilder: (context, index) {
                            final weightValue = currentWeightOptions[index];
                            return _buildWeightChip(weightValue, _preferMetric);
                          },
                          separatorBuilder: (context, index) =>
                              const SizedBox(width: 8),
                        ),
                ),
                const SizedBox(height: 8),

                // Link to toggle custom ruck weight input
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                    ),
                    onPressed: () {
                      setState(() {
                        _showCustomRuckWeightInput =
                            !_showCustomRuckWeightInput;
                        if (!_showCustomRuckWeightInput) {
                          // Clear any entered custom weight when hiding
                          _customRuckWeightController.clear();
                        }
                      });
                    },
                    child: Text(
                      _showCustomRuckWeightInput
                          ? 'Hide custom weight'
                          : 'Enter custom weight',
                      style: AppTextStyles.bodySmall.copyWith(
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
                if (_showCustomRuckWeightInput) ...[
                  const SizedBox(height: 8),
                  CustomTextField(
                    controller: _customRuckWeightController,
                    label: 'Custom Ruck Weight ($weightUnit)',
                    hint: 'e.g. 37.5',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    prefixIcon: Icons.fitness_center_outlined,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                    ],
                    validator: (value) {
                      if (!_showCustomRuckWeightInput)
                        return null; // Skip if not shown
                      if (value == null || value.isEmpty) {
                        return 'Please enter a weight';
                      }
                      final parsed = double.tryParse(value);
                      if (parsed == null || parsed <= 0) {
                        return sessionInvalidWeight;
                      }
                      return null;
                    },
                    onChanged: (value) {
                      final parsed = double.tryParse(value);
                      if (parsed != null && parsed > 0) {
                        setState(() {
                          if (_preferMetric) {
                            _ruckWeight = parsed;
                            _displayRuckWeight = parsed;
                          } else {
                            _ruckWeight = parsed / AppConfig.kgToLbs;
                            _displayRuckWeight = parsed;
                          }
                          _selectedRuckWeight = _ruckWeight;
                        });
                      }
                    },
                  ),
                ],
                const SizedBox(height: 32),

                // User weight field (optional)
                CustomTextField(
                  controller: _userWeightController,
                  label: 'Your Weight ($weightUnit)',
                  hint: 'Enter your weight',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  prefixIcon: Icons.monitor_weight_outlined,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                  ],
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return null;
                    }
                    if (double.tryParse(value) == null) {
                      return sessionInvalidWeight;
                    }
                    if (double.parse(value) <= 0) {
                      return sessionInvalidWeight;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // Planned duration field
                CustomTextField(
                  controller: _durationController,
                  label: 'Planned Duration (minutes) - Optional',
                  hint: 'Enter planned duration',
                  keyboardType: TextInputType.number,
                  focusNode: _durationFocusNode,
                  prefixIcon: Icons.timer_outlined,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  validator: (value) {
                    if (value != null && value.isNotEmpty) {
                      if (int.tryParse(value) == null) {
                        return sessionInvalidDuration;
                      }
                      if (int.parse(value) <= 0) {
                        return sessionInvalidDuration;
                      }
                    }
                    return null;
                  },
                  onChanged: (value) {
                    setState(() {
                      if (value.isEmpty) {
                        _plannedDuration = null;
                      } else {
                        final parsed = int.tryParse(value);
                        _plannedDuration =
                            (parsed != null && parsed > 0) ? parsed : null;
                      }
                    });
                  },
                  onFieldSubmitted: (_) {
                    FocusScope.of(context).unfocus();
                    if (!_isCreating) _createSession();
                  },
                ),
                const SizedBox(height: 32),

                // AI Cheerleader Controls
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI Cheerleader',
                          style: AppTextStyles.titleLarge.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Get AI-powered motivation during your ruck',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // AI Cheerleader Toggle
                        SwitchListTile(
                          title: const Text('Enable AI Cheerleader'),
                          subtitle: const Text(
                              'Get motivational messages during your ruck'),
                          value: _aiCheerleaderEnabled,
                          onChanged: (bool value) async {
                            setState(() {
                              _aiCheerleaderEnabled = value;
                            });
                            // Save preference immediately
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setBool('aiCheerleaderEnabled', value);
                          },
                          contentPadding: EdgeInsets.zero,
                        ),

                        // Personality Dropdown (only shown when enabled)
                        if (_aiCheerleaderEnabled) ...[
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: _aiCheerleaderPersonality,
                            decoration: const InputDecoration(
                              labelText: 'Personality',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                            ),
                            items: const [
                              DropdownMenuItem(
                                  value: 'Supportive Friend',
                                  child: Text('Supportive Friend (F)')),
                              DropdownMenuItem(
                                  value: 'Drill Sergeant',
                                  child: Text('Drill Sergeant (M)')),
                              DropdownMenuItem(
                                  value: 'Southern Redneck',
                                  child: Text('Southern Redneck (M)')),
                              DropdownMenuItem(
                                  value: 'Yoga Instructor',
                                  child: Text('Yoga Instructor (F)')),
                              DropdownMenuItem(
                                  value: 'British Butler',
                                  child: Text('British Butler (M)')),
                              DropdownMenuItem(
                                  value: 'Sports Commentator',
                                  child: Text('Sports Commentator (M)')),
                              DropdownMenuItem(
                                  value: 'Cowboy/Cowgirl',
                                  child: Text('Cowboy (M)')),
                              DropdownMenuItem(
                                  value: 'Nature Lover',
                                  child: Text('Nature Lover (F)')),
                              DropdownMenuItem(
                                  value: 'Burt Reynolds',
                                  child: Text('Burt Reynolds (M)')),
                              DropdownMenuItem(
                                  value: 'Tom Selleck',
                                  child: Text('Tom Selleck (M)')),
                            ],
                            onChanged: (String? newValue) async {
                              if (newValue != null) {
                                setState(() {
                                  _aiCheerleaderPersonality = newValue;
                                });
                                // Save preference immediately
                                final prefs =
                                    await SharedPreferences.getInstance();
                                await prefs.setString(
                                    'aiCheerleaderPersonality', newValue);
                              }
                            },
                          ),

                          const SizedBox(height: 8),

                          // Explicit Content Toggle
                          SwitchListTile(
                            title: const Text('Explicit Language'),
                            subtitle: const Text(
                                'Allow stronger language for intense motivation'),
                            value: _aiCheerleaderExplicitContent,
                            onChanged: (bool value) async {
                              setState(() {
                                _aiCheerleaderExplicitContent = value;
                              });
                              // Save preference immediately
                              final prefs =
                                  await SharedPreferences.getInstance();
                              await prefs.setBool(
                                  'aiCheerleaderExplicitContent', value);
                            },
                            contentPadding: EdgeInsets.zero,
                          ),

                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 8),

                          // Live Following Toggle
                          SwitchListTile(
                            title: const Text('Allow Live Following'),
                            subtitle: const Text(
                                'Let friends follow your ruck live and send voice messages'),
                            value: _allowLiveFollowing,
                            onChanged: (bool value) {
                              setState(() {
                                _allowLiveFollowing = value;
                              });
                            },
                            contentPadding: EdgeInsets.zero,
                            activeColor: AppColors.primary,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                if (_isOfflineMode) ...[
                  const SizedBox(height: 16),
                  CustomTextField(
                    controller: _offlineDurationMinutesController,
                    label: 'Duration Minutes',
                    hint: 'e.g. 45',
                    keyboardType: TextInputType.number,
                    validator: (value) =>
                        value?.isEmpty ?? true ? 'Minutes required' : null,
                  ),
                  const SizedBox(height: 8),
                  CustomTextField(
                    controller: _offlineDurationSecondsController,
                    label: 'Duration Seconds',
                    hint: 'e.g. 30',
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value?.isEmpty ?? true) return null;
                      final sec = int.tryParse(value!);
                      return (sec == null || sec < 0 || sec >= 60)
                          ? '0-59'
                          : null;
                    },
                  ),
                  const SizedBox(height: 16),
                  CustomTextField(
                    controller: _offlineDistanceController,
                    label: 'Distance (${_preferMetric ? 'km' : 'miles'})',
                    hint: 'e.g. ${_preferMetric ? '5.0' : '3.1'}',
                    keyboardType:
                        TextInputType.numberWithOptions(decimal: true),
                    validator: (value) =>
                        value?.isEmpty ?? true ? 'Distance is required' : null,
                  ),
                  const SizedBox(height: 16),
                  CustomTextField(
                    controller: _offlineElevationGainController,
                    label:
                        'Elevation Gain (${_preferMetric ? 'meters' : 'feet'}) - Optional',
                    hint: 'e.g. ${_preferMetric ? '100' : '328'}',
                    keyboardType:
                        TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 16),
                  CustomTextField(
                    controller: _offlineElevationLossController,
                    label:
                        'Elevation Loss (${_preferMetric ? 'meters' : 'feet'}) - Optional',
                    hint: 'e.g. ${_preferMetric ? '100' : '328'}',
                    keyboardType:
                        TextInputType.numberWithOptions(decimal: true),
                  ),
                ],
                const SizedBox(height: 32),

                // Start session button - orange and full width
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: Text(
                        _isOfflineMode ? 'SAVE OFFLINE RUCK' : 'START SESSION',
                        style: AppTextStyles.labelLarge.copyWith(
                          // button -> labelLarge
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        )),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.secondary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed:
                        _isOfflineMode ? _saveOfflineRuck : _createSession,
                  ),
                ),
                Center(
                  child: TextButton(
                    onPressed: () {
                      setState(() {
                        _isOfflineMode = !_isOfflineMode;
                        if (!_isOfflineMode) {
                          _offlineDurationMinutesController.clear();
                          _offlineDurationSecondsController.clear();
                          _offlineDistanceController.clear();
                          _offlineElevationGainController.clear();
                          _offlineElevationLossController.clear();
                        }
                      });
                    },
                    child: Text(
                        _isOfflineMode ? 'Cancel' : 'Record Offline Ruck',
                        style: TextStyle(fontSize: 14, color: Colors.grey)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
