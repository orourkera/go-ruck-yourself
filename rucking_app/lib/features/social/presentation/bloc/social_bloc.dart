import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/foundation.dart';

import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/social/presentation/bloc/social_event.dart';
import 'package:rucking_app/features/social/presentation/bloc/social_state.dart';
import 'package:rucking_app/features/social/data/repositories/social_repository.dart';
import 'package:rucking_app/core/error/exceptions.dart';
import 'package:rucking_app/features/social/domain/models/ruck_like.dart';
import 'package:rucking_app/features/social/domain/models/ruck_comment.dart';

/// BLoC for managing social interactions (likes, comments)
class SocialBloc extends Bloc<SocialEvent, SocialState> {
  final SocialRepository _socialRepository;
  final AuthBloc _authBloc;

  SocialBloc({
    required SocialRepository socialRepository,
    required AuthBloc authBloc,
  })  : _socialRepository = socialRepository,
        _authBloc = authBloc,
        super(SocialInitial()) {
    on<LoadRuckLikes>(_onLoadRuckLikes);
    on<ToggleRuckLike>(_onToggleRuckLike);
    on<CheckUserLikeStatus>(_onCheckUserLikeStatus);
    on<CheckRuckLikeStatus>(_onCheckRuckLikeStatus);
    on<LoadRuckComments>(_onLoadRuckComments);
    on<AddRuckComment>(_onAddRuckComment);
    on<UpdateRuckComment>(_onUpdateRuckComment);
    on<DeleteRuckComment>(_onDeleteRuckComment);
    on<ClearSocialError>(_onClearSocialError);
    on<ClearSocialCache>(_onClearSocialCache);
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
    } on UnauthorizedException {
      emit(LikesError('Authentication error'));
    } on ServerException {
      emit(LikesError('Server error'));
    } catch (e) {
      emit(LikesError('Unknown error: $e'));
    }
  }

  /// Handler for toggling like status on a ruck session
  Future<void> _onToggleRuckLike(
    ToggleRuckLike event,
    Emitter<SocialState> emit,
  ) async {
    try {
      final int? ruckId = event.ruckId;

      // Early return if ruckId is null - cannot process like toggle
      if (ruckId == null) {
        emit(LikeActionError('Cannot toggle like: Invalid session ID', -1));
        return;
      }

      // Get current user
      final authState = _authBloc.state;
      if (authState is! Authenticated) {
        emit(LikeActionError('User not authenticated', ruckId));
        return;
      }

      // Use cached like status to determine action - much faster than API call
      final cachedLikeStatus = _socialRepository.getCachedLikeStatus(ruckId);
      final isCurrentlyLiked =
          cachedLikeStatus ?? false; // Default to false if no cache

      // Toggle the like - API endpoints will return updated state
      bool newLikedState;
      int newLikeCount;

      if (isCurrentlyLiked) {
        await _socialRepository.removeRuckLike(ruckId);
        newLikedState = false;
        // Get the updated count from repository cache (already decremented)
        newLikeCount = _socialRepository.getCachedLikeCount(ruckId) ?? 0;
      } else {
        await _socialRepository.addRuckLike(ruckId);
        newLikedState = true;
        // Get the updated count from repository cache (already incremented)
        newLikeCount = _socialRepository.getCachedLikeCount(ruckId) ?? 1;
      }

      // Emit completed state immediately - no need for additional API calls
      emit(LikeActionCompleted(
        isLiked: newLikedState,
        ruckId: ruckId,
        likeCount: newLikeCount,
      ));
    } catch (e) {
      emit(LikeActionError(
          'Error updating like status: $e', event.ruckId ?? -1));
    }
  }

  /// Handler for checking if current user has liked a ruck
  Future<void> _onCheckUserLikeStatus(
    CheckUserLikeStatus event,
    Emitter<SocialState> emit,
  ) async {
    try {
      // Get current user ID from AuthBloc
      String? currentUserId;
      if (_authBloc.state is Authenticated) {
        currentUserId = (_authBloc.state as Authenticated).user.userId;
      }

      if (currentUserId == null) {
        emit(const LikesError(
            'User not authenticated. Cannot check like status.'));
        return;
      }

      // Always fetch all likes for the ruck
      final List<RuckLike> likes =
          await _socialRepository.getRuckLikes(event.ruckId);

      // Determine if the current user has liked this ruck
      final bool userHasLiked =
          likes.any((like) => like.userId == currentUserId);

      // Get the total like count
      final int totalLikeCount = likes.length;

      final LikeStatusChecked stateToEmit = LikeStatusChecked(
        isLiked: userHasLiked,
        ruckId: event.ruckId,
        likeCount: totalLikeCount,
      );
      emit(stateToEmit);
    } on UnauthorizedException {
      emit(LikesError('Authentication error'));
    } on ServerException {
      emit(LikesError('Server error'));
    } catch (e) {
      emit(LikesError('Unknown error: $e'));
    }
  }

  /// Handler for checking ruck like status (specifically for UI components)
  Future<void> _onCheckRuckLikeStatus(
    CheckRuckLikeStatus event,
    Emitter<SocialState> emit,
  ) async {
    // First emit cached data immediately if available
    final cachedLikeStatus =
        _socialRepository.getCachedLikeStatus(event.ruckId);
    final cachedLikeCount = _socialRepository.getCachedLikeCount(event.ruckId);

    if (cachedLikeStatus != null && cachedLikeCount != null) {
      // Emit cached state immediately
      emit(LikeStatusChecked(
        isLiked: cachedLikeStatus,
        ruckId: event.ruckId,
        likeCount: cachedLikeCount,
      ));
    }

    try {
      // Then fetch fresh data. hasUserLikedRuck will update caches internally for both status and count.
      final bool hasLiked =
          await _socialRepository.hasUserLikedRuck(event.ruckId);
      // After hasUserLikedRuck completes, caches are guaranteed to be updated if they were invalid.
      // So, we can now safely get the (potentially updated) count from the cache.
      final int likeCount =
          _socialRepository.getCachedLikeCount(event.ruckId) ?? 0;

      // Only emit again if value changed or we didn't emit cached data initially
      if (cachedLikeStatus != hasLiked ||
          cachedLikeCount != likeCount ||
          cachedLikeStatus == null ||
          cachedLikeCount == null) {
        emit(LikeStatusChecked(
          isLiked: hasLiked,
          ruckId: event.ruckId,
          likeCount: likeCount,
        ));
      }
    } on UnauthorizedException {
      // Don't emit error state for this quietly running check, but ensure a default state if nothing was emitted
      if (cachedLikeStatus == null || cachedLikeCount == null) {
        emit(LikeStatusChecked(
            isLiked: false, ruckId: event.ruckId, likeCount: 0));
      }
    } on ServerException {
      if (cachedLikeStatus == null || cachedLikeCount == null) {
        emit(LikeStatusChecked(
            isLiked: false, ruckId: event.ruckId, likeCount: 0));
      }
    } catch (e) {
      if (cachedLikeStatus == null || cachedLikeCount == null) {
        emit(LikeStatusChecked(
            isLiked: false, ruckId: event.ruckId, likeCount: 0));
      }
    }
  }

  /// Handler for loading comments for a ruck session - optimized for faster response
  Future<void> _onLoadRuckComments(
    LoadRuckComments event,
    Emitter<SocialState> emit,
  ) async {
    // First check for cached comments
    final cachedComments = _socialRepository.getCachedComments(event.ruckId);

    if (cachedComments != null && cachedComments.isNotEmpty) {
      // Skip the loading state if we have cached data
      emit(CommentsLoaded(comments: cachedComments, ruckId: event.ruckId));

      // Also update comment count immediately
      _updateCommentCount(event.ruckId, cachedComments.length, emit);
    } else {
      // Only emit loading state if no cached data
      emit(CommentsLoading());
    }

    try {
      // Fetch fresh data
      final comments = await _socialRepository.getRuckComments(event.ruckId);

      // Only emit if different from cached or no cache was available
      if (cachedComments == null ||
          cachedComments.length != comments.length ||
          _commentsChanged(cachedComments, comments)) {
        emit(CommentsLoaded(comments: comments, ruckId: event.ruckId));
        // Update the comment count so listeners can update
        _updateCommentCount(event.ruckId, comments.length, emit);
      }
    } on UnauthorizedException {
      // Only emit error if we didn't already show cached comments
      if (cachedComments == null) {
        emit(CommentsError('Authentication error'));
      }
    } on ServerException {
      // Only emit error if we didn't already show cached comments
      if (cachedComments == null) {
        emit(CommentsError('Server error'));
      }
    } catch (e) {
      // Only emit error if we didn't already show cached comments
      if (cachedComments == null) {
        emit(CommentsError('Unknown error: $e'));
      }
    }
  }

  /// Helper method to determine if comments have changed
  bool _commentsChanged(
      List<RuckComment> oldComments, List<RuckComment> newComments) {
    if (oldComments.length != newComments.length) return true;

    // Check if any comment IDs or content don't match
    for (int i = 0; i < oldComments.length; i++) {
      if (i >= newComments.length) return true;
      if (oldComments[i].id != newComments[i].id ||
          oldComments[i].content != newComments[i].content) {
        return true;
      }
    }

    return false;
  }

  /// Handler for adding a comment to a ruck session
  Future<void> _onAddRuckComment(
    AddRuckComment event,
    Emitter<SocialState> emit,
  ) async {
    final ruckId = event.ruckId;
    final ruckIdInt = int.tryParse(ruckId);
    if (ruckIdInt == null) {
      emit(CommentActionError('Invalid ruck ID format'));
      return;
    }

    // Store the content for optimistic update
    final commentContent = event.content;

    try {
      emit(CommentActionInProgress());

      // First, get current comment count for optimistic update
      final currentComments = await _socialRepository.getRuckComments(ruckId);
      final currentCount = currentComments.length;
      final newCount = currentCount +
          1; // Optimistically assume comment will be added successfully

      // Optimistically update the comment count BEFORE the API call completes
      // This ensures the UI updates immediately
      emit(CommentCountUpdated(ruckId: ruckIdInt, count: newCount));

      // Now actually add the comment to the backend
      final newComment = await _socialRepository.addRuckComment(
        ruckId,
        commentContent,
      );

      // Fetch actual updated comments list to confirm the update
      final updatedComments = await _socialRepository.getRuckComments(ruckId);
      final actualCount = updatedComments.length;

      // Emit the completed action
      emit(CommentActionCompleted(comment: newComment, actionType: 'add'));

      // Emit updated comments
      emit(CommentsLoaded(comments: updatedComments, ruckId: ruckId));

      // Emit the actual comment count in case our optimistic count was wrong
      if (actualCount != newCount) {
        _updateCommentCount(ruckId, actualCount, emit);
      }

      // Extra protection: emit the comment count update again after a tiny delay
      // This helps ensure that even widgets that may be temporarily inactive receive the update
      await Future.delayed(const Duration(milliseconds: 300));
      _updateCommentCount(ruckId, actualCount, emit);
    } catch (e) {
      // If error occurs, revert the optimistic update by fetching the actual count
      try {
        final revertComments = await _socialRepository.getRuckComments(ruckId);
        final actualCount = revertComments.length;
        _updateCommentCount(ruckId, actualCount, emit);
      } catch (_) {
        // If we can't get the actual count, just indicate the error
        emit(CommentActionError('Failed to add comment'));
      }

      emit(CommentActionError('Error adding comment: $e'));
    }
  }

  /// Helper method to update comment count for a specific ruck
  /// This helps keep comment counts in sync across different screens
  void _updateCommentCount(
      String ruckId, int commentCount, Emitter<SocialState> emit) {
    final ruckIdInt = int.tryParse(ruckId);
    if (ruckIdInt == null) return;

    // Emit a CommentCountUpdated event to notify all listeners
    emit(CommentCountUpdated(ruckId: ruckIdInt, count: commentCount));
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
    } on UnauthorizedException {
      emit(CommentActionError('Authentication error'));
    } on ServerException {
      emit(CommentActionError('Server error'));
    } catch (e) {
      emit(CommentActionError('Unknown error: $e'));
    }
  }

  Future<void> _onDeleteRuckComment(
    DeleteRuckComment event,
    Emitter<SocialState> emit,
  ) async {
    emit(CommentActionInProgress());

    try {
      final result = await _socialRepository.deleteRuckComment(
        event.ruckId,
        event.commentId,
      );

      // Always fetch updated comments list after deletion (successful or 404)
      final comments = await _socialRepository.getRuckComments(event.ruckId);

      // Update comments list
      emit(CommentsLoaded(comments: comments, ruckId: event.ruckId));

      // Also update comment count for all screens
      _updateCommentCount(event.ruckId, comments.length, emit);

      if (result) {
        // Create a placeholder comment to indicate successful deletion
        final deletedComment = RuckComment(
          id: event.commentId,
          ruckId: int.parse(event.ruckId), // Convert String to int
          userId: '',
          userDisplayName: 'Deleted User',
          content: 'Comment removed',
          createdAt: DateTime.now().toUtc(),
        );

        emit(CommentActionCompleted(
            comment: deletedComment, actionType: 'delete'));
      } else {
        emit(CommentActionError('Failed to delete comment'));
      }
    } catch (e) {
      // Even on error, try to refresh comments to sync with server state
      try {
        final comments = await _socialRepository.getRuckComments(event.ruckId);
        emit(CommentsLoaded(comments: comments, ruckId: event.ruckId));
        _updateCommentCount(event.ruckId, comments.length, emit);
      } catch (refreshError) {
        // If refresh also fails, log it but don't override the original error
        debugPrint(
            'Failed to refresh comments after delete error: $refreshError');
      }

      emit(CommentActionError('Error deleting comment: $e'));
    }
  }

  /// Handler for clearing social errors
  void _onClearSocialError(
    ClearSocialError event,
    Emitter<SocialState> emit,
  ) {
    emit(SocialInitial());
  }

  /// Handler for clearing social cache
  void _onClearSocialCache(
    ClearSocialCache event,
    Emitter<SocialState> emit,
  ) {
    // Clear cache in repository
    _socialRepository.clearCache();
    emit(SocialInitial());
  }
}
