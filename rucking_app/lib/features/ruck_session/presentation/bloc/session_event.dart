part of 'session_bloc.dart';

/// Base class for session events
abstract class SessionEvent extends Equatable {
  const SessionEvent();

  @override
  List<Object> get props => [];
}

/// Event for deleting a session
class DeleteSessionEvent extends SessionEvent {
  final String sessionId;
  
  const DeleteSessionEvent({required this.sessionId});
  
  @override
  List<Object> get props => [sessionId];
}
