import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/location_service.dart';
import 'package:rucking_app/core/services/session_completion_detection_service.dart';
import 'package:rucking_app/core/services/watch_service.dart';
import 'package:rucking_app/core/services/active_session_storage.dart';
import 'package:rucking_app/core/services/terrain_tracker.dart';
import 'package:rucking_app/features/health_integration/domain/health_service.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';
import 'package:rucking_app/features/ruck_session/data/repositories/session_repository.dart';
import 'package:rucking_app/features/ruck_session/domain/services/heart_rate_service.dart';
import 'package:rucking_app/features/ruck_session/domain/services/split_tracking_service.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/active_session_page.dart';
import 'package:rucking_app/core/services/connectivity_service.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/ai_cheerleader/services/ai_cheerleader_service.dart';
import 'package:rucking_app/features/ai_cheerleader/services/openai_service.dart';
import 'package:rucking_app/features/ai_cheerleader/services/elevenlabs_service.dart';
import 'package:rucking_app/features/ai_cheerleader/services/location_context_service.dart';
import 'package:rucking_app/features/ai_cheerleader/services/ai_audio_service.dart';

class InstantStartPage extends StatefulWidget {
  final ActiveSessionArgs args;
  const InstantStartPage({super.key, required this.args});

  @override
  State<InstantStartPage> createState() => _InstantStartPageState();
}

class _InstantStartPageState extends State<InstantStartPage> {
  late ActiveSessionBloc _sessionBloc;
  StreamSubscription? _sub;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    final locator = GetIt.instance;
    _sessionBloc = ActiveSessionBloc(
      apiClient: locator<ApiClient>(),
      locationService: locator<LocationService>(),
      healthService: locator<HealthService>(),
      completionDetectionService: locator<SessionCompletionDetectionService>(),
      watchService: locator<WatchService>(),
      heartRateService: locator<HeartRateService>(),
      splitTrackingService: locator<SplitTrackingService>(),
      terrainTracker: locator<TerrainTracker>(),
      sessionRepository: locator<SessionRepository>(),
      activeSessionStorage: locator<ActiveSessionStorage>(),
      connectivityService: locator<ConnectivityService>(),
      aiCheerleaderService: locator<AICheerleaderService>(),
      openAIService: locator<OpenAIService>(),
      elevenLabsService: locator<ElevenLabsService>(),
      locationContextService: locator<LocationContextService>(),
      audioService: locator<AIAudioService>(),
    );

    // Kick off the session immediately
    _sessionBloc.add(SessionStarted(
      ruckWeightKg: widget.args.ruckWeight,
      userWeightKg: widget.args.userWeightKg,
      notes: widget.args.notes ?? '',
      plannedDuration: widget.args.plannedDuration,
      eventId: widget.args.eventId,
      plannedRoute: widget.args.plannedRoute,
      plannedRouteDistance: widget.args.plannedRouteDistance,
      plannedRouteDuration: widget.args.plannedRouteDuration,
      aiCheerleaderEnabled: widget.args.aiCheerleaderEnabled,
      aiCheerleaderPersonality: widget.args.aiCheerleaderPersonality,
      aiCheerleaderExplicitContent: widget.args.aiCheerleaderExplicitContent,
    ));

    _sub = _sessionBloc.stream.listen((state) {
      if (_navigated) return;
      if (state is ActiveSessionRunning) {
        _navigate();
      }
    });

    // Failsafe: navigate after 2.5s even if state not received yet
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (!_navigated && mounted) {
        AppLogger.warning('[INSTANT_START] Timeout reached, navigating');
        _navigate();
      }
    });
  }

  void _navigate() {
    if (!mounted) return;
    _navigated = true;
    _sessionBloc.add(const TimerStarted());
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: _sessionBloc,
          child: ActiveSessionPage(args: widget.args),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
