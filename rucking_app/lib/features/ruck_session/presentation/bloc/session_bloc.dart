import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/ruck_session/data/repositories/session_repository.dart';

part 'session_event.dart';
part 'session_state.dart';

/// BLoC for managing ruck session operations
class SessionBloc extends Bloc<SessionEvent, SessionState> {
  final SessionRepository sessionRepository;

  SessionBloc({required this.sessionRepository}) : super(SessionInitial()) {
    on<DeleteSessionEvent>(_onDeleteSession);
  }

  Future<void> _onDeleteSession(
    DeleteSessionEvent event,
    Emitter<SessionState> emit,
  ) async {
    try {
      emit(SessionOperationInProgress());

      final success = await sessionRepository.deleteSession(event.sessionId);

      if (success) {
        emit(SessionDeleteSuccess(sessionId: event.sessionId));
      } else {
        emit(const SessionOperationFailure(
          message: 'Failed to delete session. Please try again.',
        ));
      }
    } catch (e) {
      AppLogger.error('Error deleting session: $e');
      
      // Check if this is a 404 error indicating session doesn't exist in backend
      if (e.toString().contains('404') || 
          e.toString().contains('Session not found') ||
          e.toString().contains('NotFoundException')) {
        AppLogger.warning('Session ${event.sessionId} not found in backend - treating as successful deletion');
        emit(SessionDeleteSuccess(sessionId: event.sessionId));
      } else {
        emit(SessionOperationFailure(
          message: 'Error deleting session: $e',
        ));
      }
    }
  }
}
