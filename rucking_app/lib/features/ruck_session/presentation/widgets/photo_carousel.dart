import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// A carousel widget to display ruck session photos
class PhotoCarousel extends StatefulWidget {
  /// List of photo URLs to display
  final List<String> photoUrls;
  
  /// Optional callback when a photo is tapped
  final Function(int index)? onPhotoTap;
  
  /// Optional callback when user wants to delete a photo
  final Function(int index)? onDeleteRequest;
  
  /// Whether to show delete buttons for photos
  final bool showDeleteButtons;
  
  /// Height of the carousel
  final double height;
  
  /// Whether this is editable or view-only
  final bool isEditable;
  
  /// Constructor for the photo carousel
  const PhotoCarousel({
    Key? key,
    required this.photoUrls,
    this.onPhotoTap,
    this.onDeleteRequest,
    this.showDeleteButtons = false,
    this.height = 240.0,
    this.isEditable = false,
  }) : super(key: key);

  @override
  State<PhotoCarousel> createState() => _PhotoCarouselState();
}

class _PhotoCarouselState extends State<PhotoCarousel> {
  late PageController _pageController;
  int _currentPage = 0;
  
  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0, viewportFraction: 0.85);
  }
  
  @override
  void didUpdateWidget(PhotoCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Reset the carousel when the photoUrls list changes (e.g., after a deletion)
    if (widget.photoUrls.length != oldWidget.photoUrls.length) {
      // If we're currently viewing a page that no longer exists, reset to the max available index
      if (_currentPage >= widget.photoUrls.length && widget.photoUrls.isNotEmpty) {
        _currentPage = widget.photoUrls.length - 1;
        _pageController.jumpToPage(_currentPage);
      }
      setState(() {});
    }
  }
  
  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    if (widget.photoUrls.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Text(
            'No photos yet',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }
    
    return Column(
      children: [
        SizedBox(
          height: widget.height,
          child: PageView.builder(
            controller: _pageController,
            itemCount: widget.photoUrls.length,
            onPageChanged: (index) {
              setState(() {
                _currentPage = index;
              });
            },
            itemBuilder: (context, index) {
              return _buildPhotoItem(context, index);
            },
          ),
        ),
        const SizedBox(height: 12),
        // Pagination indicators
        if (widget.photoUrls.length > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.photoUrls.length, (index) {
              return Container(
                width: 8.0,
                height: 8.0,
                margin: const EdgeInsets.symmetric(horizontal: 4.0),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _currentPage == index
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey.shade300,
                ),
              );
            }),
          ),
      ],
    );
  }
  
  // Helper method to load images with error handling
  Widget _buildImageWithErrorHandling(int index) {
    final String imageUrl = widget.photoUrls[index];
    
    // Log URL for debugging
    AppLogger.info('Loading image from URL: $imageUrl');
    
    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      // Use a loading placeholder
      placeholder: (context, url) => const Center(
        child: CircularProgressIndicator(),
      ),
      errorWidget: (context, url, error) {
        AppLogger.error('Error loading image: $url, error: $error');
        return Container(
          color: Colors.grey.shade300,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.broken_image, color: Colors.red, size: 32),
                const SizedBox(height: 8),
                Text(
                  'Image failed to load',
                  style: TextStyle(color: Colors.red.shade800),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildPhotoItem(BuildContext context, int index) {
    return GestureDetector(
      onTap: () {
        if (widget.onPhotoTap != null) {
          widget.onPhotoTap!(index);
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 8.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 5.0,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Photo
            ClipRRect(
              borderRadius: BorderRadius.circular(15.0),
              child: _buildImageWithErrorHandling(index),
            ),
            
            // Delete button (if allowed)
            if (widget.showDeleteButtons && widget.isEditable)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.white),
                    onPressed: () {
                      // Show confirmation dialog
                      showDialog(
                        context: context,
                        builder: (BuildContext context) {
                          return AlertDialog(
                            title: const Text('Delete Photo'),
                            content: const Text(
                              'Are you sure you want to delete this photo? This action cannot be undone.'
                            ),
                            actions: [
                              TextButton(
                                child: const Text('CANCEL'),
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                              TextButton(
                                child: const Text('DELETE'),
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  if (widget.onDeleteRequest != null) {
                                    widget.onDeleteRequest!(index);
                                  }
                                },
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A fullscreen photo viewer with zoom and swipe capabilities
class FullscreenPhotoViewer extends StatefulWidget {
  final List<String> photoUrls;
  final int initialIndex;
  
  const FullscreenPhotoViewer({
    Key? key,
    required this.photoUrls,
    this.initialIndex = 0,
  }) : super(key: key);

  @override
  State<FullscreenPhotoViewer> createState() => _FullscreenPhotoViewerState();
}

class _FullscreenPhotoViewerState extends State<FullscreenPhotoViewer> {
  late PageController _pageController;
  late int _currentIndex;
  
  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }
  
  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.5),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          '${_currentIndex + 1} / ${widget.photoUrls.length}',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.photoUrls.length,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        itemBuilder: (context, index) {
          return GestureDetector(
            onTap: () {
              Navigator.of(context).pop();
            },
            child: Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 3.0,
                child: CachedNetworkImage(
                  imageUrl: widget.photoUrls[index],
                  fit: BoxFit.contain,
                  placeholder: (context, url) => const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                  errorWidget: (context, url, error) => const Center(
                    child: Icon(Icons.error_outline, color: Colors.red, size: 42),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
