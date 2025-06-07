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
  }

  @override
  void didUpdateWidget(StableCachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _currentUrl = widget.imageUrl;
    }
    if (oldWidget.thumbnailUrl != widget.thumbnailUrl) {
      _currentThumbnailUrl = widget.thumbnailUrl;
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

  /// Safe disk cache dimension calculation with reasonable defaults
  int _getMaxDiskCacheWidth() {
    if (widget.width == null || widget.width == double.infinity) {
      return 800; // Reasonable default for full-res images
    }
    return widget.width!.toInt().clamp(200, 1200); // Clamp to reasonable range
  }

  /// Safe disk cache dimension calculation with reasonable defaults
  int _getMaxDiskCacheHeight() {
    if (widget.height == null || widget.height == double.infinity) {
      return 600; // Reasonable default for full-res images
    }
    return widget.height!.toInt().clamp(150, 1000); // Clamp to reasonable range
  }

  Widget _buildShimmerPlaceholder() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
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
        placeholder: (context, url) => widget.useShimmer ? _buildShimmerPlaceholder() : _buildDefaultPlaceholder(),
        errorWidget: (context, url, error) => widget.useShimmer ? _buildShimmerPlaceholder() : _buildDefaultPlaceholder(),
        // Use smaller cache sizes for thumbnails to save memory
        memCacheWidth: _getMemoryCacheWidth() != null ? (_getMemoryCacheWidth()! * 0.5).toInt() : null,
        memCacheHeight: _getMemoryCacheHeight() != null ? (_getMemoryCacheHeight()! * 0.5).toInt() : null,
        maxWidthDiskCache: (_getMaxDiskCacheWidth() * 0.5).toInt(),
        maxHeightDiskCache: (_getMaxDiskCacheHeight() * 0.5).toInt(),
      );
    }
    
    // Fallback to shimmer or default placeholder
    return widget.useShimmer ? _buildShimmerPlaceholder() : _buildDefaultPlaceholder();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    
    return CachedNetworkImage(
      key: ValueKey('stable_cached_$_currentUrl'),
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
        return widget.errorWidget ?? Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Center(
            child: Icon(
              Icons.error,
              color: Colors.grey,
              size: 32,
            ),
          ),
        );
      },
      
      // Memory optimization - resize images to fit container when possible
      memCacheWidth: _getMemoryCacheWidth(),
      memCacheHeight: _getMemoryCacheHeight(),
      
      // Prevent flashing when URL changes
      useOldImageOnUrlChange: true,
      
      // Reduce memory usage by limiting max disk cache size
      maxWidthDiskCache: _getMaxDiskCacheWidth(),
      maxHeightDiskCache: _getMaxDiskCacheHeight(),
    );
  }
}
