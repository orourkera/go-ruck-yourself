import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:rucking_app/features/social/presentation/bloc/social_event.dart';
import 'package:rucking_app/features/social/presentation/bloc/social_state.dart';
import 'package:rucking_app/features/social/data/repositories/social_repository.dart';
import 'package:rucking_app/core/error/exceptions.dart';

/// BLoC for managing social interactions (likes, comments)
class SocialBloc extends Bloc<SocialEvent, SocialState> {
  final SocialRepository _socialRepository;

  SocialBloc({required SocialRepository socialRepository})
      : _socialRepository = socialRepository,
        super(SocialInitial()) {
    on<LoadRuckLikes>(_onLoadRuckLikes);
    on<ToggleRuckLike>(_onToggleRuckLike);
    on<CheckUserLikeStatus>(_onCheckUserLikeStatus);
    on<LoadRuckComments>(_onLoadRuckComments);
    on<AddRuckComment>(_onAddRuckComment);
    on<UpdateRuckComment>(_onUpdateRuckComment);
    on<DeleteRuckComment>(_onDeleteRuckComment);
    on<ClearSocialError>(_onClearSocialError);
  }

  /// Handler for loading likes for a ruck session
  Future<void> _onLoadRuckLikes(
    LoadRuckLikes event,
    Emitter<SocialState> emit,
  ) async {
    emit(LikesLoading());
    
    try {
      final likes = await _socialRepository.getRuckLikes(event.ruckId);
      final hasLiked = await _socialRepository.hasUserLikedRuck(event.ruckId);
      
      emit(LikesLoaded(
        likes: likes,
        userHasLiked: hasLiked,
        ruckId: event.ruckId,
      ));
    } on UnauthorizedException catch (e) {
      emit(LikesError('Authentication error: ${e.message}'));
    } on ServerException catch (e) {
      emit(LikesError('Server error: ${e.message}'));
    } catch (e) {
      emit(LikesError('Unknown error: $e'));
    }
  }

  /// Handler for toggling like status on a ruck session
  Future<void> _onToggleRuckLike(
    ToggleRuckLike event,
    Emitter<SocialState> emit,
  ) async {
    // Check current state to see if user has already liked this ruck
    bool isCurrentlyLiked = false;
    if (state is LikesLoaded) {
      isCurrentlyLiked = (state as LikesLoaded).userHasLiked;
    } else {
      try {
        isCurrentlyLiked = await _socialRepository.hasUserLikedRuck(event.ruckId);
      } catch (e) {
        emit(LikeActionError('Error checking like status: $e'));
        return;
      }
    }
    
    emit(LikeActionInProgress());
    
    try {
      bool success;
      if (isCurrentlyLiked) {
        // User already liked it, so remove like
        success = await _socialRepository.removeRuckLike(event.ruckId);
        if (success) {
          emit(LikeActionCompleted(
            isLiked: false,
            ruckId: event.ruckId,
          ));
        } else {
          emit(const LikeActionError('Failed to unlike ruck session'));
        }
      } else {
        // User hasn't liked it yet, so add like
        final like = await _socialRepository.addRuckLike(event.ruckId);
        emit(LikeActionCompleted(
          isLiked: true,
          ruckId: event.ruckId,
        ));
      }
      
      // Refresh likes
      add(LoadRuckLikes(event.ruckId));
    } on UnauthorizedException catch (e) {
      emit(LikeActionError('Authentication error: ${e.message}'));
    } on ServerException catch (e) {
      emit(LikeActionError('Server error: ${e.message}'));
    } catch (e) {
      emit(LikeActionError('Unknown error: $e'));
    }
  }

  /// Handler for checking if current user has liked a ruck
  Future<void> _onCheckUserLikeStatus(
    CheckUserLikeStatus event,
    Emitter<SocialState> emit,
  ) async {
    try {
      final hasLiked = await _socialRepository.hasUserLikedRuck(event.ruckId);
      
      // Only emit if we're not already in a loaded state
      if (state is! LikesLoaded) {
        final likes = await _socialRepository.getRuckLikes(event.ruckId);
        emit(LikesLoaded(
          likes: likes,
          userHasLiked: hasLiked,
          ruckId: event.ruckId,
        ));
      }
    } on UnauthorizedException catch (e) {
      emit(LikesError('Authentication error: ${e.message}'));
    } on ServerException catch (e) {
      emit(LikesError('Server error: ${e.message}'));
    } catch (e) {
      emit(LikesError('Unknown error: $e'));
    }
  }

  /// Handler for loading comments for a ruck session
  Future<void> _onLoadRuckComments(
    LoadRuckComments event,
    Emitter<SocialState> emit,
  ) async {
    emit(CommentsLoading());
    
    try {
      final comments = await _socialRepository.getRuckComments(event.ruckId);
      
      emit(CommentsLoaded(
        comments: comments,
        ruckId: event.ruckId,
      ));
    } on UnauthorizedException catch (e) {
      emit(CommentsError('Authentication error: ${e.message}'));
    } on ServerException catch (e) {
      emit(CommentsError('Server error: ${e.message}'));
    } catch (e) {
      emit(CommentsError('Unknown error: $e'));
    }
  }

  /// Handler for adding a comment to a ruck session
  Future<void> _onAddRuckComment(
    AddRuckComment event,
    Emitter<SocialState> emit,
  ) async {
    emit(CommentActionInProgress());
    
    try {
      final comment = await _socialRepository.addRuckComment(
        event.ruckId,
        event.content,
      );
      
      emit(CommentActionCompleted(
        comment: comment,
        actionType: 'add',
      ));
      
      // Refresh comments list
      add(LoadRuckComments(event.ruckId));
    } on UnauthorizedException catch (e) {
      emit(CommentActionError('Authentication error: ${e.message}'));
    } on ServerException catch (e) {
      emit(CommentActionError('Server error: ${e.message}'));
    } catch (e) {
      emit(CommentActionError('Unknown error: $e'));
    }
  }

  /// Handler for updating a comment
  Future<void> _onUpdateRuckComment(
    UpdateRuckComment event,
    Emitter<SocialState> emit,
  ) async {
    emit(CommentActionInProgress());
    
    try {
      final updatedComment = await _socialRepository.updateRuckComment(
        event.commentId,
        event.content,
      );
      
      emit(CommentActionCompleted(
        comment: updatedComment,
        actionType: 'update',
      ));
      
      // Refresh comments if we know which ruck this belongs to
      if (state is CommentsLoaded) {
        final ruckId = (state as CommentsLoaded).ruckId;
        add(LoadRuckComments(ruckId));
      }
    } on UnauthorizedException catch (e) {
      emit(CommentActionError('Authentication error: ${e.message}'));
    } on ServerException catch (e) {
      emit(CommentActionError('Server error: ${e.message}'));
    } catch (e) {
      emit(CommentActionError('Unknown error: $e'));
    }
  }

  /// Handler for deleting a comment
  Future<void> _onDeleteRuckComment(
    DeleteRuckComment event,
    Emitter<SocialState> emit,
  ) async {
    emit(CommentActionInProgress());
    
    try {
      final success = await _socialRepository.deleteRuckComment(
        event.commentId,
      );
      
      if (success) {
        emit(const CommentActionCompleted(
          comment: null,
          actionType: 'delete',
        ));
        
        // Refresh comments list
        add(LoadRuckComments(event.ruckId));
      } else {
        emit(const CommentActionError('Failed to delete comment'));
      }
    } on UnauthorizedException catch (e) {
      emit(CommentActionError('Authentication error: ${e.message}'));
    } on ServerException catch (e) {
      emit(CommentActionError('Server error: ${e.message}'));
    } catch (e) {
      emit(CommentActionError('Unknown error: $e'));
    }
  }

  /// Handler for clearing errors
  void _onClearSocialError(
    ClearSocialError event,
    Emitter<SocialState> emit,
  ) {
    if (state is LikesError || state is LikeActionError) {
      emit(SocialInitial());
    } else if (state is CommentsError || state is CommentActionError) {
      emit(SocialInitial());
    }
  }
}
