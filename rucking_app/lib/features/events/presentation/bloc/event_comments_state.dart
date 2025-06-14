import 'package:equatable/equatable.dart';
import 'package:rucking_app/features/events/domain/models/event_comment.dart';

abstract class EventCommentsState extends Equatable {
  const EventCommentsState();

  @override
  List<Object?> get props => [];
}

class EventCommentsInitial extends EventCommentsState {}

class EventCommentsLoading extends EventCommentsState {
  final String eventId;

  const EventCommentsLoading(this.eventId);

  @override
  List<Object?> get props => [eventId];
}

class EventCommentsLoaded extends EventCommentsState {
  final String eventId;
  final List<EventComment> comments;

  const EventCommentsLoaded({
    required this.eventId,
    required this.comments,
  });

  @override
  List<Object?> get props => [eventId, comments];
}

class EventCommentsError extends EventCommentsState {
  final String eventId;
  final String message;

  const EventCommentsError({
    required this.eventId,
    required this.message,
  });

  @override
  List<Object?> get props => [eventId, message];
}

class EventCommentActionLoading extends EventCommentsState {
  final String eventId;
  final String message;

  const EventCommentActionLoading({
    required this.eventId,
    required this.message,
  });

  @override
  List<Object?> get props => [eventId, message];
}

class EventCommentActionSuccess extends EventCommentsState {
  final String eventId;
  final String message;
  final bool shouldRefresh;

  const EventCommentActionSuccess({
    required this.eventId,
    required this.message,
    this.shouldRefresh = true,
  });

  @override
  List<Object?> get props => [eventId, message, shouldRefresh];
}

class EventCommentActionError extends EventCommentsState {
  final String eventId;
  final String message;

  const EventCommentActionError({
    required this.eventId,
    required this.message,
  });

  @override
  List<Object?> get props => [eventId, message];
}
