import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:rucking_app/shared/widgets/styled_snackbar.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'package:flutter_map/flutter_map.dart';
import '../../../../shared/widgets/map/robust_tile_layer.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:rucking_app/core/utils/measurement_utils.dart';
import 'package:rucking_app/core/models/location_point.dart';
import 'package:rucking_app/core/models/terrain_segment.dart';

import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/location_service.dart';
import 'package:rucking_app/core/services/watch_service.dart';
import 'package:rucking_app/core/services/active_session_storage.dart';
import 'package:rucking_app/core/services/terrain_tracker.dart';
import 'package:rucking_app/core/services/connectivity_service.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/ruck_session/domain/services/heart_rate_service.dart';
import 'package:rucking_app/features/ruck_session/domain/services/split_tracking_service.dart';
import 'package:rucking_app/features/health_integration/domain/health_service.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_session.dart';
import 'package:rucking_app/features/ruck_session/domain/models/session_split.dart';
import 'package:rucking_app/features/ruck_session/data/repositories/session_repository.dart';
import 'package:rucking_app/features/ruck_session/presentation/widgets/session_stats_overlay.dart';
import 'package:rucking_app/features/ruck_session/presentation/widgets/session_controls.dart';
import 'package:rucking_app/features/ruck_session/presentation/widgets/terrain_info_widget.dart';

import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/health_integration/bloc/health_bloc.dart';
import 'package:provider/provider.dart';

/// Arguments passed to the ActiveSessionPage
class ActiveSessionArgs {
  final double ruckWeight;
  final String? notes;
  final int? plannedDuration; // in seconds
  final latlong.LatLng? initialCenter; // Optional initial map center
  final double userWeightKg; // Added user's body weight in kg
  final String? eventId; // Add event ID for event-linked sessions

  ActiveSessionArgs({
    required this.ruckWeight,
    required this.userWeightKg, // Made required
    this.notes,
    this.plannedDuration,
    this.initialCenter,
    this.eventId, // Add eventId parameter
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

    // Get GetIt instance first so it's available regardless of which path we take
    final locator = GetIt.I;
    
    if (existingBloc != null) {
      // Bloc already exists – simply build the view.
      // Also provide HealthBloc for the session complete screen
      return BlocProvider<HealthBloc>(
        create: (_) => HealthBloc(
          healthService: locator<HealthService>(),
          userId: context.read<AuthBloc>().state is Authenticated
            ? (context.read<AuthBloc>().state as Authenticated).user.userId
            : null,
        ),
        child: _ActiveSessionView(args: args),
      );
    }

    // No existing bloc – create a fresh one (e.g. when user lands here
    // directly without going through the countdown page).
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => ActiveSessionBloc(
            apiClient: locator<ApiClient>(),
            locationService: locator<LocationService>(),
            healthService: locator<HealthService>(),
            watchService: locator<WatchService>(),
            heartRateService: locator<HeartRateService>(),
            splitTrackingService: locator<SplitTrackingService>(),
            sessionRepository: locator<SessionRepository>(),
            activeSessionStorage: locator<ActiveSessionStorage>(),
            terrainTracker: locator<TerrainTracker>(),
            connectivityService: locator<ConnectivityService>(),
          ),
        ),
        BlocProvider(
          create: (_) => HealthBloc(
            healthService: locator<HealthService>(),
            userId: context.read<AuthBloc>().state is Authenticated
              ? (context.read<AuthBloc>().state as Authenticated).user.userId
              : null,
          ),
        ),
      ],
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
  bool _terrainExpanded = false; // Changed to false to be collapsed by default
  ActiveSessionRunning? _lastActiveSessionRunning;

  void _checkAnimateOverlay() {
    // No animation needed anymore since we removed the gray overlay
    // This method is kept for compatibility but doesn't do anything
  }
  
  // Helper method to get the appropriate color based on user gender
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
      if (state is ActiveSessionRunning) {
        _lastActiveSessionRunning = state;
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
                    color: _getLadyModeColor(context),
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
                    buildWhen: (previous, current) {
                      // Always rebuild if the type of state changes (e.g., Loading -> Running)
                      if (previous.runtimeType != current.runtimeType) {
                        return true;
                      }
                      // If both are ActiveSessionRunning, check for specific significant changes
                      if (previous is ActiveSessionRunning && current is ActiveSessionRunning) {
                        return previous.isPaused != current.isPaused ||
                            !listEquals(previous.locationPoints, current.locationPoints) || // More robust list comparison
                            previous.distanceKm != current.distanceKm ||
                            previous.pace != current.pace ||
                            previous.calories != current.calories ||
                            previous.elevationGain != current.elevationGain ||
                            previous.elevationLoss != current.elevationLoss ||
                            previous.sessionId != current.sessionId; // Important for initial load
                      }
                      // For other state types or transitions, allow rebuild
                      return true;
                    },
                    listenWhen: (prev, curr) => 
                      (prev is ActiveSessionFailure != curr is ActiveSessionFailure) || 
                      (curr is SessionSummaryGenerated) ||
                      (curr is ActiveSessionRunning && !sessionRunning) ||
                      (prev is! ActiveSessionInitial && curr is ActiveSessionInitial), // Handle transition back to initial (404 case)
                    listener: (context, state) {
                      if (state is ActiveSessionFailure) {
                        StyledSnackBar.showError(
                          context: context,
                          message: state.errorMessage,
                          duration: const Duration(seconds: 3),
                        );
                      } else if (state is ActiveSessionInitial && uiInitialized) {
                        // If we transition back to Initial after UI was initialized, 
                        // it means we need to navigate away (e.g., 404 error case)
                        AppLogger.info('Session returned to Initial state, navigating to homepage');
                        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
                      } else if (state is SessionSummaryGenerated) {
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
                        final splits = state.session.splits;
                        
                        // Debug logging for splits
                        print('[DEBUG] Splits data being passed to session complete:');
                        print('[DEBUG] Splits type: ${splits.runtimeType}');
                        print('[DEBUG] Splits length: ${splits?.length ?? 'null'}');
                        if (splits != null && splits.isNotEmpty) {
                          print('[DEBUG] First split: ${splits.first}');
                          for (int i = 0; i < splits.length; i++) {
                            print('[DEBUG] Split $i: ${splits[i]}');
                          }
                        } else {
                          print('[DEBUG] No splits data available');
                        }
                        
                        // Get terrain segments from the previous running state if available
                        List<TerrainSegment> terrainSegments = [];
                        if (sessionRunning && _lastActiveSessionRunning != null) {
                          terrainSegments = _lastActiveSessionRunning!.terrainSegments;
                        }

                        Navigator.of(context).pushReplacementNamed(
                          '/session_complete',
                          arguments: {
                            'completedAt': endTime,
                            'ruckId': ruckId,
                            'duration': duration,
                            'distance': distance,
                            'caloriesBurned': caloriesBurned,
                            'elevationGain': elevationGain,
                            'elevationLoss': elevationLoss,
                            'ruckWeight': ruckWeightKg, // Changed back to ruckWeight
                            'initialNotes': notes,
                            'heartRateSamples': heartRateSamples,
                            'splits': splits,
                            'terrainSegments': terrainSegments,
                          },
                        );
                      } else if (state is ActiveSessionRunning && !sessionRunning) {
                        setState(() {
                          sessionRunning = true;
                        });
                        // Session just started running - DON'T animate overlay away yet
                        // The countdown completion will trigger this later
                      } else if (state is ActiveSessionRunning 
                                && uiInitialized 
                                && context.read<ActiveSessionBloc>().state is ActiveSessionInitial) {
                        // This case is to handle if the session somehow reverts to Initial AFTER UI is initialized
                        // and a session was running. This might indicate a need to restart the session logic.
                        // This specific log and condition might need review based on actual app flow.
                        AppLogger.warning('Session was running, UI initialized, but BLoC reset to Initial. Re-triggering SessionStarted.');
                        context.read<ActiveSessionBloc>().add(SessionStarted(
                                ruckWeightKg: widget.args.ruckWeight,
                                userWeightKg: widget.args.userWeightKg, // Added missing parameter
                                notes: widget.args.notes,
                                plannedDuration: widget.args.plannedDuration,
                                eventId: widget.args.eventId, // Pass event ID if creating session from event
                                initialLocation: widget.args.initialCenter == null 
                                    ? null 
                                    : LocationPoint(
                                        latitude: widget.args.initialCenter!.latitude,
                                        longitude: widget.args.initialCenter!.longitude,
                                        timestamp: DateTime.now().toUtc(),
                                        elevation: 0.0, // Added default
                                        accuracy: 0.0, // Added default
                                      )
                            ));
                      }
                    },
                    builder: (context, state) {
                      AppLogger.debug('[ActiveSessionPage] BlocConsumer builder rebuilding with state: ${state.runtimeType}');
                      // Add a check for uiInitialized before starting the session
                      // This ensures that the session doesn't start before the UI is ready.
                      if (!uiInitialized && state is ActiveSessionInitial) {
                        // Delay starting the session until after the first frame
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) { // Ensure widget is still mounted
                             AppLogger.info('UI Initialized, starting session with args: ${widget.args.ruckWeight}kg, ${widget.args.plannedDuration}s');
                             context.read<ActiveSessionBloc>().add(SessionStarted(
                                  ruckWeightKg: widget.args.ruckWeight,
                                  userWeightKg: widget.args.userWeightKg,
                                  notes: widget.args.notes,
                                  plannedDuration: widget.args.plannedDuration,
                                  eventId: widget.args.eventId, // Pass event ID if creating session from event
                                  initialLocation: widget.args.initialCenter == null 
                                    ? null 
                                    : LocationPoint(
                                        latitude: widget.args.initialCenter!.latitude,
                                        longitude: widget.args.initialCenter!.longitude,
                                        timestamp: DateTime.now().toUtc(),
                                        elevation: 0.0, // Added default
                                        accuracy: 0.0, // Added default
                                      )
                              ));
                             setState(() {
                               uiInitialized = true; // Mark UI as initialized
                             });
                          }
                        });
                      } else if (state is ActiveSessionRunning && !sessionRunning) {
                        // This case might be redundant if listenWhen handles it, but ensures sessionRunning is set.
                        // Consider if sessionRunning flag logic can be simplified.
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if(mounted) {
                             setState(() {
                              sessionRunning = true;
                            });
                          }
                        });
                      }

                      if (state is ActiveSessionInitial || state is ActiveSessionLoading) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      
                      if (state is ActiveSessionFailure) {
                        // Log the error for debugging
                        AppLogger.error('ActiveSessionFailure displayed to user: ${state.errorMessage} (session: ${state.sessionDetails?.sessionId ?? 'unknown'})');
                        
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.error_outline, size: 64, color: Colors.red),
                              SizedBox(height: 16),
                              Text(
                                'Session Error',
                                style: AppTextStyles.headlineMedium,
                              ),
                              SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                                child: Text(
                                  state.errorMessage,
                                  textAlign: TextAlign.center,
                                  style: AppTextStyles.bodyMedium,
                                ),
                              ),
                              SizedBox(height: 24),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  ElevatedButton(
                                    onPressed: () {
                                      // Try to restart the session
                                      context.read<ActiveSessionBloc>().add(SessionStarted(
                                        ruckWeightKg: widget.args.ruckWeight,
                                        userWeightKg: widget.args.userWeightKg,
                                        notes: widget.args.notes,
                                        plannedDuration: widget.args.plannedDuration,
                                        eventId: widget.args.eventId,
                                        initialLocation: widget.args.initialCenter == null 
                                          ? null 
                                          : LocationPoint(
                                              latitude: widget.args.initialCenter!.latitude,
                                              longitude: widget.args.initialCenter!.longitude,
                                              timestamp: DateTime.now().toUtc(),
                                              elevation: 0.0,
                                              accuracy: 0.0,
                                            )
                                      ));
                                    },
                                    child: Text('Retry'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () {
                                      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.grey,
                                    ),
                                    child: Text('Go Home'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }
                      
                      if (state is ActiveSessionRunning) {
                        // Validate state before rendering to prevent white pages
                        if (state.sessionId.isEmpty) {
                          AppLogger.warning('ActiveSessionRunning state has empty sessionId');
                          return const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 16),
                                Text('Initializing session...'),
                              ],
                            ),
                          );
                        }
                        
                        print('[ACTIVE_SESSION_PAGE] ActiveSessionRunning - building UI');
                        print('[ACTIVE_SESSION_PAGE] Session ID: ${state.sessionId}');
                        print('[ACTIVE_SESSION_PAGE] Terrain segments count: ${state.terrainSegments.length}');
                        if (state.terrainSegments.isEmpty) {
                          print('[ACTIVE_SESSION_PAGE] No terrain segments available yet');
                        }
                        
                        final route = state.locationPoints
                            .map((p) => latlong.LatLng(p.latitude, p.longitude))
                            .toList();

                        return SingleChildScrollView(
                          child: Column(
                            children: [
                              // Map with weight chip overlay
                              Padding(
                                padding: const EdgeInsets.only(top: 4.0, left: 8.0, right: 8.0),
                                child: Builder(
                                  builder: (context) {
                                    // Defensive wrapper to prevent ParentData crashes
                                    return Stack(
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
                                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                                      if (mounted) {
                                                        setState(() {
                                                          mapReady = true;
                                                        });
                                                      }
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
                                    );
                                  },
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
                                    print('[ACTIVE_SESSION_PAGE] BlocBuilder build called with state: ${state.runtimeType}');
                                    if (state is ActiveSessionRunning) {
                                      print('[ACTIVE_SESSION_PAGE] ActiveSessionRunning state - terrainSegments: ${state.terrainSegments.length}');
                                      print('[ACTIVE_SESSION_PAGE] Terrain segments: ${state.terrainSegments.map((s) => s.surfaceType).toList()}');
                                    }
                                    
                                    if (state is ActiveSessionRunning) {
                                      sessionRunning = true;
                                      _checkAnimateOverlay();
                                    }
                                    return AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 300),
                                      child: state is ActiveSessionRunning
                                          ? SessionStatsOverlay(
                                              state: state,
                                              preferMetric: context.read<AuthBloc>().state is Authenticated
                                                  ? (context.read<AuthBloc>().state as Authenticated).user.preferMetric
                                                  : true,
                                              useCardLayout: true,
                                            )
                                          : const Center(child: CircularProgressIndicator()),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 4.0), // Reduced spacing before terrain widget
                              // Terrain Info Widget
                              if (state.terrainSegments.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                  child: TerrainInfoWidget(
                                    terrainSegments: state.terrainSegments,
                                    preferMetric: context.read<AuthBloc>().state is Authenticated
                                        ? (context.read<AuthBloc>().state as Authenticated).user.preferMetric
                                        : true,
                                    isExpanded: _terrainExpanded,
                                    onToggle: () {
                                      print('[ACTIVE_SESSION] TerrainInfoWidget toggle - was expanded: $_terrainExpanded');
                                      setState(() {
                                        _terrainExpanded = !_terrainExpanded;
                                      });
                                      print('[ACTIVE_SESSION] TerrainInfoWidget toggle - now expanded: $_terrainExpanded');
                                    },
                                  ),
                                ),
                              const SizedBox(height: 4.0), // Reduced spacing after terrain widget
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
                                          context.read<ActiveSessionBloc>().add(const SessionResumed(source: SessionActionSource.ui));
                                        } else {
                                          context.read<ActiveSessionBloc>().add(const SessionPaused(source: SessionActionSource.ui));
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
                      
                      if (state is ActiveSessionCompleted) {
                        print('[UI] ActiveSessionCompleted state received: distance=${state.finalDistanceKm}km, duration=${state.finalDurationSeconds}s');
                        return Center(
                          child: Text(
                            'Session Completed — Distance: ${state.finalDistanceKm.toStringAsFixed(2)} km',
                            style: AppTextStyles.titleMedium,
                          ),
                        );
                      }
                      
                      if (state is SessionSummaryGenerated) {
                        // Show loading while navigating to session complete screen
                        return const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text('Completing session...'),
                            ],
                          ),
                        );
                      }
                      
                      if (state is SessionCompletionUploading) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const CircularProgressIndicator(),
                              const SizedBox(height: 24),
                              Text(
                                state.progressMessage,
                                style: AppTextStyles.headlineMedium,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Processing ${state.locationPointsCount} location points\nand ${state.heartRateSamplesCount} heart rate samples',
                                style: AppTextStyles.bodyMedium,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${state.distanceKm.toStringAsFixed(1)} km • ${(state.durationSeconds / 60).toStringAsFixed(0)} min',
                                style: AppTextStyles.bodySmall,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        );
                      }
                      
                      if (state is SessionSummaryGenerated) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const CircularProgressIndicator(),
                              const SizedBox(height: 24),
                              Text(
                                'Completing session...',
                                style: AppTextStyles.headlineMedium,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        );
                      }
                      
                      // Catch-all error handler to prevent blank white screens
                      AppLogger.error('Unknown ActiveSessionState encountered: ${state.runtimeType} - ${state.toString()}');
                      
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.warning_amber_outlined, size: 64, color: Colors.orange),
                            SizedBox(height: 16),
                            Text(
                              'Unexpected State',
                              style: AppTextStyles.headlineMedium,
                            ),
                            SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24.0),
                              child: Text(
                                'The session encountered an unexpected state: ${state.runtimeType}',
                                textAlign: TextAlign.center,
                                style: AppTextStyles.bodyMedium,
                              ),
                            ),
                            SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: () {
                                Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
                              },
                              child: Text('Go Home'),
                            ),
                          ],
                        ),
                      );
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

    // Determine if pace should be shown and is valid
    final bool canShowPace = 
        elapsedSeconds >= minTimeSeconds && 
        distanceKm >= minDistanceKm && 
        pace != null && 
        pace.isFinite && 
        pace > 0 && 
        pace <= 3600; // Corresponds to 60 min/km or 60 min/mi

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Pace', style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        canShowPace
            ? Text(
                MeasurementUtils.formatPace(pace!, metric: preferMetric), // pace is non-null here due to canShowPace check
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _tilesLoaded = true;
          });
        }
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
  Widget _buildGenderSpecificMarker(BuildContext context) {
    // Get user gender from AuthBloc using context
    String? userGender;
    try {
      final authState = context.read<AuthBloc>().state;
      if (authState is Authenticated) {
        userGender = authState.user.gender;
        debugPrint('Map marker detected gender: $userGender');
      }
    } catch (e) {
      // If auth bloc is not available, continue with default marker
      debugPrint('Could not get user gender for map marker: $e');
    }
    
    // Determine which marker image to use based on gender
    final String markerImagePath = (userGender == 'female')
        ? 'assets/images/ladyruckerpin.png' // Female version
        : 'assets/images/map_marker.png'; // Default/male version
    
    debugPrint('Using map marker image path: $markerImagePath');
    
    // Try to load the image asset with error handling
    try {
      return Image.asset(
        markerImagePath,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('Error loading marker image: $error');
          return Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.blue, // Use blue for lady mode as a fallback
            ),
            child: const Icon(Icons.person_pin, color: Colors.white),
          );
        },
      );
    } catch (e) {
      debugPrint('Exception loading marker image: $e');
      return Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.green, // Use green for default mode as a fallback
        ),
        child: const Icon(Icons.person_pin, color: Colors.white),
      );
    }
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
                SafeTileLayer(
                  style: 'stamen_terrain',
                  retinaMode: RetinaMode.isHighDensity(context),
                  onTileLoaded: () {
                    // Set tiles as loaded on first tile
                    _onTilesLoaded();
                  },
                  onTileError: () {
                    AppLogger.warning('Map tile loading error in active session');
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
                        child: _buildGenderSpecificMarker(context),
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
