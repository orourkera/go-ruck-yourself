import 'dart:async';
import 'package:flutter/material.dart';
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
import 'package:rucking_app/features/ruck_session/domain/services/session_validation_service.dart';
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
  bool countdownComplete = false;
  bool mapReady = false;
  bool sessionRunning = false;

  @override
  void initState() {
    super.initState();
  }

  void _handleEndSession(BuildContext context, ActiveSessionRunning currentState) {
    // Use the SessionValidationService to check all requirements
    final validator = SessionValidationService();
    final validation = validator.validateSessionForSave(
      distanceMeters: currentState.distanceKm * 1000,
      duration: Duration(seconds: currentState.elapsedSeconds),
      caloriesBurned: currentState.calories.toDouble(),
    );
    if (validation['isValid'] == true) {
      _showConfirmEndSessionDialog(context, currentState);
    } else {
      _showSessionTooShortDialog(context);
    }
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

  void _showSessionTooShortDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        // Retrieve provider data safely inside the build method
        final authBloc = Provider.of<AuthBloc>(dialogContext, listen: false);
        final bool preferMetric = authBloc.state is Authenticated
            ? (authBloc.state as Authenticated).user.preferMetric
            : true;
        
        return AlertDialog(
          title: const Text('Session Too Short, Rucker.'),
          content: const Text('Your session did not accumulate enough data to be saved.'),
          actions: [
            TextButton(
              onPressed: () {
                // Discard Session: pop all the way to home
                Navigator.of(dialogContext).popUntil((route) => route.isFirst);
              },
              child: const Text(
                'Discard Session',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w300,
                  fontSize: 16,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                // Keep Rucking: just close the dialog
                Navigator.of(dialogContext).pop();
              },
              child: const Text(
                'Keep Rucking',
                style: TextStyle(
                  color: Color(0xFFB86F1B), // Optional: match your accent color
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final overlayVisible = !(countdownComplete && mapReady && sessionRunning);

    return Scaffold(
      body: Stack(
        children: [
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
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text(state.errorMessage)),
                        );
                      } else if (state is ActiveSessionComplete) {
                        Navigator.of(ctx).pushReplacementNamed(
                          '/session_complete',
                          arguments: {
                            'endTime': state.session.endTime,
                            'ruckId': state.session.id,
                            'duration': state.session.duration,
                            'distance': state.session.distance,
                            'caloriesBurned': state.session.caloriesBurned,
                            'elevationGain': state.session.elevationGain,
                            'elevationLoss': state.session.elevationLoss,
                            'ruckWeightKg': state.session.ruckWeightKg,
                            'notes': state.session.notes,
                            'heartRateSamples': state.session.heartRateSamples,
                          },
                        );
                      } else if (state is ActiveSessionRunning && !sessionRunning) {
                        setState(() {
                          sessionRunning = true;
                        });
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
                                        child: _RouteMap(
                                          route: route,
                                          initialCenter: (context.findAncestorWidgetOfExactType<ActiveSessionPage>()?.args.initialCenter),
                                          onMapReady: () {
                                            if (!mapReady) {
                                              setState(() {
                                                mapReady = true;
                                              });
                                            }
                                          },
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 12,
                                      right: 12,
                                      child: _WeightChip(weightKg: state.ruckWeightKg),
                                    ),
                                    if (state.isPaused)
                                      const Positioned.fill(child: _PauseOverlay()),
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
                                child: SessionControls(
                                  isPaused: state.isPaused,
                                  onTogglePause: () {
                                    if (state.isPaused) {
                                      context.read<ActiveSessionBloc>().add(const SessionResumed());
                                    } else {
                                      context.read<ActiveSessionBloc>().add(const SessionPaused());
                                    }
                                  },
                                  onEndSession: () => _handleEndSession(context, state),
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
          // Overlay
          if (overlayVisible)
            Positioned.fill(
              child: Container(
                color: AppColors.primary,
                child: (!countdownComplete)
                    ? CountdownOverlay(
                        onCountdownComplete: () {
                          setState(() {
                            countdownComplete = true;
                          });
                          context.read<ActiveSessionBloc>().add(
                            SessionStarted(
                              ruckWeightKg: widget.args.ruckWeight,
                              notes: widget.args.notes,
                              plannedDuration: widget.args.plannedDuration,
                            ),
                          );
                        },
                      )
                    : const SizedBox.shrink(),
              ),
            ),
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
    
    final pace = state is ActiveSessionRunning ? (state as ActiveSessionRunning).pace : null;
    // 60 min/km = 3600 seconds/km (or seconds/mi)
    final bool paceTooHigh = pace != null && pace > 3600;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Pace', style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        pace == null || paceTooHigh
            ? const Text('--', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))
            : Text(
                MeasurementUtils.formatPace(pace, metric: preferMetric),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
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
  void _signalMapReady() {
    if (!_mapReadyCalled && widget.onMapReady != null) {
      _mapReadyCalled = true;
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) widget.onMapReady!();
      });
    }
  }
  Timer? _fallbackTimer;
  final MapController _controller = MapController();

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
  void didUpdateWidget(covariant _RouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.route.isNotEmpty && widget.route != oldWidget.route) {
      // Use a microtask to ensure that mapController is ready and avoid conflicts
      // if FlutterMap is rebuilding.
      Future.microtask(() => _fitBoundsToRoute());
    }
  }

  void _fitBoundsToRoute() {
    if (mounted && widget.route.length > 1) {
      final bounds = LatLngBounds.fromPoints(widget.route);
      _controller.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(40.0),
        ),
      );
    } else if (mounted && widget.route.isNotEmpty) {
      // If only one point, center on it with a fixed zoom
      _controller.move(widget.route.last, 16.5);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine initial center for when the map is first built or route is empty.
    // If fitBounds is called, this initialCenter will be overridden.
    final latlong.LatLng initialMapCenter = widget.route.isNotEmpty
        ? widget.route.last
        : (widget.initialCenter ?? latlong.LatLng(0, 0));

    return Stack(
      children: [
        Container(
          color: AppColors.primary,
          child: FlutterMap(
            mapController: _controller,
            options: MapOptions(
              initialCenter: initialMapCenter,
              initialZoom: 16.5,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tiles.stadiamaps.com/tiles/stamen_terrain/{z}/{x}/{y}{r}.png?api_key=${dotenv.env['STADIA_MAPS_API_KEY']}',
                userAgentPackageName: 'com.ruckingapp',
                retinaMode: RetinaMode.isHighDensity(context),
                tileBuilder: (context, tileWidget, tile) {
                  // Call onMapReady the first time a tile is built
                  if (!_mapReadyCalled) {
                    print("Tile loaded: triggering onMapReady (delayed)");
                    _signalMapReady();
                  }
                  return tileWidget;
                },
              ),
              if (widget.route.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: widget.route,
                      strokeWidth: 4.0,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              if (widget.route.isNotEmpty)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: widget.route.last,
                      width: 40,
                      height: 40,
                      child: Image.asset('assets/images/map marker.png'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
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
    final String weightDisplay = preferMetric ? '${weightKg.toStringAsFixed(0)} kg' : '${(weightKg * 2.20462).toStringAsFixed(0)} lb';
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

class CountdownOverlay extends StatefulWidget {
  final VoidCallback? onCountdownComplete;
  const CountdownOverlay({Key? key, this.onCountdownComplete}) : super(key: key);

  @override
  _CountdownOverlayState createState() => _CountdownOverlayState();
}

class _CountdownOverlayState extends State<CountdownOverlay> with SingleTickerProviderStateMixin {
  int _count = 3;
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1));
    _opacityAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(_controller);
    _startCountdown();
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_count > 1) {
        setState(() {
          _count--;
        });
        _controller.forward(from: 0.0);
      } else {
        // Wait a full second before hiding overlay
        Future.delayed(const Duration(seconds: 1), () {
          setState(() {
            _count = 0;
          });
          if (widget.onCountdownComplete != null) {
            widget.onCountdownComplete!();
          }
        });
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_count == 0) return const SizedBox.shrink();
    return Positioned.fill(
      child: Container(
        color: AppColors.primary,
        child: Center(
          child: FadeTransition(
            opacity: _opacityAnimation,
            child: Text(
              _count.toString(),
              style: const TextStyle(
                fontSize: 96,
                color: Colors.white,
                fontFamily: 'Bangers',
                fontWeight: FontWeight.normal,
                letterSpacing: 2.0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
