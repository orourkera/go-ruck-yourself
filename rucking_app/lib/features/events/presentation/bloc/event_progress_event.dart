import 'package:equatable/equatable.dart';

abstract class EventProgressEvent extends Equatable {
  const EventProgressEvent();

  @override
  List<Object?> get props => [];
}

class LoadEventLeaderboard extends EventProgressEvent {
  final String eventId;

  const LoadEventLeaderboard(this.eventId);

  @override
  List<Object?> get props => [eventId];
}

class RefreshEventLeaderboard extends EventProgressEvent {
  final String eventId;

  const RefreshEventLeaderboard(this.eventId);

  @override
  List<Object?> get props => [eventId];
}

class LoadUserEventProgress extends EventProgressEvent {
  final String eventId;
  final String userId;

  const LoadUserEventProgress({
    required this.eventId,
    required this.userId,
  });

  @override
  List<Object?> get props => [eventId, userId];
}
