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

/// Arguments passed to the ActiveSessionPage
class ActiveSessionArgs {
  final double ruckWeight;
  final String? notes;
  final latlong.LatLng? initialCenter;

  const ActiveSessionArgs({
    required this.ruckWeight,
    this.notes,
    this.initialCenter,
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
      )..add(SessionStarted(ruckWeightKg: args.ruckWeight, notes: args.notes)),
      child: const _ActiveSessionView(),
    );
  }
}

class _ActiveSessionView extends StatelessWidget {
  const _ActiveSessionView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: BlocConsumer<ActiveSessionBloc, ActiveSessionState>(
          listenWhen: (prev, curr) => prev is ActiveSessionFailure != (curr is ActiveSessionFailure),
          listener: (ctx, state) {
            if (state is ActiveSessionFailure) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(content: Text(state.errorMessage)),
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

              return Stack(
                children: [
                  // Map layer
                  Positioned.fill(
                    child: _RouteMap(
                      route: route,
                      initialCenter: (context.findAncestorWidgetOfExactType<ActiveSessionPage>()?.args.initialCenter),
                    ),
                  ),
                  // Stats overlay at the top
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: SessionStatsOverlay(state: state),
                  ),
                  // Validation banner directly below stats
                  const Positioned(
                    top: 80,
                    left: 16,
                    right: 16,
                    child: ValidationBanner(),
                  ),
                  // Control buttons at the bottom
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: const SessionControls(),
                      ),
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
          CircleLayer(
            circles: [
              CircleMarker(
                point: widget.route.last,
                color: AppColors.primary,
                radius: 6,
              ),
            ],
          ),
      ],
    );
  }
}
