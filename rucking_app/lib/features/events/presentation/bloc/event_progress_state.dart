import 'package:equatable/equatable.dart';
import 'package:rucking_app/features/events/domain/models/event_progress.dart';

abstract class EventProgressState extends Equatable {
  const EventProgressState();

  @override
  List<Object?> get props => [];
}

class EventProgressInitial extends EventProgressState {}

class EventLeaderboardLoading extends EventProgressState {
  final String eventId;

  const EventLeaderboardLoading(this.eventId);

  @override
  List<Object?> get props => [eventId];
}

class EventLeaderboardLoaded extends EventProgressState {
  final EventLeaderboard leaderboard;

  const EventLeaderboardLoaded(this.leaderboard);

  @override
  List<Object?> get props => [leaderboard];
}

class EventLeaderboardError extends EventProgressState {
  final String eventId;
  final String message;

  const EventLeaderboardError({
    required this.eventId,
    required this.message,
  });

  @override
  List<Object?> get props => [eventId, message];
}

class UserEventProgressLoading extends EventProgressState {
  final String eventId;
  final String userId;

  const UserEventProgressLoading({
    required this.eventId,
    required this.userId,
  });

  @override
  List<Object?> get props => [eventId, userId];
}

class UserEventProgressLoaded extends EventProgressState {
  final String eventId;
  final String userId;
  final EventProgress? progress;

  const UserEventProgressLoaded({
    required this.eventId,
    required this.userId,
    this.progress,
  });

  @override
  List<Object?> get props => [eventId, userId, progress];
}

class UserEventProgressError extends EventProgressState {
  final String eventId;
  final String userId;
  final String message;

  const UserEventProgressError({
    required this.eventId,
    required this.userId,
    required this.message,
  });

  @override
  List<Object?> get props => [eventId, userId, message];
}
