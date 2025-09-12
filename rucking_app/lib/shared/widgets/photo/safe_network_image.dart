import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:rucking_app/core/services/image_cache_manager.dart';

/// A safer version of network image loading that handles various error cases
/// and helps prevent crashes during image loading and rendering
class SafeNetworkImage extends StatelessWidget {
  /// The URL of the image to display
  final String imageUrl;

  /// How the image should be inscribed into the space allocated
  final BoxFit? fit;

  /// The width to display the image
  final double? width;

  /// The height to display the image
  final double? height;

  /// Optional headers to send with the HTTP request
  final Map<String, String>? headers;

  /// Optional placeholder widget to show while loading
  final Widget? placeholder;

  /// Optional error widget builder to show when loading fails
  final Widget Function(BuildContext context, String url, dynamic error)?
      errorWidget;

  /// Optional border radius for the image
  final BorderRadius? borderRadius;

  /// Whether to force the image to be reloaded (bypass cache)
  final bool forceReload;

  /// Creates a new SafeNetworkImage widget
  const SafeNetworkImage({
    Key? key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.headers,
    this.placeholder,
    this.errorWidget,
    this.borderRadius,
    this.forceReload = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Skip network images in debug mode if requested (helps with performance)
    if (kDebugMode && false) {
      // Set to true to disable network images in debug
      return _buildPlaceholder(context);
    }

    // Validate URL - return error widget for invalid URLs
    if (imageUrl.isEmpty || !(Uri.tryParse(imageUrl)?.hasScheme ?? false)) {
      return _buildDefaultErrorWidget(context, 'Invalid image URL');
    }

    // Add cache-busting parameter if forceReload is true
    final String url = forceReload
        ? '${imageUrl.split('?')[0]}?t=${DateTime.now().millisecondsSinceEpoch}'
        : imageUrl;

    // Default headers to help prevent caching issues
    final Map<String, String> defaultHeaders = forceReload
        ? {
            'Cache-Control': 'no-cache, no-store, must-revalidate',
            'Pragma': 'no-cache',
            'Expires': '0',
          }
        : {};

    // Merge default headers with provided headers
    final Map<String, String> finalHeaders = {
      ...defaultHeaders,
      ...?headers,
    };

    // Use CachedNetworkImage for better performance and error handling
    Widget image = CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      width: width,
      height: height,
      httpHeaders: finalHeaders,
      cacheManager:
          ImageCacheManager.instance, // Use ImageCacheManager instance
      placeholder: (context, url) => _buildPlaceholder(context),
      errorWidget: (context, url, error) => errorWidget != null
          ? errorWidget!(context, url, error)
          : _buildDefaultErrorWidget(context, error.toString()),
      fadeInDuration: const Duration(milliseconds: 300),
    );

    // Apply border radius if specified
    if (borderRadius != null) {
      image = ClipRRect(
        borderRadius: borderRadius!,
        child: image,
      );
    }

    // Wrap in error boundary to catch any rendering errors
    return image;
  }

  /// Build placeholder widget when image is loading
  Widget _buildPlaceholder(BuildContext context) {
    if (placeholder != null) {
      return placeholder!;
    }

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: borderRadius,
      ),
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.0,
          ),
        ),
      ),
    );
  }

  /// Build default error widget when image loading fails
  Widget _buildDefaultErrorWidget(BuildContext context, String error) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: borderRadius,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image, color: Colors.grey.shade600, size: 32),
            const SizedBox(height: 4),
            Text(
              'Image not available',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
