import 'package:equatable/equatable.dart';
import 'package:rucking_app/features/events/domain/models/event.dart';

abstract class EventsState extends Equatable {
  const EventsState();

  @override
  List<Object?> get props => [];
}

class EventsInitial extends EventsState {}

class EventsLoading extends EventsState {}

class EventsLoaded extends EventsState {
  final List<Event> events;
  final String? searchQuery;
  final String? clubId;
  final String? status;
  final bool? includeParticipating;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool? sortByDistance;

  const EventsLoaded({
    required this.events,
    this.searchQuery,
    this.clubId,
    this.status,
    this.includeParticipating,
    this.startDate,
    this.endDate,
    this.sortByDistance,
  });

  @override
  List<Object?> get props => [
        events,
        searchQuery,
        clubId,
        status,
        includeParticipating,
        startDate,
        endDate,
        sortByDistance,
      ];
}

class EventsError extends EventsState {
  final String message;

  const EventsError(this.message);

  @override
  List<Object?> get props => [message];
}

class EventDetailsLoading extends EventsState {
  final String eventId;

  const EventDetailsLoading(this.eventId);

  @override
  List<Object?> get props => [eventId];
}

class EventDetailsLoaded extends EventsState {
  final EventDetails eventDetails;

  const EventDetailsLoaded(this.eventDetails);

  @override
  List<Object?> get props => [eventDetails];
}

class EventDetailsError extends EventsState {
  final String message;
  final String eventId;

  const EventDetailsError(this.message, this.eventId);

  @override
  List<Object?> get props => [message, eventId];
}

class EventParticipantsLoading extends EventsState {
  final String eventId;

  const EventParticipantsLoading(this.eventId);

  @override
  List<Object?> get props => [eventId];
}

class EventParticipantsLoaded extends EventsState {
  final String eventId;
  final List<EventParticipant> participants;

  const EventParticipantsLoaded({
    required this.eventId,
    required this.participants,
  });

  @override
  List<Object?> get props => [eventId, participants];
}

class EventParticipantsError extends EventsState {
  final String message;
  final String eventId;

  const EventParticipantsError(this.message, this.eventId);

  @override
  List<Object?> get props => [message, eventId];
}

class EventActionLoading extends EventsState {
  final String message;

  const EventActionLoading(this.message);

  @override
  List<Object?> get props => [message];
}

class EventActionSuccess extends EventsState {
  final String message;
  final bool shouldRefresh;
  final String? eventId;
  final String? eventTitle; // For event context navigation
  final String? sessionId; // For StartRuckFromEvent

  const EventActionSuccess(
    this.message, {
    this.shouldRefresh = true,
    this.eventId,
    this.eventTitle,
    this.sessionId,
  });

  @override
  List<Object?> get props => [message, shouldRefresh, eventId, eventTitle, sessionId];
}

class EventActionError extends EventsState {
  final String message;

  const EventActionError(this.message);

  @override
  List<Object?> get props => [message];
}
