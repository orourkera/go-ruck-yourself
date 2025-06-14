import 'package:equatable/equatable.dart';

abstract class EventCommentsEvent extends Equatable {
  const EventCommentsEvent();

  @override
  List<Object?> get props => [];
}

class LoadEventComments extends EventCommentsEvent {
  final String eventId;

  const LoadEventComments(this.eventId);

  @override
  List<Object?> get props => [eventId];
}

class RefreshEventComments extends EventCommentsEvent {
  final String eventId;

  const RefreshEventComments(this.eventId);

  @override
  List<Object?> get props => [eventId];
}

class AddEventComment extends EventCommentsEvent {
  final String eventId;
  final String comment;

  const AddEventComment({
    required this.eventId,
    required this.comment,
  });

  @override
  List<Object?> get props => [eventId, comment];
}

class UpdateEventComment extends EventCommentsEvent {
  final String eventId;
  final String commentId;
  final String comment;

  const UpdateEventComment({
    required this.eventId,
    required this.commentId,
    required this.comment,
  });

  @override
  List<Object?> get props => [eventId, commentId, comment];
}

class DeleteEventComment extends EventCommentsEvent {
  final String eventId;
  final String commentId;

  const DeleteEventComment({
    required this.eventId,
    required this.commentId,
  });

  @override
  List<Object?> get props => [eventId, commentId];
}
