import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:rucking_app/features/events/domain/repositories/events_repository.dart';
import 'package:rucking_app/features/events/presentation/bloc/event_progress_event.dart';
import 'package:rucking_app/features/events/presentation/bloc/event_progress_state.dart';

class EventProgressBloc extends Bloc<EventProgressEvent, EventProgressState> {
  final EventsRepository _eventsRepository;

  EventProgressBloc(this._eventsRepository) : super(EventProgressInitial()) {
    on<LoadEventLeaderboard>(_onLoadEventLeaderboard);
    on<RefreshEventLeaderboard>(_onRefreshEventLeaderboard);
    on<LoadUserEventProgress>(_onLoadUserEventProgress);
  }

  Future<void> _onLoadEventLeaderboard(
      LoadEventLeaderboard event, Emitter<EventProgressState> emit) async {
    try {
      emit(EventLeaderboardLoading(event.eventId));

      final leaderboard =
          await _eventsRepository.getEventLeaderboard(event.eventId);

      emit(EventLeaderboardLoaded(leaderboard));
    } catch (e) {
      debugPrint('Error loading event leaderboard: $e');

      // Handle 403 (unauthorized) errors with specific message
      String errorMessage;
      if (e.toString().contains('403') ||
          e.toString().toLowerCase().contains('unauthorized')) {
        errorMessage = 'You no longer have access to this event\'s leaderboard';
      } else {
        errorMessage = 'Failed to load leaderboard';
      }

      emit(EventLeaderboardError(
        eventId: event.eventId,
        message: errorMessage,
      ));
    }
  }

  Future<void> _onRefreshEventLeaderboard(
      RefreshEventLeaderboard event, Emitter<EventProgressState> emit) async {
    add(LoadEventLeaderboard(event.eventId));
  }

  Future<void> _onLoadUserEventProgress(
      LoadUserEventProgress event, Emitter<EventProgressState> emit) async {
    try {
      emit(UserEventProgressLoading(
        eventId: event.eventId,
        userId: event.userId,
      ));

      final progress = await _eventsRepository.getUserEventProgress(
        eventId: event.eventId,
        userId: event.userId,
      );

      emit(UserEventProgressLoaded(
        eventId: event.eventId,
        userId: event.userId,
        progress: progress,
      ));
    } catch (e) {
      debugPrint('Error loading user event progress: $e');
      emit(UserEventProgressError(
        eventId: event.eventId,
        userId: event.userId,
        message: 'Failed to load progress: ${e.toString()}',
      ));
    }
  }
}
