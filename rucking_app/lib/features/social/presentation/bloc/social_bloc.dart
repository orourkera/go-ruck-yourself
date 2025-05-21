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
    
    // Check the current state to determine if we're already liked
    bool isCurrentlyLiked = false;
    int currentLikeCount = 0;
    
    // Try to determine current like status from state first
    if (state is LikesLoaded && (state as LikesLoaded).ruckId == event.ruckId) {
      isCurrentlyLiked = (state as LikesLoaded).userHasLiked;
      currentLikeCount = (state as LikesLoaded).likes.length;
      debugPrint('[SOCIAL_DEBUG] Current like status from LikesLoaded state: $isCurrentlyLiked');
    } else if (state is LikeActionCompleted && (state as LikeActionCompleted).ruckId == event.ruckId) {
      isCurrentlyLiked = (state as LikeActionCompleted).isLiked;
      currentLikeCount = (state as LikeActionCompleted).likeCount;
      debugPrint('[SOCIAL_DEBUG] Current like status from LikeActionCompleted state: $isCurrentlyLiked');
    } else if (state is LikeStatusChecked && (state as LikeStatusChecked).ruckId == event.ruckId) {
      isCurrentlyLiked = (state as LikeStatusChecked).isLiked;
      currentLikeCount = (state as LikeStatusChecked).likeCount;
      debugPrint('[SOCIAL_DEBUG] Current like status from LikeStatusChecked state: $isCurrentlyLiked');
    } else if (state is BatchLikeStatusChecked) {
      // Try to get the like status from a batch check
      final batchState = state as BatchLikeStatusChecked;
      final likeStatus = batchState.likeStatusMap[event.ruckId];
      final likeCount = batchState.likeCountMap[event.ruckId];
      
      if (likeStatus != null) {
        isCurrentlyLiked = likeStatus;
        debugPrint('[SOCIAL_DEBUG] Current like status from BatchLikeStatusChecked: $isCurrentlyLiked');
      }
      
      if (likeCount != null) {
        currentLikeCount = likeCount;
        debugPrint('[SOCIAL_DEBUG] Current like count from BatchLikeStatusChecked: $currentLikeCount');
      }
    } else {
      // No existing state with like info, need to check with API
      debugPrint('[SOCIAL_DEBUG] No existing like status in state, checking with API');
      try {
        isCurrentlyLiked = await _socialRepository.hasUserLikedRuck(event.ruckId);
        final likes = await _socialRepository.getRuckLikes(event.ruckId);
        currentLikeCount = likes.length;
        debugPrint('[SOCIAL_DEBUG] Current like status from API: $isCurrentlyLiked, count: $currentLikeCount');
      } catch (e) {
        debugPrint('[SOCIAL_DEBUG] Error fetching current like status: $e');
        // Continue with toggle anyway, assuming not liked
        isCurrentlyLiked = false;
        currentLikeCount = 0;
      }
    }

    // Calculate the new like state and count
    final newLikeStatus = !isCurrentlyLiked;
    final newLikeCount = newLikeStatus 
        ? currentLikeCount + 1 
        : (currentLikeCount > 0 ? currentLikeCount - 1 : 0);
    
    // OPTIMISTIC UPDATE: Immediately update UI for better user experience
    debugPrint('[SOCIAL_DEBUG] Applying optimistic update. New status: $newLikeStatus');
    
    // Emit the new like state immediately for responsive UI
    emit(LikeActionCompleted(
      isLiked: newLikeStatus,
      ruckId: event.ruckId,
      likeCount: newLikeCount,
    ));
    
    // Update batch state immediately for all screens
    if (state is BatchLikeStatusChecked) {
      final batchState = state as BatchLikeStatusChecked;
      final updatedStatusMap = Map<int, bool>.from(batchState.likeStatusMap);
      final updatedCountMap = Map<int, int>.from(batchState.likeCountMap);
      
      updatedStatusMap[event.ruckId] = newLikeStatus;
      updatedCountMap[event.ruckId] = newLikeCount;
      
      emit(BatchLikeStatusChecked(updatedStatusMap, likeCountMap: updatedCountMap));
    }
    
    // Now try the actual API call, and revert if it fails
    try {
      debugPrint('[SOCIAL_DEBUG] Sending API request to toggle like from: $isCurrentlyLiked');
      bool success = false;
      
      if (isCurrentlyLiked) {
        success = await _socialRepository.removeRuckLike(event.ruckId);
      } else {
        // This method returns a RuckLike object, not a boolean
        final like = await _socialRepository.addRuckLike(event.ruckId);
        // If we get here without an exception, consider it successful
        success = like != null && like.id.isNotEmpty;
      }
      
      if (!success) {
        debugPrint('[SOCIAL_DEBUG] Like toggle API call failed - reverting optimistic update');
        
        // Revert to the original state
        emit(LikeActionCompleted(
          isLiked: isCurrentlyLiked,
          ruckId: event.ruckId,
          likeCount: currentLikeCount,
        ));
        
        // Also revert the batch state
        if (state is BatchLikeStatusChecked) {
          final batchState = state as BatchLikeStatusChecked;
          final updatedStatusMap = Map<int, bool>.from(batchState.likeStatusMap);
          final updatedCountMap = Map<int, int>.from(batchState.likeCountMap);
          
          updatedStatusMap[event.ruckId] = isCurrentlyLiked;
          updatedCountMap[event.ruckId] = currentLikeCount;
          
          emit(BatchLikeStatusChecked(updatedStatusMap, likeCountMap: updatedCountMap));
        }
        
        emit(LikeActionError('Failed to toggle like', event.ruckId));
      } else {
        debugPrint('[SOCIAL_DEBUG] Like toggle API call succeeded');
      }
    } catch (e) {
      debugPrint('[SOCIAL_DEBUG] Error toggling like: $e');
      
      // Revert to the original state on error
      emit(LikeActionCompleted(
        isLiked: isCurrentlyLiked,
        ruckId: event.ruckId,
        likeCount: currentLikeCount,
      ));
      
      // Also revert the batch state
      if (state is BatchLikeStatusChecked) {
        final batchState = state as BatchLikeStatusChecked;
        final updatedStatusMap = Map<int, bool>.from(batchState.likeStatusMap);
        final updatedCountMap = Map<int, int>.from(batchState.likeCountMap);
        
        updatedStatusMap[event.ruckId] = isCurrentlyLiked;
        updatedCountMap[event.ruckId] = currentLikeCount;
        
        emit(BatchLikeStatusChecked(updatedStatusMap, likeCountMap: updatedCountMap));
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
      debugPrint('✅ Like status check complete: $hasLiked');
      
      // Emit simple state just with like status
      emit(LikeStatusChecked(
        isLiked: hasLiked,
        ruckId: event.ruckId,
        likeCount: 0, // This will need to be updated to include the like count
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
    debugPrint('[SOCIAL_DEBUG] _onAddRuckComment called for ruck ${event.ruckId}');
    emit(CommentActionInProgress());
    try {
      // Add the new comment
      final newComment = await _socialRepository.addRuckComment(
        event.ruckId,
        event.content,
      );
      
      debugPrint('[SOCIAL_DEBUG] Successfully added comment ${newComment.id}');
      
      // Fetch updated comments list
      final comments = await _socialRepository.getRuckComments(event.ruckId);      
      debugPrint('[SOCIAL_DEBUG] Fetched ${comments.length} comments');
      
      // Emit the completed action and updated comments
      emit(CommentActionCompleted(comment: newComment, actionType: 'add'));
      emit(CommentsLoaded(comments: comments, ruckId: event.ruckId));
      
      // Also update comment count for all screens
      _updateCommentCount(event.ruckId, comments.length, emit);
    } on Exception catch (e) {
      debugPrint('[SOCIAL_DEBUG] Error adding comment: $e');
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
    if (event.ruckIds.isEmpty) return;
    
    debugPrint('[SOCIAL_DEBUG] BatchCheckUserLikeStatus called for ${event.ruckIds.length} rucks');
    
    try {
      // Use the repository's batch method to efficiently check multiple rucks
      final result = await _socialRepository.batchCheckUserLikes(event.ruckIds);
      
      // Handle potentially null maps safely
      final Map<int, bool> likeStatusMap = result['likeStatus'] != null ? 
          Map<int, bool>.from(result['likeStatus'] as Map) : {};
      
      final Map<int, int> likeCountMap = result['likeCounts'] != null ? 
          Map<int, int>.from(result['likeCounts'] as Map) : {};
      
      debugPrint('[SOCIAL_DEBUG] Batch like status check completed for ${likeStatusMap.length} rucks');
      debugPrint('[SOCIAL_DEBUG] Final processed like statuses: $likeStatusMap');
      debugPrint('[SOCIAL_DEBUG] Final processed like counts: $likeCountMap');
      
      // Process each ruck ID individually to make sure the state changes are registered properly
      // This ensures multiple heart icons update correctly across different UI components
      for (final ruckId in event.ruckIds) {
        if (likeStatusMap.containsKey(ruckId)) {
          final isLiked = likeStatusMap[ruckId] ?? false;
          final likeCount = likeCountMap[ruckId] ?? 0;
          
          // Emit individual status updates first so listeners can react
          emit(LikeStatusChecked(ruckId: ruckId, isLiked: isLiked, likeCount: likeCount));
          debugPrint('[SOCIAL_DEBUG] Emitted individual status for ruck $ruckId: isLiked=$isLiked, count=$likeCount');
        }
      }
      
      // Now emit the batch update for components that listen to the batch event
      emit(BatchLikeStatusChecked(likeStatusMap, likeCountMap: likeCountMap));
    } on UnauthorizedException catch (e) {
      debugPrint('[SOCIAL_DEBUG] Authentication error checking batch like status: ${e.message}');
      // Don't emit error state as this is a background operation
    } on ServerException catch (e) {
      debugPrint('[SOCIAL_DEBUG] Server error checking batch like status: ${e.message}');
      // Don't emit error state as this is a background operation
    } catch (e) {
      debugPrint('[SOCIAL_DEBUG] Unknown error checking batch like status: $e');
      // Don't emit error state as this is a background operation
    }
  }
}
