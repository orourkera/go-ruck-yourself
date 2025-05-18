import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:rucking_app/features/social/domain/models/ruck_comment.dart';
import 'package:rucking_app/features/social/presentation/bloc/social_bloc.dart';
import 'package:rucking_app/features/social/presentation/bloc/social_event.dart';
import 'package:rucking_app/features/social/presentation/bloc/social_state.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/widgets/styled_snackbar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A widget for displaying and interacting with comments on a ruck session
class CommentsSection extends StatefulWidget {
  /// ID of the ruck session
  final int ruckId;
  
  /// Maximum number of comments to display at once
  final int? maxDisplayed;
  
  /// Whether to show the "View All" button when there are more comments
  final bool showViewAllButton;
  
  /// Callback when "View All" is tapped
  final VoidCallback? onViewAllTapped;

  /// Creates a comment section for ruck sessions
  const CommentsSection({
    Key? key,
    required this.ruckId,
    this.maxDisplayed,
    this.showViewAllButton = true,
    this.onViewAllTapped,
  }) : super(key: key);

  @override
  State<CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<CommentsSection> {
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();
  bool _isAddingComment = false;
  String? _editingCommentId;
  
  // Current user info
  final _currentUserId = Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    
    // Load comments on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SocialBloc>().add(LoadRuckComments(widget.ruckId));
    });
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  void _handleAddComment() {
    if (_commentController.text.trim().isEmpty) {
      return;
    }
    
    setState(() {
      _isAddingComment = true;
    });
    
    if (_editingCommentId != null) {
      // Update existing comment
      context.read<SocialBloc>().add(
        UpdateRuckComment(
          commentId: _editingCommentId!,
          content: _commentController.text.trim(),
        ),
      );
    } else {
      // Add new comment
      context.read<SocialBloc>().add(
        AddRuckComment(
          ruckId: widget.ruckId,
          content: _commentController.text.trim(),
        ),
      );
    }
    
    _commentController.clear();
    _commentFocusNode.unfocus();
  }

  void _handleEditComment(RuckComment comment) {
    setState(() {
      _editingCommentId = comment.id;
      _commentController.text = comment.content;
    });
    _commentFocusNode.requestFocus();
  }

  void _handleDeleteComment(RuckComment comment) {
    // Show confirmation dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Comment'),
        content: const Text('Are you sure you want to delete this comment?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<SocialBloc>().add(
                DeleteRuckComment(
                  commentId: comment.id,
                  ruckId: widget.ruckId,
                ),
              );
            },
            child: const Text('DELETE'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
      ),
    );
  }

  void _cancelEditing() {
    setState(() {
      _editingCommentId = null;
      _commentController.clear();
    });
    _commentFocusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SocialBloc, SocialState>(
      listenWhen: (previous, current) {
        // Listen only for states related to comments
        return current is CommentsLoaded || 
               current is CommentActionCompleted || 
               current is CommentActionError;
      },
      listener: (context, state) {
        if (state is CommentActionCompleted) {
          setState(() {
            _isAddingComment = false;
            _editingCommentId = null;
          });
          
          if (state.actionType == 'add') {
            StyledSnackBar.show(
              context: context,
              message: 'Comment added',
              type: SnackBarType.success,
            );
          } else if (state.actionType == 'update') {
            StyledSnackBar.show(
              context: context,
              message: 'Comment updated',
              type: SnackBarType.success,
            );
          } else if (state.actionType == 'delete') {
            StyledSnackBar.show(
              context: context,
              message: 'Comment deleted',
              type: SnackBarType.success,
            );
          }
        } else if (state is CommentActionError) {
          setState(() {
            _isAddingComment = false;
          });
          
          StyledSnackBar.show(
            context: context,
            message: 'Error: ${state.message}',
            type: SnackBarType.error,
          );
        }
      },
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section title
            Padding(
              padding: const EdgeInsets.only(
                left: 16.0, 
                right: 16.0,
                top: 16.0,
                bottom: 8.0,
              ),
              child: Text(
                'Comments',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            
            // Comments list
            if (state is CommentsLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (state is CommentsLoaded)
              _buildCommentsList(state.comments)
            else if (state is CommentsError)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Error loading comments: ${state.message}',
                  style: TextStyle(color: Colors.red[700]),
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('No comments yet. Be the first to comment!'),
              ),
            
            // Add comment section
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentController,
                      focusNode: _commentFocusNode,
                      maxLines: 3,
                      minLines: 1,
                      decoration: InputDecoration(
                        hintText: _editingCommentId != null
                            ? 'Edit your comment...'
                            : 'Add a comment...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16.0),
                          borderSide: BorderSide(
                            color: Colors.grey.shade300,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12.0,
                          vertical: 8.0,
                        ),
                        suffixIcon: _editingCommentId != null
                            ? IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: _cancelEditing,
                              )
                            : null,
                      ),
                      enabled: !_isAddingComment,
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  _isAddingComment
                      ? const SizedBox(
                          width: 24.0,
                          height: 24.0,
                          child: CircularProgressIndicator(strokeWidth: 2.0),
                        )
                      : IconButton(
                          icon: const Icon(Icons.send),
                          color: AppColors.primary,
                          onPressed: _handleAddComment,
                        ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCommentsList(List<RuckComment> comments) {
    // Sort comments by date (newest first)
    final sortedComments = List<RuckComment>.from(comments)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    
    // Limit displayed comments if maxDisplayed is set
    final displayedComments = widget.maxDisplayed != null && 
                              sortedComments.length > widget.maxDisplayed!
        ? sortedComments.take(widget.maxDisplayed!).toList()
        : sortedComments;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Comments
        ...displayedComments.map((comment) => _buildCommentItem(comment)),
        
        // "View All" button if needed
        if (widget.showViewAllButton && 
            widget.maxDisplayed != null && 
            sortedComments.length > widget.maxDisplayed!)
          Padding(
            padding: const EdgeInsets.only(
              left: 16.0, 
              right: 16.0, 
              bottom: 8.0,
            ),
            child: TextButton(
              onPressed: widget.onViewAllTapped,
              child: Text(
                'View all ${sortedComments.length} comments',
                style: TextStyle(color: AppColors.primary),
              ),
            ),
          ),
        
        // No comments message
        if (comments.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text('No comments yet. Be the first to comment!'),
          ),
      ],
    );
  }

  Widget _buildCommentItem(RuckComment comment) {
    final isCurrentUserComment = comment.userId == _currentUserId;
    final formattedDate = DateFormat('MMM d, yyyy • h:mm a').format(comment.createdAt);
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: isCurrentUserComment ? Colors.blue.shade50 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: username and actions
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // User info
              Expanded(
                child: Row(
                  children: [
                    // Avatar placeholder
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        shape: BoxShape.circle,
                      ),
                      child: comment.userAvatarUrl != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                comment.userAvatarUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.person,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            )
                          : const Icon(
                              Icons.person,
                              size: 16,
                              color: Colors.white,
                            ),
                    ),
                    const SizedBox(width: 8),
                    // Username and timestamp
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            comment.userDisplayName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            formattedDate,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              // Action buttons for user's own comments
              if (isCurrentUserComment) ...[
                IconButton(
                  icon: const Icon(Icons.edit, size: 18),
                  onPressed: () => _handleEditComment(comment),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4.0),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: const Icon(Icons.delete, size: 18),
                  onPressed: () => _handleDeleteComment(comment),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4.0),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ],
          ),
          
          // Comment content
          Padding(
            padding: const EdgeInsets.only(top: 8.0, left: 32.0),
            child: Text(comment.content),
          ),
          
          // Edited indicator
          if (comment.isEdited)
            Padding(
              padding: const EdgeInsets.only(top: 4.0, left: 32.0),
              child: Text(
                '(edited)',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
