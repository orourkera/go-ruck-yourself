import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:rucking_app/core/models/location_point.dart';
import 'package:rucking_app/core/services/location_service.dart';
import 'package:rucking_app/features/events/domain/models/event.dart';
import 'package:rucking_app/features/events/domain/repositories/events_repository.dart';
import 'package:rucking_app/features/events/presentation/bloc/events_event.dart';
import 'package:rucking_app/features/events/presentation/bloc/events_state.dart';

class EventsBloc extends Bloc<EventsEvent, EventsState> {
  final EventsRepository _eventsRepository;
  final LocationService _locationService;

  EventsBloc(this._eventsRepository, this._locationService)
      : super(EventsInitial()) {
    on<LoadEvents>(_onLoadEvents);
    on<RefreshEvents>(_onRefreshEvents);
    on<CreateEvent>(_onCreateEvent);
    on<LoadEventDetails>(_onLoadEventDetails);
    on<UpdateEvent>(_onUpdateEvent);
    on<CancelEvent>(_onCancelEvent);
    on<JoinEvent>(_onJoinEvent);
    on<LeaveEvent>(_onLeaveEvent);
    on<LoadEventParticipants>(_onLoadEventParticipants);
    on<ManageEventParticipation>(_onManageEventParticipation);
    on<StartRuckFromEvent>(_onStartRuckFromEvent);
  }

  Future<void> _onLoadEvents(
      LoadEvents event, Emitter<EventsState> emit) async {
    try {
      emit(EventsLoading());

      final events = await _eventsRepository.getEvents(
        search: event.search,
        clubId: event.clubId,
        status: event.status,
        includeParticipating: event.includeParticipating,
        startDate: event.startDate,
        endDate: event.endDate,
      );

      List<Event> sortedEvents = events;

      // If "Near Me" sorting is requested, sort by distance from user location
      if (event.sortByDistance == true) {
        try {
          final userLocation = await _locationService.getCurrentLocation();
          if (userLocation != null) {
            // Separate events with and without location
            final eventsWithLocation = <Event>[];
            final eventsWithoutLocation = <Event>[];

            for (final eventItem in events) {
              if (eventItem.latitude != null && eventItem.longitude != null) {
                eventsWithLocation.add(eventItem);
              } else {
                eventsWithoutLocation.add(eventItem);
              }
            }

            // Sort events with location by distance from user
            eventsWithLocation.sort((a, b) {
              final distanceA = _locationService.calculateDistance(
                userLocation,
                LocationPoint(
                  latitude: a.latitude!,
                  longitude: a.longitude!,
                  elevation: 0.0, // Use default elevation for event locations
                  timestamp: DateTime.now(),
                  accuracy: 0.0, // Use default accuracy for event locations
                ),
              );
              final distanceB = _locationService.calculateDistance(
                userLocation,
                LocationPoint(
                  latitude: b.latitude!,
                  longitude: b.longitude!,
                  elevation: 0.0, // Use default elevation for event locations
                  timestamp: DateTime.now(),
                  accuracy: 0.0, // Use default accuracy for event locations
                ),
              );
              return distanceA.compareTo(distanceB);
            });

            // Combine: nearest events first, then events without location
            sortedEvents = [...eventsWithLocation, ...eventsWithoutLocation];
          }
        } catch (e) {
          debugPrint('Error getting user location for distance sorting: $e');
          // If location fails, keep original event order
        }
      }

      emit(EventsLoaded(
        events: sortedEvents,
        searchQuery: event.search,
        clubId: event.clubId,
        status: event.status,
        includeParticipating: event.includeParticipating,
        startDate: event.startDate,
        endDate: event.endDate,
        sortByDistance: event.sortByDistance,
      ));
    } catch (e) {
      debugPrint('Error loading events: $e');
      emit(EventsError('Failed to load events: ${e.toString()}'));
    }
  }

  Future<void> _onRefreshEvents(
      RefreshEvents event, Emitter<EventsState> emit) async {
    // If we're currently showing loaded events, preserve the filters and refresh
    if (state is EventsLoaded) {
      final currentState = state as EventsLoaded;
      add(LoadEvents(
        search: currentState.searchQuery,
        clubId: currentState.clubId,
        status: currentState.status,
        includeParticipating: currentState.includeParticipating,
        startDate: currentState.startDate,
        endDate: currentState.endDate,
        sortByDistance: currentState.sortByDistance,
      ));
    } else {
      // Otherwise just load events with no filters
      add(const LoadEvents());
    }
  }

  Future<void> _onCreateEvent(
      CreateEvent event, Emitter<EventsState> emit) async {
    try {
      emit(const EventActionLoading('Creating event...'));

      final createdEvent = await _eventsRepository.createEvent(
        title: event.title,
        description: event.description,
        clubId: event.clubId,
        scheduledStartTime: event.scheduledStartTime,
        durationMinutes: event.durationMinutes,
        locationName: event.locationName,
        latitude: event.latitude,
        longitude: event.longitude,
        maxParticipants: event.maxParticipants,
        minParticipants: event.minParticipants,
        approvalRequired: event.approvalRequired,
        difficultyLevel: event.difficultyLevel,
        ruckWeightKg: event.ruckWeightKg,
        bannerImageFile: event.bannerImageFile,
      );

      emit(EventActionSuccess(
        'Event "${createdEvent.title}" created successfully!',
        eventId: createdEvent.id,
      ));
    } catch (e) {
      debugPrint('Error creating event: $e');
      emit(EventActionError('Failed to create event: ${e.toString()}'));
    }
  }

  Future<void> _onLoadEventDetails(
      LoadEventDetails event, Emitter<EventsState> emit) async {
    try {
      emit(EventDetailsLoading(event.eventId));

      final eventDetails =
          await _eventsRepository.getEventDetails(event.eventId);

      emit(EventDetailsLoaded(eventDetails));
    } catch (e) {
      debugPrint('Error loading event details: $e');
      emit(EventDetailsError(
          'Failed to load event details: ${e.toString()}', event.eventId));
    }
  }

  Future<void> _onUpdateEvent(
      UpdateEvent event, Emitter<EventsState> emit) async {
    try {
      emit(const EventActionLoading('Updating event...'));

      final updatedEvent = await _eventsRepository.updateEvent(
        eventId: event.eventId,
        title: event.title,
        description: event.description,
        scheduledStartTime: event.scheduledStartTime,
        durationMinutes: event.durationMinutes,
        locationName: event.locationName,
        latitude: event.latitude,
        longitude: event.longitude,
        maxParticipants: event.maxParticipants,
        minParticipants: event.minParticipants,
        approvalRequired: event.approvalRequired,
        difficultyLevel: event.difficultyLevel,
        ruckWeightKg: event.ruckWeightKg,
        bannerImageFile: event.bannerImageFile,
      );

      emit(EventActionSuccess(
        'Event "${updatedEvent.title}" updated successfully!',
        eventId: updatedEvent.id,
      ));
    } catch (e) {
      debugPrint('Error updating event: $e');
      emit(EventActionError('Failed to update event: ${e.toString()}'));
    }
  }

  Future<void> _onCancelEvent(
      CancelEvent event, Emitter<EventsState> emit) async {
    try {
      emit(const EventActionLoading('Cancelling event...'));

      await _eventsRepository.cancelEvent(event.eventId);

      emit(const EventActionSuccess('Event cancelled successfully!'));
    } catch (e) {
      debugPrint('Error cancelling event: $e');
      emit(EventActionError('Failed to cancel event: ${e.toString()}'));
    }
  }

  Future<void> _onJoinEvent(JoinEvent event, Emitter<EventsState> emit) async {
    try {
      emit(const EventActionLoading('Joining event...'));

      await _eventsRepository.joinEvent(event.eventId);

      emit(EventActionSuccess(
        'Successfully joined event!',
        eventId: event.eventId,
      ));
    } catch (e) {
      debugPrint('Error joining event: $e');
      emit(EventActionError('Failed to join event: ${e.toString()}'));
    }
  }

  Future<void> _onLeaveEvent(
      LeaveEvent event, Emitter<EventsState> emit) async {
    try {
      emit(const EventActionLoading('Leaving event...'));

      await _eventsRepository.leaveEvent(event.eventId);

      emit(EventActionSuccess(
        'Successfully left event!',
        eventId: event.eventId,
      ));
    } catch (e) {
      debugPrint('Error leaving event: $e');
      emit(EventActionError('Failed to leave event: ${e.toString()}'));
    }
  }

  Future<void> _onLoadEventParticipants(
      LoadEventParticipants event, Emitter<EventsState> emit) async {
    try {
      emit(EventParticipantsLoading(event.eventId));

      final participants =
          await _eventsRepository.getEventParticipants(event.eventId);

      emit(EventParticipantsLoaded(
        eventId: event.eventId,
        participants: participants,
      ));
    } catch (e) {
      debugPrint('Error loading event participants: $e');
      emit(EventParticipantsError(
          'Failed to load participants: ${e.toString()}', event.eventId));
    }
  }

  Future<void> _onManageEventParticipation(
      ManageEventParticipation event, Emitter<EventsState> emit) async {
    try {
      emit(const EventActionLoading('Managing participation...'));

      await _eventsRepository.manageParticipation(
        eventId: event.eventId,
        userId: event.userId,
        action: event.action,
      );

      final actionText = event.action == 'approve' ? 'approved' : 'rejected';
      emit(EventActionSuccess(
        'Participation $actionText successfully!',
        eventId: event.eventId,
      ));
    } catch (e) {
      debugPrint('Error managing participation: $e');
      emit(EventActionError('Failed to manage participation: ${e.toString()}'));
    }
  }

  Future<void> _onStartRuckFromEvent(
      StartRuckFromEvent event, Emitter<EventsState> emit) async {
    try {
      emit(const EventActionLoading('Starting ruck session...'));

      final eventContext =
          await _eventsRepository.startRuckFromEvent(event.eventId);

      emit(EventActionSuccess(
        'Ready to start ruck session!',
        eventId: eventContext['event_id'],
        eventTitle: eventContext['event_title'],
        shouldRefresh: false, // Don't refresh events list for this action
      ));
    } catch (e) {
      debugPrint('Error starting ruck from event: $e');
      emit(EventActionError('Failed to start ruck session: ${e.toString()}'));
    }
  }
}
