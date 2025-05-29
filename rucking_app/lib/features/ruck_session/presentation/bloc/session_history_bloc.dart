import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_session.dart';
import 'package:rucking_app/features/ruck_session/data/repositories/session_repository.dart';

part 'session_history_event.dart';
part 'session_history_state.dart';

class SessionHistoryBloc extends Bloc<SessionHistoryEvent, SessionHistoryState> {
  final SessionRepository _sessionRepository;
  
  SessionHistoryBloc({required SessionRepository sessionRepository}) 
      : _sessionRepository = sessionRepository,
        super(SessionHistoryInitial()) {
    on<LoadSessionHistory>(_onLoadSessionHistory);
    on<FilterSessionHistory>(_onFilterSessionHistory);
  }
  
  Future<void> _onLoadSessionHistory(
    LoadSessionHistory event, 
    Emitter<SessionHistoryState> emit
  ) async {
    emit(SessionHistoryLoading());
    
    try {
      // Determine date filters based on the filter type
      DateTime? startDate;
      DateTime? endDate;
      
      if (event.filter != null) {
        switch (event.filter) {
          case SessionFilter.thisWeek:
            final now = DateTime.now();
            final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
            startDate = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
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
      
      // Use the cached repository method
      final sessions = await _sessionRepository.fetchSessionHistory(
        startDate: startDate,
        endDate: endDate,
      );
      
      emit(SessionHistoryLoaded(sessions: sessions));
    } catch (e) {
      AppLogger.error('Error fetching sessions: $e');
      emit(SessionHistoryError(message: e.toString()));
    }
  }
  
  Future<void> _onFilterSessionHistory(
    FilterSessionHistory event, 
    Emitter<SessionHistoryState> emit
  ) async {
    // Simply call LoadSessionHistory with the filter
    add(LoadSessionHistory(filter: event.filter));
  }
}
