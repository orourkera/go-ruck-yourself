import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/location_service.dart';
import 'package:rucking_app/core/services/watch_service.dart';
import 'package:rucking_app/features/health_integration/domain/health_service.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';
import 'package:rucking_app/features/ruck_session/presentation/widgets/session_stats_overlay.dart';
import 'package:rucking_app/features/ruck_session/presentation/widgets/session_controls.dart';
import 'package:rucking_app/features/ruck_session/presentation/widgets/validation_banner.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';

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
      )..add(SessionStarted(ruckWeightKg: args.ruckWeight, notes: args.notes, plannedDuration: args.plannedDuration)),

      child: const _ActiveSessionView(),
    );
  }
}

class _ActiveSessionView extends StatefulWidget {
  const _ActiveSessionView();

  @override
  State<_ActiveSessionView> createState() => _ActiveSessionViewState();
}

class _ActiveSessionViewState extends State<_ActiveSessionView> {
  void _handleEndSession(BuildContext context, ActiveSessionRunning currentState) {
    if (currentState.isLongEnough) {
      _showConfirmEndSessionDialog(context);
    } else {
      _showSessionTooShortDialog(context);
    }
  }

  void _showConfirmEndSessionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('End Session?'),
          content: const Text('Are you sure you want to end this ruck session?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            TextButton(
              child: const Text('End Session'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                context.read<ActiveSessionBloc>().add(const SessionCompleted());
              },
            ),
          ],
        );
      },
    );
  }

  void _showSessionTooShortDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Session Too Short'),
          content: const Text('This session is very short. Are you sure you want to end it and save? Alternatively, you can discard it.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Discard Session'),
              onPressed: () {
                Navigator.of(dialogContext).pop(); // Dismiss dialog
                // Navigate to home/root screen
                Navigator.of(context).popUntil((route) => route.isFirst);
                // Still tell BLoC to clean up its "running" state
                context.read<ActiveSessionBloc>().add(const SessionCompleted());
              },
            ),
            TextButton(
              child: const Text('Save Anyway'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                context.read<ActiveSessionBloc>().add(const SessionCompleted());
              },
            ),
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
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
                  (curr is ActiveSessionSuccess), 
                listener: (ctx, state) {
                  if (state is ActiveSessionFailure) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text(state.errorMessage)),
                    );
                  } else if (state is ActiveSessionSuccess) {
                    Navigator.of(ctx).pushReplacementNamed(
                      '/session-complete', 
                      arguments: state.sessionId, 
                    );
                  }
                },
                buildWhen: (prev, curr) => prev != curr,
                builder: (ctx, state) {
                  if (state is ActiveSessionInitial || state is ActiveSessionLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (state is ActiveSessionRunning) {
                    final route = state.locationPoints
                        .map((p) => latlong.LatLng(p.latitude, p.longitude))
                        .toList();

                    return Column(
                      children: [
                        // Map with weight chip overlay
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
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
                        // Stats overlay or spinner
                        if (state.locationPoints.length < 2)
                          const Padding(
                            padding: EdgeInsets.only(top: 0.0),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else
                          BlocBuilder<ActiveSessionBloc, ActiveSessionState>(
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
                              if (state is! ActiveSessionRunning) return const SizedBox.shrink();
                              final preferMetric = context.select<AuthBloc, bool>((bloc) {
                                final authState = bloc.state;
                                if (authState is Authenticated) return authState.user.preferMetric;
                                return true;
                              });
                              return SessionStatsOverlay(
                                state: state,
                                preferMetric: preferMetric,
                                useCardLayout: true,
                              );
                            },
                          ),
                        // Validation banner
                        const Padding(
                          padding: EdgeInsets.only(top: 8.0, left: 16.0, right: 16.0),
                          child: ValidationBanner(),
                        ),
                        const Spacer(),
                        // Controls at bottom
                        Padding(
                          padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 18.0, top: 8.0),
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
                      ],
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
    );
  }
}

/// Real map – replace with FlutterMap or GoogleMap.
class _RouteMap extends StatefulWidget {
  const _RouteMap({required this.route, this.initialCenter});

  final List<latlong.LatLng> route;
  final latlong.LatLng? initialCenter;

  @override
  State<_RouteMap> createState() => _RouteMapState();
}

class _RouteMapState extends State<_RouteMap> {
  late final MapController _controller;

  @override
  void initState() {
    super.initState();
    _controller = MapController();
  }

  @override
  void didUpdateWidget(covariant _RouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.route.isNotEmpty) {
      final latest = widget.route.last;
      final prevLatest = oldWidget.route.isNotEmpty ? oldWidget.route.last : null;
      if (prevLatest == null || (latest.latitude != prevLatest.latitude || latest.longitude != prevLatest.longitude)) {
        // Move map center smoothly to latest position
        final currentZoom = _controller.camera.zoom;
        _controller.move(latest, currentZoom);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final center = widget.route.isNotEmpty
        ? widget.route.last
        : (widget.initialCenter ?? latlong.LatLng(0, 0));

    return FlutterMap(
      mapController: _controller,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 15,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://tiles.stadiamaps.com/tiles/stamen_terrain/{z}/{x}/{y}{r}.png?api_key=${dotenv.env['STADIA_MAPS_API_KEY']}',
          userAgentPackageName: 'com.ruckingapp',
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
    );
  }
}

class _WeightChip extends StatelessWidget {
  const _WeightChip({required this.weightKg});

  final double weightKg;

  @override
  Widget build(BuildContext context) {
    final preferMetric = context.select<AuthBloc, bool>((bloc) {
      final st = bloc.state;
      if (st is Authenticated) return st.user.preferMetric;
      return true;
    });

    final display = preferMetric
        ? '${weightKg.toStringAsFixed(0)} kg'
        : '${(weightKg * 2.20462).toStringAsFixed(0)} lb';
    return Chip(
      backgroundColor: AppColors.secondary,
      label: Text(
        display,
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
