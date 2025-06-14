import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/duel_comment.dart';
import '../bloc/duel_detail/duel_detail_bloc.dart';
import '../bloc/duel_detail/duel_detail_event.dart';
import '../bloc/duel_detail/duel_detail_state.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/styled_snackbar.dart';
import '../../../../shared/widgets/user_avatar.dart';

/// A widget for displaying and interacting with comments on a duel
class DuelCommentsSection extends StatefulWidget {
  /// ID of the duel
  final String duelId;
  
  /// Maximum number of comments to display at once
  final int? maxDisplayed;
  
  /// Whether to show the "View All" button when there are more comments
  final bool showViewAllButton;
  
  /// Callback when "View All" is tapped
  final VoidCallback? onViewAllTapped;
  
  /// Whether to hide the comment input field
  final bool hideInput;
  
  /// Callback when a comment edit button is pressed, allows parent to handle editing
  final Function(String commentId, String currentText)? onEditCommentRequest;

  /// Creates a comment section for duels
  const DuelCommentsSection({
    Key? key,
    required this.duelId,
    this.maxDisplayed,
    this.showViewAllButton = true,
    this.onViewAllTapped,
    this.hideInput = false,
    this.onEditCommentRequest,
  }) : super(key: key);

  @override
  State<DuelCommentsSection> createState() => _DuelCommentsSectionState();
}

class _DuelCommentsSectionState extends State<DuelCommentsSection> {
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();
  bool _isAddingComment = false;
  String? _editingCommentId;
  bool _commentsLoaded = false; // Track if comments have been loaded to prevent duplicate requests
  
  // Store loaded comments locally to keep them across all state changes
  List<DuelComment> _currentComments = [];
  
  // Get the current user ID from the AuthBloc
  String? _getCurrentUserId(BuildContext context) {
    try {
      final authState = context.read<AuthBloc>().state;
      if (authState is Authenticated) {
        return authState.user.userId;
      }
      return null;
    } catch (e) {
      debugPrint('Error getting current user ID: $e');
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    
    // Always try to load comments - if user isn't a participant, we'll handle the error gracefully
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DuelDetailBloc>().add(LoadDuelComments(duelId: widget.duelId));
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
      context.read<DuelDetailBloc>().add(
        UpdateDuelComment(
          commentId: _editingCommentId!,
          content: _commentController.text.trim(),
        ),
      );
    } else {
      // Add new comment
      context.read<DuelDetailBloc>().add(
        AddDuelComment(
          duelId: widget.duelId,
          content: _commentController.text.trim(),
        ),
      );
    }
    
    Future.microtask(() {
      if (mounted) {
        _commentController.clear();
        _commentFocusNode.unfocus();
      }
    });
  }

  void _handleEditComment(DuelComment comment) {
    setState(() {
      _editingCommentId = comment.id;
      _commentController.text = comment.content;
    });
    _commentFocusNode.requestFocus();
  }

  void _handleDeleteComment(DuelComment comment) {
    // Show confirmation dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Comment'),
        content: const Text('Are you sure you want to delete this comment? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.read<DuelDetailBloc>().add(DeleteDuelComment(commentId: comment.id));
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _cancelEditing() {
    setState(() {
      _editingCommentId = null;
    });
    _commentController.clear();
    _commentFocusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<DuelDetailBloc, DuelDetailState>(
      listener: (context, state) {
        if (state is DuelDetailLoaded) {
          // Update local comments state
          setState(() {
            _currentComments = state.comments;
            _commentsLoaded = true;
            _isAddingComment = false;
          });
          
          // Cancel editing if we were editing
          if (_editingCommentId != null) {
            _cancelEditing();
          }
        } else if (state is DuelDetailError && state.message.contains('comment')) {
          // Handle specific "must be participant" error gracefully
          if (state.message.contains('must be a participant') || 
              state.message.contains('participant to view comments')) {
            // Don't show error snackbar for participant restriction - handle it in UI
            setState(() {
              _isAddingComment = false;
            });
          } else {
            // Show error for other comment operations
            StyledSnackBar.showError(
              context: context,
              message: state.message,
            );
            setState(() {
              _isAddingComment = false;
            });
          }
        }
      },
      child: BlocBuilder<DuelDetailBloc, DuelDetailState>(
        builder: (context, state) {
          List<DuelComment> comments = _currentComments;
          bool canViewComments = false;
          
          if (state is DuelDetailLoaded) {
            comments = state.comments;
            canViewComments = state.canViewComments;
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Comments list (only show if can view comments and there are comments)
              if (canViewComments && comments.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildCommentsList(comments),
              ],
              
              // Comment input field (if not hidden and can view comments)
              if (!widget.hideInput && canViewComments) ...[
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TextField(
                          controller: _commentController,
                          focusNode: _commentFocusNode,
                          decoration: InputDecoration(
                            hintText: _editingCommentId != null 
                                ? 'Update your comment...' 
                                : 'Add a comment...',
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.all(16),
                          ),
                          maxLines: null,
                          textInputAction: TextInputAction.newline,
                        ),
                      ),
                      
                      const SizedBox(height: 12),
                      
                      // Action buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (_editingCommentId != null) ...[
                            TextButton(
                              onPressed: _cancelEditing,
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 8),
                          ],
                          ElevatedButton(
                            onPressed: _isAddingComment ? null : _handleAddComment,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              minimumSize: Size.zero,
                            ),
                            child: _isAddingComment
                                ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : Text(_editingCommentId != null ? 'Update' : 'Post'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              
              // Show message when user cannot view comments
              if (!canViewComments) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lock_outline,
                        color: Colors.grey.shade600,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Join this duel to view and participate in discussions',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildCommentsList(List<DuelComment> comments) {
    // Apply maxDisplayed limit if specified
    List<DuelComment> displayedComments = comments;
    if (widget.maxDisplayed != null && comments.length > widget.maxDisplayed!) {
      displayedComments = comments.take(widget.maxDisplayed!).toList();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        children: [
          ...displayedComments.map((comment) => _buildCommentItem(comment)),
          
          // "View All" button if there are more comments
          if (widget.maxDisplayed != null && 
              comments.length > widget.maxDisplayed! && 
              widget.showViewAllButton)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: TextButton(
                onPressed: widget.onViewAllTapped,
                child: Text(
                  'View all ${comments.length} comments',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCommentItem(DuelComment comment) {
    final currentUserId = _getCurrentUserId(context);
    final isCurrentUserComment = currentUserId == comment.userId;
    final isEditing = _editingCommentId == comment.id;
    
    // Format date
    final now = DateTime.now();
    final difference = now.difference(comment.createdAt);
    String formattedDate;
    
    if (difference.inDays > 7) {
      formattedDate = DateFormat('MMM d, y').format(comment.createdAt);
    } else if (difference.inDays > 0) {
      formattedDate = '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      formattedDate = '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      formattedDate = '${difference.inMinutes}m ago';
    } else {
      formattedDate = 'Just now';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User info and actions
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar
              UserAvatar(
                avatarUrl: comment.userAvatarUrl,
                username: comment.userDisplayName,
                size: 32,
              ),
              
              const SizedBox(width: 12),
              
              // User name and time
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      comment.userDisplayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
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
              
              // Edit/Delete buttons (only for current user's comments)
              if (isCurrentUserComment)
                isEditing
                  ? Row(
                      children: [
                        // Save button
                        TextButton(
                          onPressed: () {
                            // Update the comment
                            context.read<DuelDetailBloc>().add(
                              UpdateDuelComment(
                                commentId: comment.id,
                                content: _commentController.text.trim(),
                              ),
                            );
                            
                            // Clear editing state
                            setState(() {
                              _editingCommentId = null;
                            });
                            _commentController.clear();
                            _commentFocusNode.unfocus();
                          },
                          child: const Text('Save'),
                        ),
                        // Cancel button
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _editingCommentId = null;
                            });
                            _commentController.clear();
                            _commentFocusNode.unfocus();
                          },
                          child: const Text('Cancel'),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        // Edit button
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18),
                          onPressed: () => _handleEditComment(comment),
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(4.0),
                          visualDensity: VisualDensity.compact,
                        ),
                        // Delete button
                        IconButton(
                          icon: const Icon(Icons.delete, size: 18),
                          onPressed: () => _handleDeleteComment(comment),
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(4.0),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
            ],
          ),
          
          const SizedBox(height: 8),
          
          // Comment content - either show text or editing field
          Padding(
            padding: const EdgeInsets.only(left: 40.0),
            child: isEditing
              ? TextField(
                  controller: _commentController,
                  focusNode: _commentFocusNode,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  maxLines: null,
                  textInputAction: TextInputAction.done,
                )
              : Text(comment.content),
          ),
          
          // Edited indicator
          if (comment.isEdited && !isEditing)
            Padding(
              padding: const EdgeInsets.only(top: 4.0, left: 40.0),
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
