import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/social/domain/models/ruck_comment.dart';
import 'package:rucking_app/features/social/presentation/bloc/social_bloc.dart';
import 'package:rucking_app/features/social/presentation/bloc/social_event.dart';
import 'package:rucking_app/features/social/presentation/bloc/social_state.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/widgets/styled_snackbar.dart';

/// A widget for displaying and interacting with comments on a ruck session
class CommentsSection extends StatefulWidget {
  /// ID of the ruck session
  final String ruckId;
  
  /// Maximum number of comments to display at once
  final int? maxDisplayed;
  
  /// Whether to show the "View All" button when there are more comments
  final bool showViewAllButton;
  
  /// Callback when "View All" is tapped
  final VoidCallback? onViewAllTapped;
  
  /// Whether to hide the comment input field
  final bool hideInput;
  
  /// Callback when a comment edit button is pressed, allows parent to handle editing
  final Function(RuckComment)? onEditCommentRequest;

  /// Creates a comment section for ruck sessions
  const CommentsSection({
    Key? key,
    required this.ruckId,
    this.maxDisplayed,
    this.showViewAllButton = true,
    this.onViewAllTapped,
    this.hideInput = false,
    this.onEditCommentRequest,
  }) : super(key: key);

  @override
  State<CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<CommentsSection> {
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();
  bool _isAddingComment = false;
  String? _editingCommentId;
  bool _commentsLoaded = false; // Track if comments have been loaded to prevent duplicate requests
  
  // Store loaded comments locally to keep them across all state changes
  List<RuckComment> _currentComments = [];
  
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
    
    // Load comments on init
    debugPrint('[COMMENT_DEBUG] CommentsSection initState for ruckId: ${widget.ruckId}');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('[COMMENT_DEBUG] CommentsSection loading comments for ruckId: ${widget.ruckId}');
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
    
    Future.microtask(() {
      if (mounted) {
        _commentController.clear();
        _commentFocusNode.unfocus();
      }
    });
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
    debugPrint('[COMMENT_DEBUG] CommentsSection build called for ruckId: ${widget.ruckId}');
    
    // Check authentication state
    bool isAuthenticated = false;
    try {
      final authState = context.read<AuthBloc>().state;
      isAuthenticated = authState is Authenticated;
      
      if (!isAuthenticated) {
        debugPrint('[COMMENT_DEBUG] User is not authenticated, disabling comment features');
      }
    } catch (e) {
      debugPrint('[COMMENT_DEBUG] Error checking auth state: $e');
    }
    
    // Manually trigger load if no comments are loaded yet and user is authenticated
    if (!_commentsLoaded && isAuthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        debugPrint('[COMMENT_DEBUG] CommentsSection forcing load of comments for ruckId: ${widget.ruckId}');
        context.read<SocialBloc>().add(LoadRuckComments(widget.ruckId));
        _commentsLoaded = true;
      });
    }
    
    return BlocConsumer<SocialBloc, SocialState>(
      listenWhen: (previous, current) {
        // Improved listening for any comment-related states
        final relevantState = current is CommentsLoaded || 
                            current is CommentActionCompleted || 
                            current is CommentActionError;
        
        // Check if this is for our specific ruck ID
        bool isForThisRuck = false;
        if (current is CommentsLoaded) {
          isForThisRuck = current.ruckId == widget.ruckId;
        } else if (current is CommentActionCompleted && current.comment != null) {
          isForThisRuck = current.comment!.ruckId == widget.ruckId;
        }
        
        debugPrint('[COMMENT_DEBUG] CommentsSection listenWhen: previous=${previous.runtimeType}, current=${current.runtimeType}, relevantState=$relevantState, isForThisRuck=$isForThisRuck');
        
        return relevantState && (current is CommentActionError || isForThisRuck);
      },
      listener: (context, state) {
        debugPrint('[COMMENT_DEBUG] CommentsSection listener fired with state: ${state.runtimeType}');
        
        if (state is CommentActionCompleted) {
          setState(() {
            _isAddingComment = false;
            _editingCommentId = null;
            _commentController.clear(); // Clear the text field after successful submission
          });
          
          // Automatically refresh comments list after an action
          debugPrint('[COMMENT_DEBUG] CommentActionCompleted, refreshing comments for ruckId: ${widget.ruckId}');
          context.read<SocialBloc>().add(LoadRuckComments(widget.ruckId));
          
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
        } else if (state is CommentsLoaded) {
          debugPrint('[COMMENT_DEBUG] CommentsLoaded state with ${state.comments.length} comments for ruckId: ${state.ruckId}');
          // Store comments in local state when they're loaded
          if (state.ruckId == widget.ruckId) {
            setState(() {
              _currentComments = List<RuckComment>.from(state.comments);
            });
          }
        }
      },
      builder: (context, state) {
        debugPrint('[COMMENT_DEBUG] CommentsSection builder with state: ${state.runtimeType}');
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section title removed per user request
            
            // Comments list
            if (state is CommentsLoading && _currentComments.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (state is CommentsLoaded && state.ruckId == widget.ruckId)
              _buildCommentsList(state.comments)
            // Use stored comments when we have a CommentCountUpdated state or other states
            else if (_currentComments.isNotEmpty)
              _buildCommentsList(_currentComments)
            else if (state is CommentsError)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Error loading comments: ${state.message}',
                  style: TextStyle(color: Colors.red[700]),
                ),
              )
            else
              const SizedBox(), // Empty placeholder instead of 'Loading comments...'
            
            // Add comment section - only show if hideInput is false and user is authenticated
            if (!widget.hideInput)
              Builder(builder: (context) {
                // Check authentication state again here to be extra safe
                bool isAuthenticated = false;
                try {
                  final authState = context.read<AuthBloc>().state;
                  isAuthenticated = authState is Authenticated;
                } catch (e) {
                  debugPrint('[COMMENT_DEBUG] Error checking auth state in comment input: $e');
                }
                
                // If not authenticated, show login prompt instead of comment field
                if (!isAuthenticated) {
                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(16.0),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lock_outline, color: Colors.grey),
                          const SizedBox(width: 8.0),
                          const Expanded(child: Text('Please log in to add comments')),
                          TextButton(
                            onPressed: () {
                              // Navigate to login screen or show login dialog
                              Navigator.of(context).pushNamed('/login');
                            },
                            child: const Text('Log In'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                
                // Show normal comment input if authenticated
                return Padding(
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
              );
            }),
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
    // Safely handle potentially null or invalid values
    String? currentUserId;
    try {
      currentUserId = _getCurrentUserId(context);
    } catch (e) {
      debugPrint('[COMMENT_DEBUG] Error getting current user ID: $e');
      currentUserId = null;
    }
    
    // Safe comparison that won't crash if userId is null or invalid
    final isCurrentUserComment = currentUserId != null && comment.userId == currentUserId;
    
    // Safely format date
    String formattedDate;
    try {
      formattedDate = DateFormat('MMM d, yyyy • h:mm a').format(comment.createdAt);
    } catch (e) {
      debugPrint('[COMMENT_DEBUG] Error formatting date: $e');
      formattedDate = 'Date unavailable';
    }
    
    final isEditing = _editingCommentId == comment.id;
    
    // Create a controller for editing if this comment is being edited
    if (isEditing && _commentController.text != comment.content) {
      // Safely set text content
      try {
        _commentController.text = comment.content;
        // Request focus after setting text
        Future.delayed(Duration.zero, () {
          if (mounted) {
            _commentFocusNode.requestFocus();
          }
        });
      } catch (e) {
        debugPrint('[COMMENT_DEBUG] Error setting comment text: $e');
      }
    }
    
    // Safely create UI elements with defensive error handling
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        // Use safe color access with fallbacks
        color: isCurrentUserComment ? 
            Colors.blue.shade50 : 
            Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          // Safely handle colors and widths with defaults to prevent NaN
          color: isEditing ? AppColors.primary : Colors.grey.shade200,
          width: isEditing ? 2.0 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // User info
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.grey.shade300,
                    child: const Icon(Icons.person, color: Colors.white),
                  ),
                  const SizedBox(width: 8.0),
                  Text(
                    comment.userDisplayName.isNotEmpty ? comment.userDisplayName : 'User',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              
              // Action buttons - show different buttons based on edit state
              if (isCurrentUserComment)
                isEditing
                  ? Row(
                      children: [
                        // Save button
                        TextButton(
                          onPressed: () {
                            // Update the comment
                            context.read<SocialBloc>().add(
                              UpdateRuckComment(
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
          
          // Date
          Padding(
            padding: const EdgeInsets.only(left: 40.0, top: 4.0),
            child: Text(
              formattedDate,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
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
