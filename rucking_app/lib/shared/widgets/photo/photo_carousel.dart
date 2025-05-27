import 'package:flutter/material.dart';
import 'package:rucking_app/shared/widgets/photo/photo_viewer.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// A reusable carousel widget for displaying photos
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

  /// Optional loading state 
  final bool isLoading;
  
  /// Constructor for the photo carousel
  const PhotoCarousel({
    Key? key,
    required this.photoUrls,
    this.onPhotoTap,
    this.onDeleteRequest,
    this.showDeleteButtons = false,
    this.height = 240.0,
    this.isEditable = false,
    this.isLoading = false,
  }) : super(key: key);

  @override
  State<PhotoCarousel> createState() => _PhotoCarouselState();
}

class _PhotoCarouselState extends State<PhotoCarousel> {
  late PageController _pageController;
  int _currentPage = 0;
  static int _instanceCounter = 0;
  late int _instanceId;
  
  @override
  void initState() {
    super.initState();
    _instanceId = ++_instanceCounter;
    print('[DEBUG] PhotoCarousel instance $_instanceId initializing with ${widget.photoUrls.length} photos');
    
    // Simple initialization - back to basics
    _pageController = PageController(initialPage: 0, viewportFraction: 0.5);
    _currentPage = 0;
  }
  
  @override
  void didUpdateWidget(PhotoCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Handle case when returning from detail screen
    // This prevents Infinity/NaN calculations when navigating back
    if (oldWidget.photoUrls != widget.photoUrls) {
      if (mounted && _pageController.hasClients) {
        _pageController.dispose();
        _pageController = PageController(initialPage: 0, viewportFraction: 0.5);
        setState(() {
          _currentPage = 0;
        });
      }
    }
  }
  
  @override
  void dispose() {
    print('[DEBUG] PhotoCarousel instance $_instanceId disposing');
    if (_pageController.hasClients) {
      _pageController.dispose();
    }
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    // Show loading state
    if (widget.isLoading) {
      return SizedBox(
        height: widget.height,
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    
    // Show empty state when there are no photos
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
    
    // Debug log all URLs to help diagnose issues
    AppLogger.info('PhotoCarousel rendering ${widget.photoUrls.length} photos');
    for (int i = 0; i < widget.photoUrls.length; i++) {
      AppLogger.info('Photo URL[$i]: ${widget.photoUrls[i]}');
    }
    
    return Column(
      children: [
        // Using enhanced PageView for image carousel
        SizedBox(
          height: widget.height,
          child: widget.photoUrls.isNotEmpty ? PageView.builder(
            controller: _pageController,
            itemCount: widget.photoUrls.length,
            // Remove default padding to eliminate left spacing
            padEnds: false,
            pageSnapping: true,
            // Remove default edge padding
            clipBehavior: Clip.none,
            onPageChanged: (int index) {
              if (mounted && index >= 0 && index < widget.photoUrls.length && index.isFinite && !index.isNaN) {
                setState(() {
                  _currentPage = index;
                });
              }
            },
            itemBuilder: (context, index) {
              if (index < 0 || index >= widget.photoUrls.length) {
                return Container(); // Safety fallback
              }
              return _buildPhotoItem(context, index);
            },
          ) : Container(
            child: widget.photoUrls.isNotEmpty 
              ? const Center(child: CircularProgressIndicator())
              : const Center(child: Text('No photos available')),
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
                    : Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey.shade700
                      : Colors.grey.shade300,
                ),
              );
            }),
          ),
      ],
    );
  }
  
  Widget _buildPhotoItem(BuildContext context, int index) {
    return GestureDetector(
      onTap: () {
        if (widget.onPhotoTap != null) {
          widget.onPhotoTap!(index);
        } else {
          // Default behavior: show fullscreen viewer
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PhotoViewer(
                photoUrls: widget.photoUrls,
                initialIndex: index,
              ),
            ),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.only(right: 10.0, top: 8.0, bottom: 8.0, left: 0),
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
              child: _buildImageWithFallback(context, index),
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
  
  // Helper method to build image with fallback options and better error handling
  Widget _buildImageWithFallback(BuildContext context, int index) {
    final String imageUrl = widget.photoUrls[index];
    // Log the attempt to load the image
    AppLogger.info('Loading image from URL: $imageUrl');
    
    return ClipRRect(
      borderRadius: BorderRadius.circular(15.0),
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        // Create a stable key based on URL to improve cache hits
        cacheKey: Uri.parse(imageUrl).pathSegments.last,
        // Memory cache optimization for thumbnails
        memCacheWidth: 300,
        memCacheHeight: 300,
        // Disk cache optimization
        maxWidthDiskCache: 600,
        maxHeightDiskCache: 600,
        // Visual settings
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        // Improve transition between placeholder and final image
        fadeOutDuration: const Duration(milliseconds: 200),
        fadeInDuration: const Duration(milliseconds: 300),
        // Error handling with detailed logging
        errorWidget: (context, url, error) {
          AppLogger.error('Error loading image: $imageUrl, error: $error');
          return _buildErrorContainer(context, 'Image failed to load');
        },
        // Improved placeholder with fade transition
        placeholder: (context, url) => Container(
          color: Colors.grey.shade200,
          child: const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.0,
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  // Helper method to build error display container
  Widget _buildErrorContainer(BuildContext context, String errorMessage) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15.0),
        color: Colors.grey.shade200,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.broken_image, color: Colors.red, size: 32),
            const SizedBox(height: 8),
            Text(
              errorMessage,
              style: TextStyle(color: Colors.red.shade800),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
