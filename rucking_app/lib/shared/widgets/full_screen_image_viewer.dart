import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:cached_network_image/cached_network_image.dart';

class FullScreenImageViewer extends StatelessWidget {
  final String? imageUrl;
  final File? imageFile;
  final String? heroTag;

  const FullScreenImageViewer({
    super.key,
    this.imageUrl,
    this.imageFile,
    this.heroTag,
  }) : assert(imageUrl != null || imageFile != null, 'Either imageUrl or imageFile must be provided');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: PhotoView(
        imageProvider: _getImageProvider(),
        backgroundDecoration: const BoxDecoration(color: Colors.black),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 3.0,
        initialScale: PhotoViewComputedScale.contained,
        heroAttributes: heroTag != null 
            ? PhotoViewHeroAttributes(tag: heroTag!)
            : null,
        loadingBuilder: (context, event) => Center(
          child: CircularProgressIndicator(
            value: event == null 
                ? 0 
                : event.cumulativeBytesLoaded / (event.expectedTotalBytes ?? 1),
            color: Colors.white,
          ),
        ),
        errorBuilder: (context, error, stackTrace) => const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error, color: Colors.white, size: 64),
              SizedBox(height: 16),
              Text(
                'Failed to load image',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }

  ImageProvider _getImageProvider() {
    if (imageFile != null) {
      return FileImage(imageFile!);
    } else if (imageUrl != null) {
      return CachedNetworkImageProvider(imageUrl!);
    } else {
      throw Exception('No image source provided');
    }
  }

  /// Show full screen image viewer as a route
  static void show(
    BuildContext context, {
    String? imageUrl,
    File? imageFile,
    String? heroTag,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FullScreenImageViewer(
          imageUrl: imageUrl,
          imageFile: imageFile,
          heroTag: heroTag,
        ),
      ),
    );
  }
}
