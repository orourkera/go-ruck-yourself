part of 'session_bloc.dart';

/// Base class for session states
abstract class SessionState extends Equatable {
  const SessionState();

  @override
  List<Object> get props => [];
}

/// Initial state
class SessionInitial extends SessionState {}

/// State for when a session operation is in progress
class SessionOperationInProgress extends SessionState {}

/// State for when session deletion is successful
class SessionDeleteSuccess extends SessionState {
  final String sessionId;
  
  const SessionDeleteSuccess({required this.sessionId});
  
  @override
  List<Object> get props => [sessionId];
}

/// State for when a session operation fails
class SessionOperationFailure extends SessionState {
  final String message;
  
  const SessionOperationFailure({required this.message});
  
  @override
  List<Object> get props => [message];
}
