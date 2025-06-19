import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/events/domain/models/event_comment.dart';
import 'package:rucking_app/features/events/presentation/bloc/event_comments_bloc.dart';
import 'package:rucking_app/features/events/presentation/bloc/event_comments_event.dart';
import 'package:rucking_app/features/events/presentation/bloc/event_comments_state.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/skeleton/skeleton_loader.dart';
import 'package:rucking_app/shared/widgets/skeleton/skeleton_widgets.dart';
import 'package:rucking_app/shared/widgets/error_display.dart';
import 'package:rucking_app/shared/widgets/styled_snackbar.dart';

class EventCommentsSection extends StatefulWidget {
  final String eventId;

  const EventCommentsSection({
    Key? key,
    required this.eventId,
  }) : super(key: key);

  @override
  State<EventCommentsSection> createState() => _EventCommentsSectionState();
}

class _EventCommentsSectionState extends State<EventCommentsSection> {
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final authState = context.read<AuthBloc>().state;
    final userId = authState is Authenticated ? authState.user.userId : null;
    
    return Column(
      children: [
        // Comments list
        Expanded(
          child: BlocConsumer<EventCommentsBloc, EventCommentsState>(
            listener: (context, state) {
              if (state is EventCommentActionSuccess) {
                _commentController.clear();
                _commentFocusNode.unfocus();
                setState(() {
                  _isSubmitting = false;
                });
                
                StyledSnackBar.showSuccess(
                  context: context,
                  message: 'Comment added successfully',
                );
              } else if (state is EventCommentsError) {
                setState(() {
                  _isSubmitting = false;
                });
                
                StyledSnackBar.showError(
                  context: context,
                  message: state.message,
                );
              }
            },
            builder: (context, state) {
              if (state is EventCommentsLoading) {
                return _buildLoadingSkeleton();
              } else if (state is EventCommentsError) {
                return ErrorDisplay(
                  message: state.message,
                  onRetry: () {
                    context.read<EventCommentsBloc>().add(
                      LoadEventComments(widget.eventId),
                    );
                  },
                );
              } else if (state is EventCommentsLoaded) {
                final comments = state.comments;
                
                return _buildCommentsList(comments, isDarkMode, userId);
              }
              
              return _buildLoadingSkeleton();
            },
          ),
        ),
        
        // Comment input
        _buildCommentInput(isDarkMode),
      ],
    );
  }

  Widget _buildLoadingSkeleton() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 3,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SkeletonCircle(size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonLine(width: 100),
                    SizedBox(height: 4),
                    SkeletonLine(width: double.infinity),
                    SizedBox(height: 2),
                    SkeletonLine(width: 200),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCommentsList(List<EventComment> comments, bool isDarkMode, String? userId) {
    if (comments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 80,
              color: Colors.grey.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No comments yet',
              style: AppTextStyles.titleMedium.copyWith(
                color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Be the first to comment on this event!',
              style: AppTextStyles.bodyMedium.copyWith(
                color: isDarkMode ? Colors.grey[500] : Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }
    
    return RefreshIndicator(
      onRefresh: () async {
        context.read<EventCommentsBloc>().add(
          RefreshEventComments(widget.eventId),
        );
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: comments.length,
        itemBuilder: (context, index) {
          final comment = comments[index];
          return _buildCommentItem(comment, isDarkMode, userId);
        },
      ),
    );
  }

  Widget _buildCommentItem(EventComment comment, bool isDarkMode, String? userId) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User avatar
          CircleAvatar(
            radius: 16,
            backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
            child: Text(
              (comment.user?.firstName.isNotEmpty == true 
                  ? comment.user!.firstName[0].toUpperCase()
                  : '?'),
              style: AppTextStyles.bodySmall.copyWith(
                color: Theme.of(context).primaryColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          
          const SizedBox(width: 12),
          
          // Comment content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // User name and timestamp
                Row(
                  children: [
                    Text(
                      comment.user?.fullName ?? 'Unknown User',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: isDarkMode ? Colors.white : Colors.black,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatCommentTime(comment.createdAt),
                      style: AppTextStyles.bodySmall.copyWith(
                        color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 4),
                
                // Comment text
                Text(
                  comment.comment,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                  ),
                ),
                
                // Comment metadata
                if (comment.updatedAt != comment.createdAt)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Edited ${_formatCommentTime(comment.updatedAt)}',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: isDarkMode ? Colors.grey[500] : Colors.grey[500],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          
          // Comment actions (for owner)
          if (comment.userId == userId)
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert,
                size: 16,
                color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
              ),
              onSelected: (value) {
                if (value == 'edit') {
                  _showEditCommentDialog(comment);
                } else if (value == 'delete') {
                  _showDeleteCommentDialog(comment);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Text('Edit'),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildCommentInput(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.black : null,
        border: Border(
          top: BorderSide(
            color: Colors.grey.withOpacity(0.2),
          ),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _commentController,
                focusNode: _commentFocusNode,
                decoration: InputDecoration(
                  hintText: 'Add a comment...',
                  hintStyle: AppTextStyles.bodyMedium.copyWith(
                    color: isDarkMode ? Colors.grey[500] : Colors.grey[500],
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(
                      color: Colors.grey.withOpacity(0.3),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                enabled: !_isSubmitting,
              ),
            ),
            
            const SizedBox(width: 8),
            
            // Send button
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.send, color: Colors.white),
                onPressed: _isSubmitting || _commentController.text.trim().isEmpty
                    ? null
                    : _submitComment,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _submitComment() {
    final content = _commentController.text.trim();
    if (content.isEmpty) return;
    
    setState(() {
      _isSubmitting = true;
    });
    
    context.read<EventCommentsBloc>().add(
      AddEventComment(
        eventId: widget.eventId,
        comment: content,
      ),
    );
  }

  void _showEditCommentDialog(EventComment comment) {
    final editController = TextEditingController(text: comment.comment);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Comment'),
        content: TextField(
          controller: editController,
          decoration: const InputDecoration(
            hintText: 'Enter your comment...',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final newContent = editController.text.trim();
              if (newContent.isNotEmpty && newContent != comment.comment) {
                context.read<EventCommentsBloc>().add(
                  UpdateEventComment(
                    eventId: widget.eventId,
                    commentId: comment.id,
                    comment: newContent,
                  ),
                );
              }
              Navigator.of(context).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showDeleteCommentDialog(EventComment comment) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Comment'),
        content: const Text('Are you sure you want to delete this comment?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              context.read<EventCommentsBloc>().add(
                DeleteEventComment(
                  eventId: widget.eventId,
                  commentId: comment.id,
                ),
              );
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  String _formatCommentTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return DateFormat('MMM d').format(dateTime);
    }
  }
}
