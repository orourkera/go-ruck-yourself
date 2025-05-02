part of 'session_history_bloc.dart';

abstract class SessionHistoryState extends Equatable {
  const SessionHistoryState();
  
  @override
  List<Object?> get props => [];
}

class SessionHistoryInitial extends SessionHistoryState {}

class SessionHistoryLoading extends SessionHistoryState {}

class SessionHistoryLoaded extends SessionHistoryState {
  final List<RuckSession> sessions;
  
  const SessionHistoryLoaded({required this.sessions});
  
  @override
  List<Object?> get props => [sessions];
}

class SessionHistoryError extends SessionHistoryState {
  final String message;
  
  const SessionHistoryError({required this.message});
  
  @override
  List<Object?> get props => [message];
}
