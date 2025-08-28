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
  final bool hasMoreData;
  final bool isLoadingMore;
  
  const SessionHistoryLoaded({
    required this.sessions,
    this.hasMoreData = true,
    this.isLoadingMore = false,
  });
  
  @override
  List<Object?> get props => [sessions, hasMoreData, isLoadingMore];
  
  SessionHistoryLoaded copyWith({
    List<RuckSession>? sessions,
    bool? hasMoreData,
    bool? isLoadingMore,
  }) {
    return SessionHistoryLoaded(
      sessions: sessions ?? this.sessions,
      hasMoreData: hasMoreData ?? this.hasMoreData,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

class SessionHistoryError extends SessionHistoryState {
  final String message;
  
  const SessionHistoryError({required this.message});
  
  @override
  List<Object?> get props => [message];
}
