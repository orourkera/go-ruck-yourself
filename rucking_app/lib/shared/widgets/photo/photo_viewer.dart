import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:rucking_app/core/services/image_cache_manager.dart';

/// A fullscreen photo viewer with zoom and swipe navigation capabilities
class PhotoViewer extends StatefulWidget {
  /// List of photo URLs to display
  final List<String> photoUrls;

  /// Initial photo index to display
  final int initialIndex;

  /// Optional callback when the viewer is closed
  final VoidCallback? onClose;

  /// Optional title to display in the app bar
  final String? title;

  /// Constructor for the fullscreen photo viewer
  const PhotoViewer({
    Key? key,
    required this.photoUrls,
    this.initialIndex = 0,
    this.onClose,
    this.title,
  }) : super(key: key);

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.photoUrls.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    if (_pageController.hasClients) {
      _pageController.dispose();
    }
    super.dispose();
  }

  void _handleClose() {
    Navigator.of(context).pop();
    if (widget.onClose != null) {
      widget.onClose!();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.5),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: _handleClose,
        ),
        title: widget.title != null
            ? Text(
                widget.title!,
                style: const TextStyle(color: Colors.white),
              )
            : Text(
                '${_currentIndex + 1} / ${widget.photoUrls.length}',
                style: const TextStyle(color: Colors.white),
              ),
        actions: [
          // Share button example (can be customized)
          IconButton(
            icon: const Icon(Icons.share, color: Colors.white),
            onPressed: () {
              // Share functionality could be implemented here
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Sharing photo ${_currentIndex + 1}')),
              );
            },
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () {
          // Toggle app bar visibility
          // This would require more state management to implement
        },
        child: PageView.builder(
          controller: _pageController,
          itemCount: widget.photoUrls.length,
          onPageChanged: (index) {
            if (mounted && index >= 0 && index < widget.photoUrls.length) {
              setState(() {
                _currentIndex = index;
              });
            }
          },
          itemBuilder: (context, index) {
            if (index < 0 || index >= widget.photoUrls.length) {
              return Container(); // Safety fallback
            }
            return Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 3.0,
                onInteractionStart: (details) {},
                child: Hero(
                  tag: 'photo_${widget.photoUrls[index]}',
                  child: CachedNetworkImage(
                    cacheManager: ImageCacheManager.instance,
                    imageUrl: widget.photoUrls[index],
                    fit: BoxFit.contain,
                    placeholder: (context, url) => const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                    errorWidget: (context, url, error) => const Center(
                      child: Icon(Icons.error_outline,
                          color: Colors.red, size: 42),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
      // Optional bottom navigation for additional controls
      bottomNavigationBar: Container(
        height: 60,
        color: Colors.black.withOpacity(0.5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Previous photo button
            IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
              onPressed: _currentIndex > 0
                  ? () {
                      _pageController.animateToPage(
                        _currentIndex - 1,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    }
                  : null,
            ),
            // Zoom out button
            IconButton(
              icon: const Icon(Icons.zoom_out, color: Colors.white),
              onPressed: () {
                // This would require InteractiveViewer controller to implement
                // Currently just a placeholder
              },
            ),
            // Zoom in button
            IconButton(
              icon: const Icon(Icons.zoom_in, color: Colors.white),
              onPressed: () {
                // This would require InteractiveViewer controller to implement
                // Currently just a placeholder
              },
            ),
            // Next photo button
            IconButton(
              icon: const Icon(Icons.arrow_forward_ios, color: Colors.white),
              onPressed: _currentIndex < widget.photoUrls.length - 1
                  ? () {
                      _pageController.animateToPage(
                        _currentIndex + 1,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
