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
  }) : _socialRepository = socialRepository,
       _authBloc = authBloc,
       super(SocialInitial()) {
    on<LoadRuckLikes>(_onLoadRuckLikes);
    on<ToggleRuckLike>(_onToggleRuckLike);
    on<CheckUserLikeStatus>(_onCheckUserLikeStatus);
    on<CheckRuckLikeStatus>(_onCheckRuckLikeStatus);
    on<BatchCheckUserLikeStatus>(_onBatchCheckUserLikeStatus);
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
    debugPrint('[SOCIAL_DEBUG] ToggleRuckLike called for ruckId: ${event.ruckId}');
    
    // Capture initial batch state if present
    final BatchLikeStatusChecked? initialBatchState = state is BatchLikeStatusChecked ? state as BatchLikeStatusChecked : null;

    bool isCurrentlyLiked = false;
    int currentLikeCount = 0;
    
    if (state is LikesLoaded && (state as LikesLoaded).ruckId == event.ruckId) {
      isCurrentlyLiked = (state as LikesLoaded).userHasLiked;
      currentLikeCount = (state as LikesLoaded).likes.length;
    } else if (state is LikeActionCompleted && (state as LikeActionCompleted).ruckId == event.ruckId) {
      isCurrentlyLiked = (state as LikeActionCompleted).isLiked;
      currentLikeCount = (state as LikeActionCompleted).likeCount;
    } else if (state is LikeStatusChecked && (state as LikeStatusChecked).ruckId == event.ruckId) {
      isCurrentlyLiked = (state as LikeStatusChecked).isLiked;
      currentLikeCount = (state as LikeStatusChecked).likeCount;
    } else if (initialBatchState != null) { // Use captured initialBatchState
      final likeStatus = initialBatchState.likeStatusMap[event.ruckId];
      final likeCount = initialBatchState.likeCountMap[event.ruckId];
      if (likeStatus != null) isCurrentlyLiked = likeStatus;
      if (likeCount != null) currentLikeCount = likeCount;
    } else {
      debugPrint('[SOCIAL_DEBUG] No existing like status in state, checking with API for toggle');
      try {
        isCurrentlyLiked = await _socialRepository.hasUserLikedRuck(event.ruckId);
        // To get count, we might need getRuckLikes or a dedicated count method
        final likes = await _socialRepository.getRuckLikes(event.ruckId); 
        currentLikeCount = likes.length;
      } catch (e) {
        debugPrint('[SOCIAL_DEBUG] Error fetching current like status for toggle: $e');
        isCurrentlyLiked = false; // Assume not liked if check fails
        currentLikeCount = 0;
      }
    }

    final newLikeStatus = !isCurrentlyLiked;
    final newLikeCount = newLikeStatus 
        ? currentLikeCount + 1 
        : (currentLikeCount > 0 ? currentLikeCount - 1 : 0);
    
    emit(LikeActionCompleted(
      isLiked: newLikeStatus,
      ruckId: event.ruckId,
      likeCount: newLikeCount,
    ));
    
    if (initialBatchState != null) {
      final updatedStatusMap = Map<int, bool>.from(initialBatchState.likeStatusMap);
      final updatedCountMap = Map<int, int>.from(initialBatchState.likeCountMap);
      updatedStatusMap[event.ruckId] = newLikeStatus;
      updatedCountMap[event.ruckId] = newLikeCount;
      emit(BatchLikeStatusChecked(updatedStatusMap, likeCountMap: updatedCountMap));
    }
    
    try {
      bool success = false;
      if (isCurrentlyLiked) {
        success = await _socialRepository.removeRuckLike(event.ruckId);
      } else {
        final like = await _socialRepository.addRuckLike(event.ruckId);
        success = like != null && like.id.isNotEmpty;
      }
      
      if (!success) {
        debugPrint('[SOCIAL_DEBUG] Like toggle API call failed - reverting optimistic update');
        emit(LikeActionCompleted(
          isLiked: isCurrentlyLiked, // Revert to original
          ruckId: event.ruckId,
          likeCount: currentLikeCount, // Revert to original
        ));
        if (initialBatchState != null) {
          final revertedStatusMap = Map<int, bool>.from(initialBatchState.likeStatusMap);
          final revertedCountMap = Map<int, int>.from(initialBatchState.likeCountMap);
          // Ensure the maps are reverted to original state for this ruckId
          revertedStatusMap[event.ruckId] = isCurrentlyLiked;
          revertedCountMap[event.ruckId] = currentLikeCount;
          emit(BatchLikeStatusChecked(revertedStatusMap, likeCountMap: revertedCountMap));
        }
        emit(LikeActionError('Failed to toggle like', event.ruckId));
      } else {
        debugPrint('[SOCIAL_DEBUG] Like toggle API call succeeded');
        // Optionally, re-fetch the definitive count from the server after a successful toggle
        // final definitiveLikes = await _socialRepository.getRuckLikes(event.ruckId);
        // final definitiveCount = definitiveLikes.length;
        // if (definitiveCount != newLikeCount) {
        //   emit(LikeActionCompleted(isLiked: newLikeStatus, ruckId: event.ruckId, likeCount: definitiveCount));
        //   if (initialBatchState != null) {
        //      final finalStatusMap = Map<int, bool>.from(initialBatchState.likeStatusMap)..[event.ruckId] = newLikeStatus;
        //      final finalCountMap = Map<int, int>.from(initialBatchState.likeCountMap)..[event.ruckId] = definitiveCount;
        //      emit(BatchLikeStatusChecked(finalStatusMap, likeCountMap: finalCountMap));
        //   }
        // }
      }
    } catch (e) {
      debugPrint('[SOCIAL_DEBUG] Error toggling like: $e');
      emit(LikeActionCompleted(
        isLiked: isCurrentlyLiked, // Revert to original
        ruckId: event.ruckId,
        likeCount: currentLikeCount, // Revert to original
      ));
      if (initialBatchState != null) {
          final revertedStatusMap = Map<int, bool>.from(initialBatchState.likeStatusMap);
          final revertedCountMap = Map<int, int>.from(initialBatchState.likeCountMap);
          revertedStatusMap[event.ruckId] = isCurrentlyLiked;
          revertedCountMap[event.ruckId] = currentLikeCount;
          emit(BatchLikeStatusChecked(revertedStatusMap, likeCountMap: revertedCountMap));
      }
      if (e is ServerException) {
        emit(LikeActionError('Server error: ${e.message}', event.ruckId));
      } else {
        emit(LikeActionError('Error toggling like: $e', event.ruckId));
      }
    }
  }

  /// Handler for checking if current user has liked a ruck
  Future<void> _onCheckUserLikeStatus(
    CheckUserLikeStatus event,
    Emitter<SocialState> emit,
  ) async {
    debugPrint('//////////////////////////////////////////////////////////////////////');
    debugPrint('[MEGA_DEBUG_BLOC] _onCheckUserLikeStatus CALLED FOR RUCK ID: ${event.ruckId}');
    debugPrint('//////////////////////////////////////////////////////////////////////');
    debugPrint('[LIKE_DEBUG_BLOC] _onCheckUserLikeStatus called for ruckId: ${event.ruckId}');
    try {
      // Get current user ID from AuthBloc
      String? currentUserId;
      if (_authBloc.state is Authenticated) {
        currentUserId = (_authBloc.state as Authenticated).user.userId;
      }

      if (currentUserId == null) {
        debugPrint('[LIKE_DEBUG_BLOC] User not authenticated. Emitting LikesError.');
        emit(const LikesError('User not authenticated. Cannot check like status.'));
        return;
      }
      debugPrint('[LIKE_DEBUG_BLOC] currentUserId: $currentUserId');

      // Always fetch all likes for the ruck
      final List<RuckLike> likes = await _socialRepository.getRuckLikes(event.ruckId);
      debugPrint('[LIKE_DEBUG_BLOC] Fetched likes for ruckId ${event.ruckId}: ${likes.map((l) => l.toJson()).toList()}');
      
      // Determine if the current user has liked this ruck
      final bool userHasLiked = likes.any((like) => like.userId == currentUserId);
      debugPrint('[LIKE_DEBUG_BLOC] userHasLiked: $userHasLiked');
      
      // Get the total like count
      final int totalLikeCount = likes.length;
      debugPrint('[LIKE_DEBUG_BLOC] totalLikeCount: $totalLikeCount');

      final LikeStatusChecked stateToEmit = LikeStatusChecked(
        isLiked: userHasLiked,
        ruckId: event.ruckId,
        likeCount: totalLikeCount,
      );
      debugPrint('[LIKE_DEBUG_BLOC] Emitting LikeStatusChecked: isLiked=${stateToEmit.isLiked}, ruckId=${stateToEmit.ruckId}, likeCount=${stateToEmit.likeCount}');
      emit(stateToEmit);
      
      // The LikesLoaded state emission might need re-evaluation based on overall bloc design.
      // For now, focusing on getting LikeStatusChecked correct for RuckBuddyDetailScreen.
      // if (state is! LikesLoaded) { // This condition might not be relevant anymore or needs adjustment
      //   emit(LikesLoaded(
      //     likes: likes, // This 'likes' is List<RuckLike>
      //     userHasLiked: userHasLiked, // Redundant if LikeStatusChecked is the primary state for this event
      //     ruckId: event.ruckId,
      //   ));
      // }

    } on UnauthorizedException catch (e) {
      emit(LikesError('Authentication error: ${e.message}'));
    } on ServerException catch (e) {
      emit(LikesError('Server error: ${e.message}'));
    } catch (e) {
      emit(LikesError('Unknown error: $e'));
    }
  }

  /// Handler for checking ruck like status (specifically for UI components)
  Future<void> _onCheckRuckLikeStatus(
    CheckRuckLikeStatus event,
    Emitter<SocialState> emit,
  ) async {
    debugPrint('🔍 Checking like status for ruck ID: ${event.ruckId}');
    try {
      final hasLiked = await _socialRepository.hasUserLikedRuck(event.ruckId);
      // Fetch the total like count
      final likes = await _socialRepository.getRuckLikes(event.ruckId);
      final likeCount = likes.length;
      debugPrint('✅ Like status check complete: $hasLiked, Count: $likeCount');
      
      // Emit simple state just with like status
      emit(LikeStatusChecked(
        isLiked: hasLiked,
        ruckId: event.ruckId,
        likeCount: likeCount, // Updated to use the fetched count
      ));
    } on UnauthorizedException catch (e) {
      debugPrint('❌ Authentication error checking like status: ${e.message}');
      // Don't emit error state for this quietly running check
    } on ServerException catch (e) {
      debugPrint('❌ Server error checking like status: ${e.message}');
      // Don't emit error state for this quietly running check
    } catch (e) {
      debugPrint('❌ Unknown error checking like status: $e');
      // Don't emit error state for this quietly running check
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
      debugPrint('[SOCIAL_DEBUG] Comments API response: 200'); // Assuming success
      emit(CommentsLoaded(comments: comments, ruckId: event.ruckId));
      // Update the comment count so listeners like RuckBuddyCard can update
      _updateCommentCount(event.ruckId, comments.length, emit);
    } on UnauthorizedException catch (e) {
      debugPrint('[SOCIAL_DEBUG] Authentication error loading comments: ${e.message}');
      emit(CommentsError('Authentication error: ${e.message}'));
    } on ServerException catch (e) {
      debugPrint('[SOCIAL_DEBUG] Server error loading comments: ${e.message}');
      emit(CommentsError('Server error: ${e.message}'));
    } catch (e) {
      debugPrint('[SOCIAL_DEBUG] Unknown error loading comments: $e');
      emit(CommentsError('Unknown error: $e'));
    }
  }

  /// Handler for adding a comment to a ruck session
  Future<void> _onAddRuckComment(
    AddRuckComment event,
    Emitter<SocialState> emit,
  ) async {
    debugPrint('[SOCIAL_DEBUG] _onAddRuckComment called for ruck ${event.ruckId}');
    
    final ruckId = event.ruckId;
    final ruckIdInt = int.tryParse(ruckId);
    if (ruckIdInt == null) {
      debugPrint('[SOCIAL_DEBUG] Invalid ruckId format: ${event.ruckId}');
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
      final newCount = currentCount + 1; // Optimistically assume comment will be added successfully
      
      // Optimistically update the comment count BEFORE the API call completes
      // This ensures the UI updates immediately
      debugPrint('[SOCIAL_DEBUG] Optimistically updating comment count to $newCount');
      emit(CommentCountUpdated(ruckId: ruckIdInt, count: newCount));
      
      // Now actually add the comment to the backend
      final newComment = await _socialRepository.addRuckComment(
        ruckId,
        commentContent,
      );
      
      debugPrint('[SOCIAL_DEBUG] Successfully added comment ${newComment.id}');
      
      // Fetch actual updated comments list to confirm the update
      final updatedComments = await _socialRepository.getRuckComments(ruckId);      
      final actualCount = updatedComments.length;
      
      debugPrint('[SOCIAL_DEBUG] Verified comment count: $actualCount');
      
      // Emit the completed action
      emit(CommentActionCompleted(comment: newComment, actionType: 'add'));
      
      // Emit updated comments
      emit(CommentsLoaded(comments: updatedComments, ruckId: ruckId));
      
      // Emit the actual comment count in case our optimistic count was wrong
      if (actualCount != newCount) {
        debugPrint('[SOCIAL_DEBUG] Correcting optimistic comment count from $newCount to $actualCount');
        _updateCommentCount(ruckId, actualCount, emit);
      }
      
      // Extra protection: emit the comment count update again after a tiny delay
      // This helps ensure that even widgets that may be temporarily inactive receive the update
      await Future.delayed(const Duration(milliseconds: 300));
      debugPrint('[SOCIAL_DEBUG] Re-emitting CommentCountUpdated after delay with count: $actualCount');
      _updateCommentCount(ruckId, actualCount, emit);
    } on Exception catch (e) {
      debugPrint('[SOCIAL_DEBUG] Error adding comment: $e');
      
      // If error occurs, revert the optimistic update by fetching the actual count
      try {
        final revertComments = await _socialRepository.getRuckComments(ruckId);
        final actualCount = revertComments.length;
        debugPrint('[SOCIAL_DEBUG] Reverting to actual comment count: $actualCount after error');
        _updateCommentCount(ruckId, actualCount, emit);
      } catch (_) {
        // If we can't get the actual count, just indicate the error
        debugPrint('[SOCIAL_DEBUG] Unable to revert comment count after error');
      }
      
      emit(CommentActionError(e.toString()));
    }
  }

  /// Helper method to update comment count for a specific ruck
  /// This helps keep comment counts in sync across different screens
  void _updateCommentCount(String ruckId, int commentCount, Emitter<SocialState> emit) {
    final ruckIdInt = int.tryParse(ruckId);
    if (ruckIdInt == null) return;
    
    // Emit a CommentCountUpdated event to notify all listeners
    emit(CommentCountUpdated(ruckId: ruckIdInt, count: commentCount));
    
    // If we have a batch state active, also update it
    if (state is BatchLikeStatusChecked) {
      final batchState = state as BatchLikeStatusChecked;
      // We intentionally don't update this state as it's for likes, not comments
      // This is handled separately by the CommentCountUpdated state
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

  Future<void> _onDeleteRuckComment(
    DeleteRuckComment event,
    Emitter<SocialState> emit,
  ) async {
    debugPrint('[SOCIAL_DEBUG] _onDeleteRuckComment called for comment ${event.commentId} on ruck ${event.ruckId}');
    emit(CommentActionInProgress());
    
    try {
      final result = await _socialRepository.deleteRuckComment(
        event.commentId,
      );
      
      if (result) {
        // Create a placeholder comment to indicate deletion
        final deletedComment = RuckComment(
          id: event.commentId,
          ruckId: int.parse(event.ruckId), // Convert String to int
          userId: '',
          userDisplayName: 'Deleted User',
          content: 'Comment removed',
          createdAt: DateTime.now(),
        );
        
        emit(CommentActionCompleted(comment: deletedComment, actionType: 'delete'));
        
        // Fetch updated comments list to get the correct count
        final comments = await _socialRepository.getRuckComments(event.ruckId);
        
        // Update comments list
        emit(CommentsLoaded(comments: comments, ruckId: event.ruckId));
        
        // Also update comment count for all screens
        _updateCommentCount(event.ruckId, comments.length, emit);
        
        debugPrint('[SOCIAL_DEBUG] Successfully deleted comment ${event.commentId}, new count: ${comments.length}');
      } else {
        emit(CommentActionError('Failed to delete comment'));
      }
    } catch (e) {
      debugPrint('[SOCIAL_DEBUG] Error deleting comment: $e');
      emit(CommentActionError('Error deleting comment: $e'));
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
  
  /// Handler for batch checking user like status for multiple rucks
  /// This is more efficient than individual API calls
  Future<void> _onBatchCheckUserLikeStatus(
    BatchCheckUserLikeStatus event,
    Emitter<SocialState> emit,
  ) async {
    debugPrint('[SOCIAL_BLOC_DEBUG] _onBatchCheckUserLikeStatus called for ${event.ruckIds.length} rucks');
    if (event.ruckIds.isEmpty) {
      // If current state is not BatchLikeStatusChecked, emit an empty one to avoid breaking UI
      // or ensure UI handles SocialInitial or other states gracefully.
      if (state is! BatchLikeStatusChecked) {
         emit(const BatchLikeStatusChecked({}, likeCountMap: {}));
      }
      return;
    }

    try {
      // Assuming batchCheckUserLikes returns a structure like:
      // {'likeStatus': Map<int, bool>, 'likeCounts': Map<int, int>}
      // You might need to adjust this based on your actual repository method.
      final result = await _socialRepository.batchCheckUserLikes(event.ruckIds);
      
      // Ensure result is not null and contains the expected keys
      final Map<int, bool> likeStatusMap = result['likeStatus'] as Map<int, bool>? ?? {}; 
      final Map<int, int> likeCountMap = result['likeCounts'] as Map<int, int>? ?? {};

      debugPrint('[SOCIAL_BLOC_DEBUG] Batch check result: Statuses count: ${likeStatusMap.length}, Counts count: ${likeCountMap.length}');
      
      // Merge with existing batch state if present, to preserve data for other rucks not in this batch
      Map<int, bool> finalStatusMap = {};
      Map<int, int> finalCountMap = {};

      if (state is BatchLikeStatusChecked) {
        final currentBatchState = state as BatchLikeStatusChecked;
        finalStatusMap.addAll(currentBatchState.likeStatusMap);
        finalCountMap.addAll(currentBatchState.likeCountMap);
      }
      
      // Update with new data from this batch
      finalStatusMap.addAll(likeStatusMap);
      finalCountMap.addAll(likeCountMap);
      
      emit(BatchLikeStatusChecked(finalStatusMap, likeCountMap: finalCountMap));
    } catch (e) {
      debugPrint('[SOCIAL_BLOC_DEBUG] Error in _onBatchCheckUserLikeStatus: $e');
      // Decide on error state: emit a specific BatchLikeError, or a general LikesError,
      // or just log and potentially emit an empty/previous state to avoid breaking UI.
      // For now, just log and emit an empty BatchLikeStatusChecked if no prior batch state exists.
      if (state is! BatchLikeStatusChecked) {
         emit(const BatchLikeStatusChecked({}, likeCountMap: {}));
      }
      // Optionally, emit a more specific error state if needed for UI feedback.
      // emit(LikesError('Failed to batch check like statuses: $e'));
    }
  }

  /// Handler for checking if current user has liked a ruck
}
