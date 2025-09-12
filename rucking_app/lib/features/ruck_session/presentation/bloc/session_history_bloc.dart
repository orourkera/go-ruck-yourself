import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/services/app_error_handler.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_session.dart';
import 'package:rucking_app/features/ruck_session/data/repositories/session_repository.dart';

part 'session_history_event.dart';
part 'session_history_state.dart';

class SessionHistoryBloc
    extends Bloc<SessionHistoryEvent, SessionHistoryState> {
  final SessionRepository _sessionRepository;
  static const int _pageSize = 50;

  SessionHistoryBloc({required SessionRepository sessionRepository})
      : _sessionRepository = sessionRepository,
        super(SessionHistoryInitial()) {
    on<LoadSessionHistory>(_onLoadSessionHistory);
    on<FilterSessionHistory>(_onFilterSessionHistory);
  }

  Future<void> _onLoadSessionHistory(
      LoadSessionHistory event, Emitter<SessionHistoryState> emit) async {
    // Determine date filters based on the filter type
    DateTime? startDate;
    DateTime? endDate;

    if (event.filter != null) {
      switch (event.filter) {
        case SessionFilter.thisWeek:
          final now = DateTime.now();
          final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
          startDate =
              DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
          break;
        case SessionFilter.thisMonth:
          final now = DateTime.now();
          startDate = DateTime(now.year, now.month, 1);
          break;
        case SessionFilter.lastMonth:
          final now = DateTime.now();
          startDate = DateTime(now.year, now.month - 1, 1);
          endDate = DateTime(now.year, now.month, 0);
          break;
        case SessionFilter.custom:
          startDate = event.customStartDate;
          endDate = event.customEndDate;
          break;
        case SessionFilter.all:
        default:
          // No date filters for "all" sessions
          break;
      }
    }

    try {
      if (event.loadMore) {
        // Load more sessions - append to existing list
        final currentState = state;
        if (currentState is SessionHistoryLoaded &&
            !currentState.isLoadingMore) {
          emit(currentState.copyWith(isLoadingMore: true));

          final offset = currentState.sessions.length;
          final newSessions = await _sessionRepository.fetchSessionHistory(
            startDate: startDate,
            endDate: endDate,
            limit: _pageSize,
            offset: offset,
          );

          AppLogger.info(
              '[SESSION_HISTORY_BLOC] Loaded ${newSessions.length} more sessions (offset: $offset)');

          final allSessions = [...currentState.sessions, ...newSessions];
          final hasMoreData = newSessions.length == _pageSize;

          emit(SessionHistoryLoaded(
            sessions: allSessions,
            hasMoreData: hasMoreData,
            isLoadingMore: false,
          ));
        }
      } else {
        // Initial load or refresh
        emit(SessionHistoryLoading());

        final sessions = await _sessionRepository.fetchSessionHistory(
          startDate: startDate,
          endDate: endDate,
          limit: _pageSize,
          offset: 0,
        );

        AppLogger.info(
            '[SESSION_HISTORY_BLOC] Fetched ${sessions.length} sessions from repository');
        if (sessions.isNotEmpty) {
          AppLogger.info(
              '[SESSION_HISTORY_BLOC] First session: id=${sessions.first.id}, status=${sessions.first.status}, distance=${sessions.first.distance}km');
        } else {
          AppLogger.warning(
              '[SESSION_HISTORY_BLOC] No sessions returned - history will be empty');
        }

        final hasMoreData = sessions.length == _pageSize;
        emit(SessionHistoryLoaded(
          sessions: sessions,
          hasMoreData: hasMoreData,
          isLoadingMore: false,
        ));
      }
    } catch (e) {
      // Enhanced error handling with Sentry
      await AppErrorHandler.handleError(
        'session_history_load',
        e,
        context: {
          'filter': event.filter?.toString(),
          'has_start_date': startDate != null,
          'has_end_date': endDate != null,
          'load_more': event.loadMore,
        },
        userId: await _sessionRepository.getCurrentUserId(),
        sendToBackend: true,
      );

      emit(SessionHistoryError(message: e.toString()));
    }
  }

  Future<void> _onFilterSessionHistory(
      FilterSessionHistory event, Emitter<SessionHistoryState> emit) async {
    // Simply call LoadSessionHistory with the filter
    add(LoadSessionHistory(filter: event.filter));
  }
}
