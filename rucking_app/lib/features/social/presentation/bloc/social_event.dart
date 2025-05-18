import 'package:equatable/equatable.dart';

/// Base class for all social interaction events
abstract class SocialEvent extends Equatable {
  const SocialEvent();

  @override
  List<Object?> get props => [];
}

/// Event to load likes for a specific ruck session
class LoadRuckLikes extends SocialEvent {
  final int ruckId;

  const LoadRuckLikes(this.ruckId);

  @override
  List<Object?> get props => [ruckId];
}

/// Event to toggle like status on a ruck session
class ToggleRuckLike extends SocialEvent {
  final int ruckId;

  const ToggleRuckLike(this.ruckId);

  @override
  List<Object?> get props => [ruckId];
}

/// Event to check if the current user has liked a specific ruck
class CheckUserLikeStatus extends SocialEvent {
  final int ruckId;

  const CheckUserLikeStatus(this.ruckId);

  @override
  List<Object?> get props => [ruckId];
}

/// Additional event for checking ruck like status with a different name for UI components
class CheckRuckLikeStatus extends SocialEvent {
  final int ruckId;

  const CheckRuckLikeStatus(this.ruckId);

  @override
  List<Object?> get props => [ruckId];
}

/// Event to load comments for a specific ruck session
class LoadRuckComments extends SocialEvent {
  final int ruckId;

  const LoadRuckComments(this.ruckId);

  @override
  List<Object?> get props => [ruckId];
}

/// Event to add a comment to a ruck session
class AddRuckComment extends SocialEvent {
  final int ruckId;
  final String content;

  const AddRuckComment({
    required this.ruckId,
    required this.content,
  });

  @override
  List<Object?> get props => [ruckId, content];
}

/// Event to update an existing comment
class UpdateRuckComment extends SocialEvent {
  final String commentId;
  final String content;

  const UpdateRuckComment({
    required this.commentId,
    required this.content,
  });

  @override
  List<Object?> get props => [commentId, content];
}

/// Event to delete a comment
class DeleteRuckComment extends SocialEvent {
  final String commentId;
  final int ruckId; // For refreshing comments after deletion

  const DeleteRuckComment({
    required this.commentId,
    required this.ruckId,
  });

  @override
  List<Object?> get props => [commentId, ruckId];
}

/// Event to clear any error state
class ClearSocialError extends SocialEvent {}
