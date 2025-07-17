import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/social/presentation/bloc/social_bloc.dart';
import 'package:rucking_app/features/social/presentation/bloc/social_event.dart';
import 'package:rucking_app/features/social/presentation/bloc/social_state.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';

/// A button widget for liking/unliking ruck sessions
class RuckLikeButton extends StatefulWidget {
  /// ID of the ruck session (nullable to handle missing data)
  final int? ruckId;
  
  /// Initial like count (optional)
  final int initialLikeCount;
  
  /// Initial like state (optional)
  final bool initialIsLiked;
  
  /// Whether to show the like count
  final bool showCount;
  
  /// Size of the button
  final double size;
  
  /// Whether to animate the button when pressed
  final bool animate;
  
  /// Callback when like status changes
  final Function(bool isLiked)? onLikeChanged;

  /// Creates a like button for ruck sessions
  const RuckLikeButton({
    Key? key,
    this.ruckId,
    this.initialLikeCount = 0,
    this.initialIsLiked = false,
    this.showCount = true,
    this.size = 24.0,
    this.animate = true,
    this.onLikeChanged,
  }) : super(key: key);

  @override
  State<RuckLikeButton> createState() => _RuckLikeButtonState();
}

class _RuckLikeButtonState extends State<RuckLikeButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  
  bool _isLiked = false;
  int _likeCount = 0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    
    _isLiked = widget.initialIsLiked;
    _likeCount = widget.initialLikeCount;
    
    // Setup animation controller
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.3),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.3, end: 1.0),
        weight: 50,
      ),
    ]).animate(_animationController);
    
    // Check like status on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.ruckId != null) {
        context.read<SocialBloc>().add(CheckUserLikeStatus(widget.ruckId!));
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _handleLikeTap() {
    if (_isLoading) return; // Prevent multiple taps
    
    if (widget.animate) {
      _animationController.forward(from: 0.0);
    }
    
    // Add null check to prevent TypeError when ruckId is null
    if (widget.ruckId != null) {
      context.read<SocialBloc>().add(ToggleRuckLike(widget.ruckId!));
    } else {
      print('Warning: Attempted to like a ruck session with null ruckId');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Don't render the widget if ruckId is null
    if (widget.ruckId == null) {
      return const SizedBox.shrink();
    }
    
    return BlocConsumer<SocialBloc, SocialState>(
      listenWhen: (previous, current) {
        // Listen only for states related to likes
        return current is LikesLoaded || 
               current is LikeActionCompleted || 
               current is LikeActionError;
      },
      listener: (context, state) {
        if (state is LikesLoaded && state.ruckId == widget.ruckId) {
          setState(() {
            _isLiked = state.userHasLiked;
            _likeCount = state.likes.length;
            _isLoading = false;
          });
          
          if (widget.onLikeChanged != null) {
            widget.onLikeChanged!(_isLiked);
          }
        } else if (state is LikeActionCompleted && state.ruckId == widget.ruckId) {
          setState(() {
            _isLiked = state.isLiked;
            // We'll update the count when LikesLoaded comes in
            _isLoading = false;
          });
          
          if (widget.onLikeChanged != null) {
            widget.onLikeChanged!(_isLiked);
          }
        } else if (state is LikeActionInProgress) {
          setState(() {
            _isLoading = true;
          });
        } else if (state is LikeActionError) {
          setState(() {
            _isLoading = false;
          });
          
          // Show error
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${state.message}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
      builder: (context, state) {
        // Update UI based on state changes
        if (state is LikesLoaded && state.ruckId == widget.ruckId) {
          _isLiked = state.userHasLiked;
          _likeCount = state.likes.length;
        } else if (state is LikeActionCompleted && state.ruckId == widget.ruckId) {
          _isLiked = state.isLiked;
          // Like count will be updated when LikesLoaded comes in
        }
        
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Like button with animation
            GestureDetector(
              onTap: _handleLikeTap,
              child: AnimatedBuilder(
                animation: _scaleAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: widget.animate ? _scaleAnimation.value : 1.0,
                    child: child,
                  );
                },
                child: _isLoading
                    ? SizedBox(
                        width: widget.size,
                        height: widget.size,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.0,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.primary,
                          ),
                        ),
                      )
                    : Image.asset(
                        _isLiked 
                            ? 'assets/images/tactical_ruck_like_icon_active.png'
                            : 'assets/images/tactical_ruck_like_icon_transparent.png',
                        width: widget.size,
                        height: widget.size,
                      ),
              ),
            ),
            
            // Like count
            if (widget.showCount) ...[
              const SizedBox(width: 4),
              Text(
                '$_likeCount',
                style: TextStyle(
                  color: _isLiked ? AppColors.primary : Colors.grey,
                  fontWeight: _isLiked ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
