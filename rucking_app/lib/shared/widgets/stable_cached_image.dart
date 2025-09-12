import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:rucking_app/core/services/image_cache_manager.dart';
import 'package:shimmer/shimmer.dart';

/// A highly optimized wrapper around CachedNetworkImage that ensures stable image loading
/// and prevents flickering during scrolls by maintaining state properly.
///
/// Features:
/// - Progressive loading with low-res thumbnail placeholders
/// - Shimmer effects for polished loading experience
/// - Intelligent dimension handling to prevent infinity/NaN errors
/// - Fade transitions for smooth image appearance
/// - Aggressive caching with customizable cache durations
/// - AutomaticKeepAlive support for scroll performance
class StableCachedImage extends StatefulWidget {
  final String imageUrl;
  final String? thumbnailUrl;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final bool useShimmer;
  final bool useProgressiveLoading;
  final Duration fadeInDuration;
  final Duration fadeOutDuration;

  const StableCachedImage({
    super.key,
    required this.imageUrl,
    this.thumbnailUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.useShimmer = true,
    this.useProgressiveLoading = true,
    this.fadeInDuration = const Duration(milliseconds: 300),
    this.fadeOutDuration = const Duration(milliseconds: 150),
  });

  @override
  State<StableCachedImage> createState() => _StableCachedImageState();
}

class _StableCachedImageState extends State<StableCachedImage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late String _currentUrl;
  String? _currentThumbnailUrl;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.imageUrl;
    _currentThumbnailUrl = widget.thumbnailUrl;
    print(
        '[StableCachedImage] Loading image: $_currentUrl, thumbnail: $_currentThumbnailUrl');
  }

  @override
  void didUpdateWidget(StableCachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only update URLs if they actually changed to prevent unnecessary rebuilds
    if (oldWidget.imageUrl != widget.imageUrl) {
      setState(() {
        _currentUrl = widget.imageUrl;
      });
    }
    if (oldWidget.thumbnailUrl != widget.thumbnailUrl) {
      setState(() {
        _currentThumbnailUrl = widget.thumbnailUrl;
      });
    }
  }

  /// Safe dimension calculation that handles infinity values
  int? _getMemoryCacheWidth() {
    if (widget.width == null || widget.width == double.infinity) {
      return null; // Let CachedNetworkImage handle default sizing
    }
    return widget.width!.toInt();
  }

  /// Safe dimension calculation that handles infinity values
  int? _getMemoryCacheHeight() {
    if (widget.height == null || widget.height == double.infinity) {
      return null; // Let CachedNetworkImage handle default sizing
    }
    return widget.height!.toInt();
  }

  Widget _buildShimmerPlaceholder() {
    return Shimmer.fromColors(
      baseColor: const Color(0xFF4A5D23), // Army green base
      highlightColor: const Color(0xFF6B7F3A), // Lighter army green highlight
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: const Color(0xFF4A5D23), // Army green background
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Widget _buildDefaultPlaceholder() {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(
        child: Icon(
          Icons.image,
          color: Colors.grey,
          size: 32,
        ),
      ),
    );
  }

  Widget _buildProgressivePlaceholder() {
    // Use thumbnail as placeholder if available and progressive loading is enabled
    if (widget.useProgressiveLoading &&
        _currentThumbnailUrl != null &&
        _currentThumbnailUrl!.isNotEmpty &&
        _currentThumbnailUrl != _currentUrl) {
      return CachedNetworkImage(
        imageUrl: _currentThumbnailUrl!,
        cacheManager: ImageCacheManager.instance,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        fadeInDuration: const Duration(milliseconds: 200),
        placeholder: (context, url) => widget.useShimmer
            ? _buildShimmerPlaceholder()
            : _buildDefaultPlaceholder(),
        errorWidget: (context, url, error) => widget.useShimmer
            ? _buildShimmerPlaceholder()
            : _buildDefaultPlaceholder(),
        // Use smaller cache sizes for thumbnails to save memory
        memCacheWidth: _getMemoryCacheWidth() != null
            ? (_getMemoryCacheWidth()! * 0.5).toInt()
            : null,
        memCacheHeight: _getMemoryCacheHeight() != null
            ? (_getMemoryCacheHeight()! * 0.5).toInt()
            : null,
      );
    }

    // Fallback to shimmer or default placeholder
    return widget.useShimmer
        ? _buildShimmerPlaceholder()
        : _buildDefaultPlaceholder();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    print(
        '[StableCachedImage] Building widget for URL: $_currentUrl (key: ${widget.key})');

    try {
      return CachedNetworkImage(
        key: widget.key ??
            ValueKey(_currentUrl), // Use provided key or fallback to URL
        imageUrl: _currentUrl,
        cacheManager: ImageCacheManager.instance,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        fadeInDuration: widget.fadeInDuration,
        fadeOutDuration: widget.fadeOutDuration,

        // Use progressive placeholder (thumbnail → shimmer → default)
        placeholder: (context, url) {
          return widget.placeholder ?? _buildProgressivePlaceholder();
        },

        // Error handling with fallback to placeholder
        errorWidget: (context, url, error) {
          print('[StableCachedImage] ERROR loading image: $url, error: $error');

          // Log specific connection errors
          if (error.toString().contains('Connection closed') ||
              error.toString().contains('HttpException') ||
              error.toString().contains('ClientException') ||
              error.toString().contains('SocketException') ||
              error.toString().contains('TimeoutException')) {
            print(
                '[StableCachedImage] Network error detected - showing fallback');
          }

          return widget.errorWidget ??
              Container(
                width: widget.width,
                height: widget.height,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Icon(
                    Icons.error_outline,
                    color: Colors.grey,
                    size: 32,
                  ),
                ),
              );
        },

        // Memory optimization - resize images to fit container when possible
        memCacheWidth: _getMemoryCacheWidth(),
        memCacheHeight: _getMemoryCacheHeight(),

        // Prevent flashing when URL changes and improve scroll performance
        useOldImageOnUrlChange: true,
        filterQuality: FilterQuality.medium, // Better performance during scroll

        // Additional stability options
        fadeInCurve: Curves.easeInOut,
        fadeOutCurve: Curves.easeInOut,
        matchTextDirection: false, // Prevent RTL layout issues
      );
    } catch (e, stackTrace) {
      // Catch any uncaught exceptions during image loading
      print('[StableCachedImage] Build crashed: $e');
      print('[StableCachedImage] Stack trace: $stackTrace');

      // Return a safe fallback widget
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Icon(
            Icons.image_not_supported_outlined,
            color: Colors.grey,
            size: 32,
          ),
        ),
      );
    }
  }
}
