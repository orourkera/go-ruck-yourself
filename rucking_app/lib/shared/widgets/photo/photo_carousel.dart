import 'package:flutter/material.dart';
import 'package:rucking_app/shared/widgets/photo/photo_viewer.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

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
  
  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0, viewportFraction: 0.5);
  }
  
  @override
  void dispose() {
    _pageController.dispose();
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
    // Validate URL first
    if (imageUrl.isEmpty || !Uri.parse(imageUrl).isAbsolute) {
      AppLogger.error('Invalid image URL: $imageUrl');
      return _buildErrorContainer(context, 'Invalid image URL');
    }
    
    // Add a timestamp to force refresh and clean URL if needed
    final String cleanUrl = imageUrl.split('?')[0] + '?t=${DateTime.now().millisecondsSinceEpoch}';
    
    // Log URL for debugging
    AppLogger.info('Loading image from URL: $cleanUrl');
    
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15.0),
        color: Colors.grey.shade200, // Placeholder color when image is loading
      ),
      child: Image.network(
        cleanUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        // Use a loading placeholder
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) {
            return child; // Image has loaded successfully
          }
          return Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                ? loadingProgress.cumulativeBytesLoaded / (loadingProgress.expectedTotalBytes ?? 1)
                : null,
            ),
          );
        },
        // Add headers to force reload and bypass cache
        headers: const {
          'Cache-Control': 'no-cache, no-store, must-revalidate',
          'Pragma': 'no-cache',
          'Expires': '0',
        },
        errorBuilder: (context, error, stackTrace) {
          AppLogger.error('Error loading image: $cleanUrl, error: $error');
          return _buildErrorContainer(context, 'Image failed to load');
        },
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
