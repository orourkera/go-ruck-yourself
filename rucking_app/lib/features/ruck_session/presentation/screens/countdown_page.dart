import 'dart:async';
import 'dart:async' show StreamSubscription;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/location_service.dart';
import 'package:rucking_app/core/services/watch_service.dart';
import 'package:rucking_app/core/services/active_session_storage.dart';
import 'package:rucking_app/core/services/terrain_tracker.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'package:rucking_app/features/health_integration/domain/health_service.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';
import 'package:rucking_app/features/ruck_session/data/repositories/session_repository.dart';
import 'package:rucking_app/features/ruck_session/domain/services/heart_rate_service.dart';
import 'package:rucking_app/features/ruck_session/domain/services/split_tracking_service.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/active_session_page.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/core/services/connectivity_service.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

/// A dedicated countdown page that shows a countdown before starting a ruck session
/// This avoids showing any map or loading screens before the session is ready
class CountdownPage extends StatefulWidget {
  final ActiveSessionArgs args;

  const CountdownPage({Key? key, required this.args}) : super(key: key);

  @override
  State<CountdownPage> createState() => _CountdownPageState();
}

class _CountdownPageState extends State<CountdownPage> with SingleTickerProviderStateMixin {
  int _count = 3;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  Timer? _timer;
  bool _countdownComplete = false;
  
  // Preload the bloc to start session initialization while countdown runs
  late ActiveSessionBloc _sessionBloc;
  StreamSubscription? _blocSubscription;

  // Last known location to pass to the map for faster centering
  latlong.LatLng? _initialCenter;

  @override
  void initState() {
    super.initState();
    
    // Animation setup
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    
    _scaleAnimation = Tween<double>(begin: 1.0, end: 3.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    
    // Start session initialization in background
    final locator = GetIt.instance;
    _sessionBloc = ActiveSessionBloc(
      apiClient: locator<ApiClient>(),
      locationService: locator<LocationService>(),
      healthService: locator<HealthService>(),
      watchService: locator<WatchService>(),
      heartRateService: locator<HeartRateService>(),
      splitTrackingService: locator<SplitTrackingService>(),
      terrainTracker: locator<TerrainTracker>(),
      sessionRepository: locator<SessionRepository>(),
      activeSessionStorage: locator<ActiveSessionStorage>(),
      connectivityService: locator<ConnectivityService>(),
    );
    
    // Start countdown after a brief delay to ensure screen is visible
    Future.delayed(const Duration(milliseconds: 200), () {
      _startCountdown();
    });
  }

  // Flag to track if session is initiated
  bool _sessionInitiated = false;
  bool _isLoading = true;
  bool _preloadComplete = false;
  
  void _startCountdown() {
    // Start session with a small delay 
    if (!_sessionInitiated) {
      _sessionInitiated = true;
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          // Initiate session during countdown
          _sessionBloc.add(SessionStarted(
            ruckWeightKg: widget.args.ruckWeight,
            userWeightKg: widget.args.userWeightKg,
            notes: widget.args.notes ?? '',
            plannedDuration: widget.args.plannedDuration,
            eventId: widget.args.eventId, // Pass event ID if creating session from event
          ));
          
          // Listen for session state changes
          _blocSubscription = _sessionBloc.stream.listen((state) {
            if (state is ActiveSessionRunning && mounted) {
              // Session is now running - mark as ready
              AppLogger.debug('[COUNTDOWN] ActiveSessionRunning state received - setting isLoading=false');
              setState(() {
                _isLoading = false;
              });
            }
          });
        }
      });
    }
    
    // Start map and assets preloading
    _preloadResources();
    
    // Start countdown timer
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_count > 1) {
        setState(() {
          _count--;
        });
        _controller.forward(from: 0.0);
      } else {
        // Final countdown animation
        AppLogger.debug('[COUNTDOWN] Countdown completed');
        setState(() {
          _countdownComplete = true;
        });
        
        _controller.forward(from: 0.0).then((_) {
          timer.cancel();
          
          // Only navigate when both countdown complete AND preloading complete
          _checkAndNavigateIfReady();
        });
      }
    });
  }
  
  void _preloadResources() async {
    // Preload map tiles for current location if available
    // This helps avoid the blue map flash
    
    // Try to fetch the user's last known location quickly
    try {
      final locationService = GetIt.instance<LocationService>();
      // Add timeout to prevent hanging
      final last = await locationService.getCurrentLocation().timeout(
        const Duration(seconds: 2),
        onTimeout: () => null,
      );
      if (last != null) {
        _initialCenter = latlong.LatLng(last.latitude, last.longitude);
      }
    } catch (e) {
      // Silent failure – fallback to default center in ActiveSessionPage
      AppLogger.debug('[COUNTDOWN] Location fetch failed: $e');
    }
    
    // Simulate resource loading with a minimum delay so the countdown animation isn't cut short
    await Future.delayed(const Duration(seconds: 3));
    
    setState(() {
      _preloadComplete = true;
    });
    AppLogger.debug('[COUNTDOWN] Preload complete');
    _checkAndNavigateIfReady();
  }
  
  void _checkAndNavigateIfReady() {
    // Only navigate when both conditions are met:
    // 1. Countdown is complete
    // 2. Preloading has finished
    // 3. Session state is ready
    AppLogger.debug('[COUNTDOWN] Navigation check: countdownComplete=$_countdownComplete, preloadComplete=$_preloadComplete, isLoading=$_isLoading, mounted=$mounted');
    
    if (_countdownComplete && _preloadComplete && !_isLoading && mounted) {
      AppLogger.debug('[COUNTDOWN] All conditions met - navigating to ActiveSessionPage');
      
      // Start the session timer before navigating
      _sessionBloc.add(TimerStarted());

      // Inject initialCenter into args to ensure the map centers immediately
      final argsWithCenter = ActiveSessionArgs(
        ruckWeight: widget.args.ruckWeight,
        userWeightKg: widget.args.userWeightKg,
        notes: widget.args.notes,
        plannedDuration: widget.args.plannedDuration,
        initialCenter: _initialCenter ?? widget.args.initialCenter,
      );

      // Navigate to the actual session with a brief fade transition
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 800),
          pageBuilder: (context, animation, secondaryAnimation) => 
            FadeTransition(
              opacity: animation,
              child: BlocProvider.value(
                value: _sessionBloc,
                child: ActiveSessionPage(args: argsWithCenter),
              ),
            ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    // Cancel stream subscription to avoid setState after dispose
    _blocSubscription?.cancel();
    // Don't dispose the session bloc - it's being passed to the next screen
    super.dispose();
  }
  
  // Helper method to get the appropriate background color based on user gender
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
    return Scaffold(
      body: Container(
        color: _getLadyModeColor(context),
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              // Show GO when countdown reaches 0
              final displayText = _countdownComplete ? 'GO!' : _count.toString();
              
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: Opacity(
                  opacity: 1.0 - (_controller.value * 0.7),
                  child: Text(
                    displayText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 96,
                      fontFamily: 'Bangers',
                      fontWeight: FontWeight.normal,
                      letterSpacing: 2.0,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
