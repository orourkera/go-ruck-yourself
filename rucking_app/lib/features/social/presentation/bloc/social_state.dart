import 'package:equatable/equatable.dart';
import 'package:rucking_app/features/social/domain/models/ruck_like.dart';
import 'package:rucking_app/features/social/domain/models/ruck_comment.dart';

/// Base class for all social interaction states
abstract class SocialState extends Equatable {
  const SocialState();

  @override
  List<Object?> get props => [];
}

/// Initial state when no social data has been loaded
class SocialInitial extends SocialState {}

/// State for when likes are being loaded
class LikesLoading extends SocialState {}

/// State for when likes have been successfully loaded
class LikesLoaded extends SocialState {
  final List<RuckLike> likes;
  final bool userHasLiked;
  final int ruckId;

  const LikesLoaded({
    required this.likes,
    required this.userHasLiked,
    required this.ruckId,
  });

  @override
  List<Object?> get props => [likes, userHasLiked, ruckId];
}

/// State for when there was an error loading likes
class LikesError extends SocialState {
  final String message;

  const LikesError(this.message);

  @override
  List<Object?> get props => [message];
}

/// State for when a like action is in progress
class LikeActionInProgress extends SocialState {}

/// State for when a like action is completed
class LikeActionCompleted extends SocialState {
  final bool isLiked;
  final int ruckId;
  final int likeCount;

  const LikeActionCompleted({
    required this.isLiked,
    required this.ruckId,
    required this.likeCount,
  });

  @override
  List<Object?> get props => [isLiked, ruckId, likeCount];
}

/// State for when a like action fails
class LikeActionError extends SocialState {
  final String message;
  final int ruckId;

  const LikeActionError(this.message, this.ruckId);

  @override
  List<Object?> get props => [message, ruckId];
}

/// State for when a like status check is completed
class LikeStatusChecked extends SocialState {
  final bool isLiked;
  final int ruckId;
  final int likeCount;

  const LikeStatusChecked({
    required this.isLiked,
    required this.ruckId,
    required this.likeCount,
  });

  @override
  List<Object?> get props => [isLiked, ruckId, likeCount];
}

/// State for when comments are being loaded
class CommentsLoading extends SocialState {}

/// State for when comments have been successfully loaded
class CommentsLoaded extends SocialState {
  final List<RuckComment> comments;
  final String ruckId;

  const CommentsLoaded({
    required this.comments,
    required this.ruckId,
  });

  @override
  List<Object?> get props => [comments, ruckId];
}

/// State for when there was an error loading comments
class CommentsError extends SocialState {
  final String message;

  const CommentsError(this.message);

  @override
  List<Object?> get props => [message];
}

/// State for when a comment action is in progress
class CommentActionInProgress extends SocialState {}

/// State for when a comment action is completed
class CommentActionCompleted extends SocialState {
  final RuckComment? comment;
  final String actionType; // 'add', 'update', 'delete'

  const CommentActionCompleted({
    this.comment,
    required this.actionType,
  });

  @override
  List<Object?> get props => [comment, actionType];
}

/// State for when a comment action fails
class CommentActionError extends SocialState {
  final String message;

  const CommentActionError(this.message);

  @override
  List<Object?> get props => [message];
}

/// State for when a batch like status check is completed
/// This stores the like status for multiple ruck IDs
class BatchLikeStatusChecked extends SocialState {
  /// Map of ruckId -> isLiked status
  final Map<int, bool> likeStatusMap;

  const BatchLikeStatusChecked(this.likeStatusMap);

  @override
  List<Object?> get props => [likeStatusMap];
}
