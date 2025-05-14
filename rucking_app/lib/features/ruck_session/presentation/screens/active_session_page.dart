import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:rucking_app/shared/widgets/styled_snackbar.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:rucking_app/core/utils/measurement_utils.dart';

import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/location_service.dart';
import 'package:rucking_app/core/services/watch_service.dart';
import 'package:rucking_app/features/health_integration/domain/health_service.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';
import 'package:rucking_app/features/ruck_session/presentation/widgets/session_stats_overlay.dart';
import 'package:rucking_app/features/ruck_session/presentation/widgets/session_controls.dart';

import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:provider/provider.dart';

/// Arguments passed to the ActiveSessionPage
class ActiveSessionArgs {
  final double ruckWeight;
  final String? notes;
  final latlong.LatLng? initialCenter;
  final int? plannedDuration;

  const ActiveSessionArgs({
    required this.ruckWeight,
    this.notes,
    this.initialCenter,
    this.plannedDuration,
  });
}

/// Thin UI wrapper around ActiveSessionBloc.
/// All heavy lifting happens in the Bloc – this widget just renders state.
class ActiveSessionPage extends StatelessWidget {
  const ActiveSessionPage({Key? key, required this.args}) : super(key: key);

  final ActiveSessionArgs args;

  @override
  Widget build(BuildContext context) {
    // If an ActiveSessionBloc is already provided higher up in the widget tree
    // (e.g. by the CountdownPage for pre-loading), reuse that instead of creating
    // a new one. This ensures the session continues seamlessly once the
    // countdown finishes and avoids restarting any logic inside the bloc.

    ActiveSessionBloc? existingBloc;
    try {
      existingBloc = BlocProvider.of<ActiveSessionBloc>(context, listen: false);
    } catch (_) {
      existingBloc = null;
    }

    if (existingBloc != null) {
      // Bloc already exists – simply build the view.
      return _ActiveSessionView(args: args);
    }

    // No existing bloc – create a fresh one (e.g. when user lands here
    // directly without going through the countdown page).
    final locator = GetIt.I;
    return BlocProvider(
      create: (_) => ActiveSessionBloc(
        apiClient: locator<ApiClient>(),
        locationService: locator<LocationService>(),
        healthService: locator<HealthService>(),
        watchService: locator<WatchService>(),
      ),
      child: _ActiveSessionView(args: args),
    );
  }
}

class _ActiveSessionView extends StatefulWidget {
  final ActiveSessionArgs args;
  const _ActiveSessionView({Key? key, required this.args}) : super(key: key);

  @override
  State<_ActiveSessionView> createState() => _ActiveSessionViewState();
}

class _ActiveSessionViewState extends State<_ActiveSessionView> {
  bool mapReady = false;
  bool sessionRunning = false;
  bool uiInitialized = false;

  void _checkAnimateOverlay() {
    // No animation needed anymore since we removed the gray overlay
    // This method is kept for compatibility but doesn't do anything
  }

  @override
  void initState() {
    super.initState();
    
    // Wait a short moment for UI to render before initializing the session
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Set UI as initialized to allow conditional rendering
      setState(() {
        uiInitialized = true;
      });
    });
    
    // Listen for session state changes
    final bloc = context.read<ActiveSessionBloc>();
    bloc.stream.listen((state) {
      if (state is ActiveSessionRunning && !sessionRunning) {
        // When session first starts running, mark it
        setState(() {
          sessionRunning = true;
        });
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _handleEndSession(BuildContext context, ActiveSessionRunning currentState) {
    // Always allow session to be ended and saved, regardless of distance/duration
    _showConfirmEndSessionDialog(context, currentState);
  }

  void _showConfirmEndSessionDialog(BuildContext context, ActiveSessionState state) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        // Now inside the builder, safe to use Provider.of or context.select
        final authBloc = Provider.of<AuthBloc>(dialogContext, listen: false);
        final bool preferMetric = authBloc.state is Authenticated
            ? (authBloc.state as Authenticated).user.preferMetric
            : true;
        
        return AlertDialog(
          title: const Text('Confirm End Session'),
          content: Text('Are you sure you want to end the session?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                // Emit a final Tick event to ensure state is up to date before ending session
                context.read<ActiveSessionBloc>().add(const Tick());
                context.read<ActiveSessionBloc>().add(const SessionCompleted());
                Navigator.of(dialogContext).pop();
              },
              child: const Text('End Session'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Base UI - Map and Stats
          Column(
            children: [
              // Header fills all the way to the top (behind status bar)
              Builder(
                builder: (context) {
                  final double topPadding = MediaQuery.of(context).padding.top;
                  return Container(
                    width: double.infinity,
                    padding: EdgeInsets.only(top: topPadding, bottom: 18.0),
                    color: AppColors.primary,
                    child: Center(
                      child: Text(
                        'ACTIVE SESSION',
                        style: AppTextStyles.headlineLarge.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  );
                },
              ),
              // Rest of content in SafeArea
              Expanded(
                child: SafeArea(
                  top: false,
                  child: BlocConsumer<ActiveSessionBloc, ActiveSessionState>(
                    listenWhen: (prev, curr) => 
                      (prev is ActiveSessionFailure != curr is ActiveSessionFailure) || 
                      (curr is ActiveSessionComplete) ||
                      (curr is ActiveSessionRunning && !sessionRunning),
                    listener: (ctx, state) {
                      if (state is ActiveSessionFailure) {
                        StyledSnackBar.showError(
                          context: ctx,
                          message: state.errorMessage,
                          duration: const Duration(seconds: 3),
                        );
                      } else if (state is ActiveSessionComplete) {
                        final endTime = state.session.endTime ?? DateTime.now();
                        final ruckId = state.session.id ?? '';
                        final duration = state.session.duration ?? Duration.zero;
                        final distance = state.session.distance ?? 0.0;
                        final caloriesBurned = state.session.caloriesBurned ?? 0;
                        final elevationGain = state.session.elevationGain ?? 0.0;
                        final elevationLoss = state.session.elevationLoss ?? 0.0;
                        final ruckWeightKg = state.session.ruckWeightKg ?? 0.0;
                        final notes = state.session.notes;
                        final heartRateSamples = state.session.heartRateSamples;

                        if (state.session.endTime == null) {
                          debugPrint('[SessionCompleteScreen] endTime was null, using DateTime.now()');
                        }
                        if (state.session.id == null) {
                          debugPrint('[SessionCompleteScreen] ruckId was null, using empty string');
                        }
                        if (state.session.duration == null) {
                          debugPrint('[SessionCompleteScreen] duration was null, using Duration.zero');
                        }
                        if (state.session.distance == null) {
                          debugPrint('[SessionCompleteScreen] distance was null, using 0.0');
                        }
                        if (state.session.caloriesBurned == null) {
                          debugPrint('[SessionCompleteScreen] caloriesBurned was null, using 0');
                        }
                        if (state.session.elevationGain == null) {
                          debugPrint('[SessionCompleteScreen] elevationGain was null, using 0.0');
                        }
                        if (state.session.elevationLoss == null) {
                          debugPrint('[SessionCompleteScreen] elevationLoss was null, using 0.0');
                        }
                        if (state.session.ruckWeightKg == null) {
                          debugPrint('[SessionCompleteScreen] ruckWeightKg was null, using 0.0');
                        }

                        Navigator.of(ctx).pushReplacementNamed(
                          '/session_complete',
                          arguments: {
                            'completedAt': endTime,
                            'ruckId': ruckId,
                            'duration': duration,
                            'distance': distance,
                            'caloriesBurned': caloriesBurned,
                            'elevationGain': elevationGain,
                            'elevationLoss': elevationLoss,
                            'ruckWeight': ruckWeightKg,
                            'initialNotes': notes,
                            'heartRateSamples': heartRateSamples,
                          },
                        );
                      } else if (state is ActiveSessionRunning && !sessionRunning) {
                        setState(() {
                          sessionRunning = true;
                        });
                        // Session just started running - DON'T animate overlay away yet
                        // The countdown completion will trigger this later
                      }  
                    },
                    buildWhen: (prev, curr) => prev != curr,
                    builder: (ctx, state) {
                      if (state is ActiveSessionInitial || state is ActiveSessionLoading) {
                        return _buildSessionContent(state);
                      }
                      if (state is ActiveSessionRunning) {
                        final route = state.locationPoints
                            .map((p) => latlong.LatLng(p.latitude, p.longitude))
                            .toList();
                        // DEBUG: Print route length and points
                        debugPrint('Route length:  [32m [1m [4m [7m${route.length} [0m');
                        for (var i = 0; i <route.length; i++) {
                          debugPrint('Route[$i]: Lat:  [36m${route[i].latitude} [0m, Lng:  [36m${route[i].longitude} [0m');
                        }

                        return SingleChildScrollView(
                          child: Column(
                            children: [
                              // Map with weight chip overlay
                              Padding(
                                padding: const EdgeInsets.only(top: 4.0, left: 8.0, right: 8.0),
                                child: Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(18),
                                      child: SizedBox(
                                        height: MediaQuery.of(context).size.height * 0.27,
                                        width: double.infinity,
                                        child: sessionRunning && uiInitialized
                                        ? _RouteMap(
                                            route: route,
                                            initialCenter: (context.findAncestorWidgetOfExactType<ActiveSessionPage>()?.args.initialCenter),
                                            onMapReady: () {
                                              if (!mapReady) {
                                                setState(() {
                                                  mapReady = true;
                                                });
                                                _checkAnimateOverlay();
                                              }
                                            },
                                          )
                                        : Container(
                                            color: const Color(0xFFE5E3DF), // Match map color
                                            child: const Center(
                                              child: CircularProgressIndicator(),
                                            ),
                                          ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 12,
                                      right: 12,
                                      child: _WeightChip(weightKg: state.ruckWeightKg),
                                    ),
                                    if (state.isPaused)
                                      const Positioned.fill(child: IgnorePointer(
                                        ignoring: true, // Let touch events pass through
                                        child: _PauseOverlay(),
                                      )),

                                  ],
                                ),
                              ),
                              const SizedBox(height: 8.0), // Added for spacing
                              // Stats overlay or spinner
                              Padding(
                                padding: const EdgeInsets.all(16.0), // This was the padding inside the Expanded
                                child: BlocBuilder<ActiveSessionBloc, ActiveSessionState>(
                                  key: const ValueKey('stats_overlay_builder'),
                                  buildWhen: (prev, curr) {
                                    if (prev is ActiveSessionRunning && curr is ActiveSessionRunning) {
                                      return prev.distanceKm != curr.distanceKm ||
                                             prev.pace != curr.pace ||
                                             prev.elapsedSeconds != curr.elapsedSeconds ||
                                             prev.latestHeartRate != curr.latestHeartRate ||
                                             prev.calories != curr.calories ||
                                             prev.elevationGain != curr.elevationGain ||
                                             prev.elevationLoss != curr.elevationLoss ||
                                             prev.plannedDuration != curr.plannedDuration;
                                    }
                                    return true;
                                  },
                                  builder: (context, state) {
                                    if (state is ActiveSessionRunning) {
                                      final authBloc = Provider.of<AuthBloc>(context, listen: false);
                                      final bool preferMetric = authBloc.state is Authenticated
                                          ? (authBloc.state as Authenticated).user.preferMetric
                                          : true;
                                      return SessionStatsOverlay(
                                        state: state,
                                        preferMetric: preferMetric,
                                        useCardLayout: true,
                                      );
                                    }
                                    // Fallback: show placeholder stats instead of spinner
                                    return SessionStatsOverlay.placeholder();
                                  },
                                ),
                              ),
                              const SizedBox(height: 8.0), // Added for spacing
                              // Controls at bottom
                              Padding(
                                padding: const EdgeInsets.only(left: 8.0, right: 8.0, bottom: 10.0, top: 4.0),
                                child: BlocBuilder<ActiveSessionBloc, ActiveSessionState>(
                                  buildWhen: (prev, curr) {
                                    // Rebuild when the state type changes (e.g. Initial -> Running) or when
                                    // the paused flag toggles within a running session.
                                    if (prev.runtimeType != curr.runtimeType) return true;
                                    if (prev is ActiveSessionRunning && curr is ActiveSessionRunning) {
                                      return prev.isPaused != curr.isPaused;
                                    }
                                    return false;
                                  },
                                  builder: (context, state) {
                                    bool isPaused = state is ActiveSessionRunning ? state.isPaused : false;
                                    return SessionControls(
                                      isPaused: isPaused,
                                      onTogglePause: () {
                                        if (state is! ActiveSessionRunning) return; // Ignore if not running
                                        if (isPaused) {
                                          context.read<ActiveSessionBloc>().add(const SessionResumed());
                                        } else {
                                          context.read<ActiveSessionBloc>().add(const SessionPaused());
                                        }
                                      },
                                      onEndSession: () {
                                        if (state is ActiveSessionRunning) {
                                          _handleEndSession(context, state);
                                        }
                                      },
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 16.0), // Added for bottom padding within scroll view
                            ],
                          ),
                        );
                      }
                      if (state is ActiveSessionComplete) {
                        return Center(
                          child: Text(
                            'Session Completed — Distance: ${state.session.distance.toStringAsFixed(2)} km',
                            style: AppTextStyles.titleMedium,
                          ),
                        );
                      }
                      return const SizedBox();
                    },
                  ),
                ),
              ),
            ],
          ),
          // Removed duplicate countdown overlay - now positioned at top of stack
          
          // Pause overlay logic handled in map Stack above. Removed duplicate overlay here.
        ],
      ),
    );
  }

  Widget _buildSessionContent(ActiveSessionState state) {
    final authBloc = Provider.of<AuthBloc>(context, listen: false);
    final bool preferMetric = authBloc.state is Authenticated
        ? (authBloc.state as Authenticated).user.preferMetric
        : true;
    
    List<latlong.LatLng> route = [];
    if (state is ActiveSessionRunning) {
      route = state.locationPoints
          .map((point) => latlong.LatLng(point.latitude, point.longitude))
          .toList();
    }
    
    return Column(
      children: [
        // Map section always visible
        Expanded(
          flex: 2,
          child: _RouteMap(
            route: route,
            initialCenter: route.isNotEmpty ? route.last : null,
            onMapReady: () {
              if (!mapReady) {
                setState(() {
                  mapReady = true;
                });
                _checkAnimateOverlay();
              }
            },
          ),
        ),
        // Stats area or spinner below the map
        Expanded(
          flex: 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
            child: state is ActiveSessionRunning
                ? SessionStatsOverlay(
                    state: state as ActiveSessionRunning,
                    preferMetric: preferMetric,
                    useCardLayout: true,
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
        ),
      ],
    );
  }

  Widget _buildPaceDisplay(ActiveSessionState state) {
    final authBloc = Provider.of<AuthBloc>(context, listen: false);
    final bool preferMetric = authBloc.state is Authenticated
        ? (authBloc.state as Authenticated).user.preferMetric
        : true;

    int elapsedSeconds = 0;
    double distanceKm = 0.0;
    final pace = state is ActiveSessionRunning ? (state as ActiveSessionRunning).pace : null;
    if (state is ActiveSessionRunning) {
      elapsedSeconds = state.elapsedSeconds;
      distanceKm = state.distanceKm;
    }

    // Thresholds
    const int minTimeSeconds = 60; // 1 minute
    const double minDistanceKm = 0.2; // 200 meters

    // 60 min/km = 3600 seconds/km (or seconds/mi)
    final bool paceTooHigh = pace != null && pace > 3600;
    final bool showPace = elapsedSeconds >= minTimeSeconds && distanceKm >= minDistanceKm && pace != null && !paceTooHigh;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Pace', style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        showPace
            ? Text(
                MeasurementUtils.formatPace(pace!, metric: preferMetric),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              )
            : const Text('--', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

/// Real map – replace with FlutterMap or GoogleMap.
class _RouteMap extends StatefulWidget {
  final VoidCallback? onMapReady;
  const _RouteMap({required this.route, this.initialCenter, this.onMapReady});

  final List<latlong.LatLng> route;
  final latlong.LatLng? initialCenter;

  @override
  State<_RouteMap> createState() => _RouteMapState();
}

class _RouteMapState extends State<_RouteMap> {
  bool _mapReadyCalled = false;
  bool _tilesLoaded = false; // Track if map tiles have loaded
  Timer? _fallbackTimer;
  final MapController _controller = MapController();
  
  void _signalMapReady() {
    if (!_mapReadyCalled && widget.onMapReady != null) {
      _mapReadyCalled = true;
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) widget.onMapReady!();
      });
    }
  }
  
  // This method will be called when map tiles are loaded
  void _onTilesLoaded() {
    if (!_tilesLoaded && mounted) {
      setState(() {
        _tilesLoaded = true;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _fallbackTimer = Timer(const Duration(seconds: 5), () {
      if (!_mapReadyCalled) {
        print("Fallback timer triggered: calling onMapReady");
        _signalMapReady();
      }
    });
    // Schedule a microtask to fit bounds after the first frame if route is available.
    // This ensures the map is laid out before we try to fit bounds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fitBoundsToRoute();
    });
  }

  @override
  // Keep track of when we last did a bounds fit to avoid doing it too frequently
  DateTime? _lastBoundsFitTime;
  
  void didUpdateWidget(covariant _RouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Only process if we have a route and it has changed
    if (widget.route.isNotEmpty && widget.route != oldWidget.route) {
      // Check if this is the first point or a new point was added
      bool isNewPoint = widget.route.length > oldWidget.route.length;
      if (!isNewPoint) return; // Skip if no new points (avoid redundant updates)
      
      // Determine if we should do a full bounds fit
      bool shouldFitBounds = 
          // First location update ever
          _lastBoundsFitTime == null || 
          // First location point
          (widget.route.length == 1 && oldWidget.route.isEmpty) ||
          // Do a bounds fit every 30 seconds instead of 10 to reduce jumpy behavior
          (_lastBoundsFitTime != null && 
           DateTime.now().difference(_lastBoundsFitTime!).inSeconds > 30);
      
      // Use a short delay to batch updates that might come in rapid succession
      Future.delayed(const Duration(milliseconds: 50), () {
        if (!mounted) return;
        
        if (shouldFitBounds) {
          _fitBoundsToRoute();
          _lastBoundsFitTime = DateTime.now();
        } else {
          // For most updates, just smoothly center on the user's location
          _centerOnLastPoint();
        }
      });
    }
  }

  void _fitBoundsToRoute() {
    if (mounted && widget.route.length > 1) {
      // Calculate bounds manually
      double minLat = 90.0;
      double maxLat = -90.0;
      double minLng = 180.0;
      double maxLng = -180.0;
      
      // Find the min/max bounds
      for (final point in widget.route) {
        minLat = math.min(minLat, point.latitude);
        maxLat = math.max(maxLat, point.latitude);
        minLng = math.min(minLng, point.longitude);
        maxLng = math.max(maxLng, point.longitude);
      }
      
      // Add padding
      final padding = 0.01; // roughly equivalent to padding of 40px
      minLat -= padding;
      maxLat += padding;
      minLng -= padding;
      maxLng += padding;
      
      // Calculate center
      final centerLat = (minLat + maxLat) / 2;
      final centerLng = (minLng + maxLng) / 2;
      
      // Calculate appropriate zoom level
      // Using log base 2: log2(x) = log(x)/log(2)
      final logBase2 = math.log(2);
      final latZoom = math.log(360 / (maxLat - minLat)) / logBase2;
      final lngZoom = math.log(360 / (maxLng - minLng)) / logBase2;
      double zoom = math.min(math.min(latZoom, lngZoom), 16.0); // base zoom capped at 16
      zoom = math.min(zoom + 0.5, 17.0); // zoom in just slightly but never beyond 17
      
      // Move to this center and zoom
      _controller.move(latlong.LatLng(centerLat, centerLng), zoom);
    } else if (mounted && widget.route.isNotEmpty) {
      // If only one point, center on it with a fixed zoom
      _controller.move(widget.route.last, 17.0);
    }
  }
  
  // Method to just center on last point without zoom changes
  // Animation controller for smooth map movements
  Timer? _animationTimer;
  
  void _centerOnLastPoint() {
    if (mounted && widget.route.isNotEmpty) {
      final currentZoom = _controller.camera.zoom;
      
      // Cancel any existing animation
      _animationTimer?.cancel();
      
      // For small movements (< 10 meters), just move directly to avoid jitter
      final distance = _calculateDistance(
        _controller.camera.center.latitude, 
        _controller.camera.center.longitude,
        widget.route.last.latitude,
        widget.route.last.longitude
      );
      
      if (distance < 10) {
        _controller.move(widget.route.last, currentZoom);
        return;
      }
      
      // For larger movements, animate smoothly
      final startCenter = _controller.camera.center;
      final endCenter = widget.route.last;
      int step = 0;
      const totalSteps = 8;
      
      _animationTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        
        step++;
        final progress = step / totalSteps;
        
        if (step >= totalSteps) {
          _controller.move(endCenter, currentZoom);
          timer.cancel();
        } else {
          final lat = startCenter.latitude + (endCenter.latitude - startCenter.latitude) * progress;
          final lng = startCenter.longitude + (endCenter.longitude - startCenter.longitude) * progress;
          _controller.move(latlong.LatLng(lat, lng), currentZoom);
        }
      });
    }
  }
  
  // Calculate distance between points in meters
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // meters
    final dLat = (lat2 - lat1) * (math.pi / 180);
    final dLon = (lon2 - lon1) * (math.pi / 180);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
             math.cos(lat1 * (math.pi / 180)) * math.cos(lat2 * (math.pi / 180)) *
             math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a));
    return earthRadius * c;
  }
  
  double _toRadians(double degrees) => degrees * math.pi / 180.0;
  
  /// Build a gender-specific map marker based on the user's gender
  Widget _buildGenderSpecificMarker() {
    // Get user gender from AuthBloc if available
    String? userGender;
    try {
      final authBloc = GetIt.instance<AuthBloc>();
      if (authBloc.state is Authenticated) {
        userGender = (authBloc.state as Authenticated).user.gender;
      }
    } catch (e) {
      // If auth bloc is not available, continue with default marker
      debugPrint('Could not get user gender for map marker: $e');
    }
    
    // Determine which marker image to use based on gender
    final String markerImagePath = (userGender == 'female')
        ? 'assets/images/map_marker_lady.png' // Female version
        : 'assets/images/map marker.png'; // Default/male version
    
    return Image.asset(markerImagePath);
  }

  @override
  Widget build(BuildContext context) {
    // Determine initial center for when the map is first built or route is empty.
    final latlong.LatLng initialMapCenter;
    if (widget.initialCenter != null) {
      initialMapCenter = widget.initialCenter!;
    } else if (widget.route.isNotEmpty) {
      initialMapCenter = widget.route.last;
    } else {
      initialMapCenter = latlong.LatLng(48.8566, 2.3522);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16.0),
      child: Stack(
        children: [
          // Placeholder with exact map background color - shown until tiles load
          Positioned.fill(
            child: Container(
              color: const Color(0xFFE8E0D8), // Exact match to Stadia Maps terrain style background
              child: Center(
                child: _tilesLoaded ? null : const CircularProgressIndicator(),
              ),
            ),
          ),
          
          // Invisible until tiles load - prevents blue flash
          Opacity(
            opacity: _tilesLoaded ? 1.0 : 0.0,
            child: FlutterMap(
              mapController: _controller,
              options: MapOptions(
                backgroundColor: const Color(0xFFE8E0D8), // Match Stadia Maps terrain style
                initialCenter: initialMapCenter,
                initialZoom: 16.5,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                ),
                onMapReady: () {
                  print("Map has signaled ready");
                  _signalMapReady();
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tiles.stadiamaps.com/tiles/stamen_terrain/{z}/{x}/{y}{r}.png?api_key=${dotenv.env['STADIA_MAPS_API_KEY']}',
                  userAgentPackageName: 'com.ruckingapp',
                  retinaMode: RetinaMode.isHighDensity(context),
                  tileBuilder: (context, tileWidget, tile) {
                    // Set tiles as loaded on first tile
                    _onTilesLoaded();
                    return tileWidget;
                  },
                ),
                if (widget.route.isNotEmpty || widget.initialCenter != null)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: widget.route.isNotEmpty ? widget.route : [widget.initialCenter!],
                        strokeWidth: 4.0,
                        color: AppColors.secondary, // Changed to orange for better visibility
                      ),
                    ],
                  ),
                if (widget.route.isNotEmpty || widget.initialCenter != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: widget.route.isNotEmpty ? widget.route.last : widget.initialCenter!,
                        width: 40,
                        height: 40,
                        child: _buildGenderSpecificMarker(),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    _animationTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }
}

class _WeightChip extends StatelessWidget {
  const _WeightChip({Key? key, required this.weightKg}) : super(key: key);

  final double weightKg;

  @override
  Widget build(BuildContext context) {
    final authBloc = Provider.of<AuthBloc>(context, listen: false);
    final bool preferMetric = authBloc.state is Authenticated
        ? (authBloc.state as Authenticated).user.preferMetric
        : true;
    final String weightDisplay = weightKg == 0
        ? 'HIKE'
        : (preferMetric ? '${weightKg.toStringAsFixed(1)} kg' : '${(weightKg * 2.20462).toStringAsFixed(1)} lb');
    return Chip(
      backgroundColor: AppColors.secondary,
      label: Text(
        weightDisplay,
        style: AppTextStyles.labelLarge.copyWith(color: Colors.white),
      ),
    );
  }
}

class _PauseOverlay extends StatelessWidget {
  const _PauseOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black45,
        alignment: Alignment.center,
        child: Text(
          'PAUSED',
          style: AppTextStyles.headlineLarge.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// CountdownOverlay has been moved to a dedicated CountdownPage
