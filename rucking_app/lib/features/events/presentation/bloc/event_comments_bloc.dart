import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:rucking_app/features/events/domain/repositories/events_repository.dart';
import 'package:rucking_app/features/events/presentation/bloc/event_comments_event.dart';
import 'package:rucking_app/features/events/presentation/bloc/event_comments_state.dart';

class EventCommentsBloc extends Bloc<EventCommentsEvent, EventCommentsState> {
  final EventsRepository _eventsRepository;

  EventCommentsBloc(this._eventsRepository) : super(EventCommentsInitial()) {
    on<LoadEventComments>(_onLoadEventComments);
    on<RefreshEventComments>(_onRefreshEventComments);
    on<AddEventComment>(_onAddEventComment);
    on<UpdateEventComment>(_onUpdateEventComment);
    on<DeleteEventComment>(_onDeleteEventComment);
  }

  Future<void> _onLoadEventComments(LoadEventComments event, Emitter<EventCommentsState> emit) async {
    try {
      emit(EventCommentsLoading(event.eventId));
      
      final comments = await _eventsRepository.getEventComments(event.eventId);
      
      emit(EventCommentsLoaded(
        eventId: event.eventId,
        comments: comments,
      ));
    } catch (e) {
      debugPrint('Error loading event comments: $e');
      
      // Handle 403 (unauthorized) errors with specific message
      String errorMessage;
      if (e.toString().contains('403') || e.toString().toLowerCase().contains('unauthorized')) {
        errorMessage = 'You no longer have access to this event\'s comments';
      } else {
        errorMessage = 'Failed to load comments';
      }
      
      emit(EventCommentsError(
        eventId: event.eventId,
        message: errorMessage,
      ));
    }
  }

  Future<void> _onRefreshEventComments(RefreshEventComments event, Emitter<EventCommentsState> emit) async {
    add(LoadEventComments(event.eventId));
  }

  Future<void> _onAddEventComment(AddEventComment event, Emitter<EventCommentsState> emit) async {
    try {
      emit(EventCommentActionLoading(
        eventId: event.eventId,
        message: 'Adding comment...',
      ));
      
      await _eventsRepository.addEventComment(
        eventId: event.eventId,
        comment: event.comment,
      );
      
      emit(EventCommentActionSuccess(
        eventId: event.eventId,
        message: 'Comment added successfully!',
      ));
      
      // Refresh comments after successful addition
      add(LoadEventComments(event.eventId));
    } catch (e) {
      debugPrint('Error adding event comment: $e');
      emit(EventCommentActionError(
        eventId: event.eventId,
        message: 'Failed to add comment: ${e.toString()}',
      ));
    }
  }

  Future<void> _onUpdateEventComment(UpdateEventComment event, Emitter<EventCommentsState> emit) async {
    try {
      emit(EventCommentActionLoading(
        eventId: event.eventId,
        message: 'Updating comment...',
      ));
      
      await _eventsRepository.updateEventComment(
        eventId: event.eventId,
        commentId: event.commentId,
        comment: event.comment,
      );
      
      emit(EventCommentActionSuccess(
        eventId: event.eventId,
        message: 'Comment updated successfully!',
      ));
      
      // Refresh comments after successful update
      add(LoadEventComments(event.eventId));
    } catch (e) {
      debugPrint('Error updating event comment: $e');
      emit(EventCommentActionError(
        eventId: event.eventId,
        message: 'Failed to update comment: ${e.toString()}',
      ));
    }
  }

  Future<void> _onDeleteEventComment(DeleteEventComment event, Emitter<EventCommentsState> emit) async {
    try {
      emit(EventCommentActionLoading(
        eventId: event.eventId,
        message: 'Deleting comment...',
      ));
      
      await _eventsRepository.deleteEventComment(
        eventId: event.eventId,
        commentId: event.commentId,
      );
      
      emit(EventCommentActionSuccess(
        eventId: event.eventId,
        message: 'Comment deleted successfully!',
      ));
      
      // Refresh comments after successful deletion
      add(LoadEventComments(event.eventId));
    } catch (e) {
      debugPrint('Error deleting event comment: $e');
      emit(EventCommentActionError(
        eventId: event.eventId,
        message: 'Failed to delete comment: ${e.toString()}',
      ));
    }
  }
}
