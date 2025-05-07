import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/location_service.dart';
import 'package:rucking_app/features/health_integration/domain/health_service.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';

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
              return Column(
                children: [
                  _StatsHeader(state: state),
                  Expanded(
                    child: _RouteMap(
                      route: state.locationPoints
                          .map((p) => latlong.LatLng(p.latitude, p.longitude))
                          .toList(),
                      initialCenter: (context.findAncestorWidgetOfExactType<ActiveSessionPage>()?.args.initialCenter),
                    ),
                  ),
                  _SessionControls(state: state),
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

/// Very basic stats header – shows distance, elapsed, pace.
class _StatsHeader extends StatelessWidget {
  const _StatsHeader({required this.state});

  final ActiveSessionRunning state;

  String _format(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _StatTile(label: 'DIST', value: '${state.distanceKm.toStringAsFixed(2)} km'),
          _StatTile(label: 'PACE', value: state.pace.toStringAsFixed(1)),
          _StatTile(label: 'TIME', value: _format(Duration(seconds: state.elapsedSeconds))),
          if (state.latestHeartRate != null)
            _StatTile(label: 'HR', value: '${state.latestHeartRate} bpm'),
          _StatTile(label: 'CAL', value: state.calories.toStringAsFixed(0)),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary)),
        const SizedBox(height: 4),
        Text(value, style: AppTextStyles.titleLarge),
      ],
    );
  }
}

/// Real map – replace with FlutterMap or GoogleMap.
class _RouteMap extends StatelessWidget {
  const _RouteMap({required this.route, this.initialCenter});

  final List<latlong.LatLng> route;
  final latlong.LatLng? initialCenter;

  @override
  Widget build(BuildContext context) {
    final center = route.isNotEmpty
        ? route.last
        : (initialCenter ?? latlong.LatLng(0, 0));

    return FlutterMap(
      options: MapOptions(
        center: center,
        zoom: 15,
        interactiveFlags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://tiles.stadiamaps.com/tiles/stamen_terrain/{z}/{x}/{y}{r}.png?api_key=${dotenv.env['STADIA_MAPS_API_KEY']}',
          userAgentPackageName: 'com.ruckingapp',
        ),
        if (route.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: route,
                strokeWidth: 4.0,
                color: AppColors.primary,
              ),
            ],
          ),
        if (route.isNotEmpty)
          CircleLayer(
            circles: [
              CircleMarker(
                point: route.last,
                color: AppColors.primary,
                radius: 6,
              ),
            ],
          ),
      ],
    );
  }
}

class _SessionControls extends StatelessWidget {
  const _SessionControls({required this.state});

  final ActiveSessionRunning state;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<ActiveSessionBloc>();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                if (state.isPaused) {
                  bloc.add(SessionResumed());
                } else {
                  bloc.add(SessionPaused());
                }
              },
              child: Text(state.isPaused ? 'RESUME' : 'PAUSE'),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton(
              onPressed: () => bloc.add(const SessionCompleted()),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('END'),
            ),
          ),
        ],
      ),
    );
  }
}
