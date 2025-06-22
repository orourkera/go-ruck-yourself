import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

/// Enum to define crop shape options
enum CropShape {
  circle,     // For profile pictures
  square,     // For square crops
  rectangle,  // For banner images and rectangular crops
}

/// A modal that allows users to crop, pan, and zoom images
class ImageCropModal extends StatefulWidget {
  final File imageFile;
  final String title;
  final double aspectRatio;
  final CropShape cropShape; // New parameter to control crop shape
  
  const ImageCropModal({
    super.key,
    required this.imageFile,
    this.title = 'Crop Image',
    this.aspectRatio = 1.0, // 1.0 for square (profile pictures)
    this.cropShape = CropShape.circle, // Default to circular for backwards compatibility
  });

  @override
  State<ImageCropModal> createState() => _ImageCropModalState();
}

class _ImageCropModalState extends State<ImageCropModal> {
  final GlobalKey _cropKey = GlobalKey();
  final TransformationController _transformationController = TransformationController();
  
  late ui.Image _image;
  bool _imageLoaded = false;
  
  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  Future<void> _loadImage() async {
    final bytes = await widget.imageFile.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frameInfo = await codec.getNextFrame();
    
    setState(() {
      _image = frameInfo.image;
      _imageLoaded = true;
    });

    // Ensure the image is centered and reasonably scaled when first displayed
    // so users are not forced to tap the Center control manually.
    if (mounted) {
      _centerImage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Custom app bar with much more padding for status bar
            Container(
              padding: const EdgeInsets.only(
                left: 16, 
                right: 16, 
                top: 40, // Much more padding to clear status bar
                bottom: 16
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 28),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Text(
                      widget.title.toUpperCase(),
                      style: AppTextStyles.titleLarge.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  TextButton(
                    onPressed: _imageLoaded ? _cropAndSave : null,
                    child: Text(
                      'Done',
                      style: TextStyle(
                        color: _imageLoaded ? AppColors.accent : Colors.grey,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Main content
            Expanded(
              child: _imageLoaded ? _buildCropInterface() : _buildLoadingIndicator(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return const Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
      ),
    );
  }

  Widget _buildCropInterface() {
    final screenSize = MediaQuery.of(context).size;
    final safeHeight = screenSize.height - MediaQuery.of(context).padding.top - 220;
    
    // Calculate crop dimensions
    final cropWidth = screenSize.width * 0.85;
    final cropHeight = math.min(cropWidth / widget.aspectRatio, safeHeight * 0.6);
    
    return Column(
      children: [
        // Instructions and dimensions info
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Move and pinch to adjust your image',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: Colors.white70,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            
            // Dimension and aspect ratio info
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.crop,
                    color: AppColors.accent,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _getDimensionText(),
                    style: AppTextStyles.bodySmall.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                    ),
                  ),
                  if (_imageLoaded) ...[
                    const SizedBox(width: 12),
                    Container(
                      width: 1,
                      height: 12,
                      color: Colors.white.withOpacity(0.3),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.photo,
                      color: Colors.white70,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${_image.width}×${_image.height}',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        
        // Main crop area with direct InteractiveViewer
        Expanded(
          child: Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Background image (blurred and darkened)
                Image.file(
                  widget.imageFile,
                  fit: BoxFit.cover,
                  color: Colors.black.withOpacity(0.7),
                  colorBlendMode: BlendMode.darken,
                ),
                
                // Interactive crop area - DIRECT InteractiveViewer (MUST BE ON TOP)
                Center(
                  child: SizedBox(
                    width: cropWidth,
                    height: cropHeight,
                    child: RepaintBoundary(
                      key: _cropKey,
                      child: InteractiveViewer(
                        transformationController: _transformationController,
                        minScale: 0.3,
                        maxScale: 5.0,
                        boundaryMargin: EdgeInsets.zero,
                        panEnabled: true,
                        scaleEnabled: true,
                        constrained: false,
                        child: Container(
                          width: cropWidth * 3,
                          height: cropHeight * 3,
                          child: ClipRRect(
                            borderRadius: widget.cropShape == CropShape.circle 
                                ? BorderRadius.circular(cropWidth * 3 / 2) 
                                : widget.cropShape == CropShape.square
                                    ? BorderRadius.circular(12)
                                    : BorderRadius.circular(16),
                            child: Image.file(
                              widget.imageFile,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                
                // Crop overlay - POINTER EVENTS DISABLED
                IgnorePointer(
                  child: Center(
                    child: Container(
                      width: cropWidth,
                      height: cropHeight,
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.accent, width: 3),
                        borderRadius: widget.cropShape == CropShape.circle 
                            ? BorderRadius.circular(cropWidth / 2) 
                            : widget.cropShape == CropShape.square
                                ? BorderRadius.circular(8)
                                : BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        
        // Controls
        _buildControls(),
      ],
    );
  }

  String _getDimensionText() {
    final screenSize = MediaQuery.of(context).size;
    final safeHeight = screenSize.height - MediaQuery.of(context).padding.top - 220; // More space for header
    
    // Calculate crop dimensions
    final cropWidth = screenSize.width * 0.85;
    final cropHeight = math.min(cropWidth / widget.aspectRatio, safeHeight * 0.6);
    
    // Format aspect ratio in a user-friendly way
    String aspectRatioText;
    if (widget.aspectRatio == 1.0) {
      aspectRatioText = '1:1 Square';
    } else if (widget.aspectRatio == 3.0) {
      aspectRatioText = '3:1 Banner';
    } else if (widget.aspectRatio == 16.0 / 9.0) {
      aspectRatioText = '16:9 Widescreen';
    } else if (widget.aspectRatio == 4.0 / 3.0) {
      aspectRatioText = '4:3 Standard';
    } else if (widget.aspectRatio == 2.0) {
      aspectRatioText = '2:1 Wide';
    } else {
      // For custom ratios, calculate simplified fraction
      final ratio = widget.aspectRatio;
      if (ratio > 1) {
        aspectRatioText = '${ratio.toStringAsFixed(1)}:1';
      } else {
        aspectRatioText = '1:${(1/ratio).toStringAsFixed(1)}';
      }
    }
    
    return '${cropWidth.toInt()}×${cropHeight.toInt()} • $aspectRatioText';
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withOpacity(0.8),
          ],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Reset button
          _buildControlButton(
            icon: Icons.refresh,
            label: 'Reset',
            onPressed: _resetTransformation,
          ),
          
          // Center button  
          _buildControlButton(
            icon: Icons.center_focus_strong,
            label: 'Center',
            onPressed: _centerImage,
          ),
          
          // Fit button
          _buildControlButton(
            icon: Icons.fit_screen,
            label: 'Fit',
            onPressed: _fitImage,
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
            color: Colors.white.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon, 
              color: Colors.white,
              size: 24,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _resetTransformation() {
    _transformationController.value = Matrix4.identity();
  }

  void _centerImage() {
    // Reset to identity first, then apply any centering adjustments
    final matrix = Matrix4.identity();
    
    // Center the image within the crop area
    final screenSize = MediaQuery.of(context).size;
    final cropWidth = screenSize.width * 0.85;
    final cropHeight = math.min(cropWidth / widget.aspectRatio, (screenSize.height - MediaQuery.of(context).padding.top - 220) * 0.6);
    
    if (_image.width > 0 && _image.height > 0) {
      // Calculate scale to fit image nicely in crop area
      final imageAspectRatio = _image.width / _image.height;
      final cropAspectRatio = widget.aspectRatio;
      
      double scale = 1.0;
      if (imageAspectRatio > cropAspectRatio) {
        // Image is wider than crop area, scale to fit height
        scale = (cropHeight * 3) / _image.height;
      } else {
        // Image is taller than crop area, scale to fit width  
        scale = (cropWidth * 3) / _image.width;
      }
      
      // Ensure minimum scale for visibility
      scale = math.max(scale, 0.5);
      
      // Apply scale
      matrix.scale(scale, scale);
    }
    
    _transformationController.value = matrix;
  }

  void _fitImage() {
    final screenSize = MediaQuery.of(context).size;
    final cropWidth = screenSize.width * 0.85;
    final cropHeight = math.min(cropWidth / widget.aspectRatio, (screenSize.height - MediaQuery.of(context).padding.top - 220) * 0.6);
    
    if (_image.width > 0 && _image.height > 0) {
      final imageAspectRatio = _image.width / _image.height;
      final containerAspectRatio = widget.aspectRatio;
      
      double scale;
      if (imageAspectRatio > containerAspectRatio) {
        // Image is wider, fit to height
        scale = (cropHeight * 3) / _image.height;
      } else {
        // Image is taller, fit to width
        scale = (cropWidth * 3) / _image.width;
      }
      
      // Ensure scale fills the crop area properly
      scale = math.max(scale, 1.0);
      
      final matrix = Matrix4.identity();
      matrix.scale(scale, scale);
      
      _transformationController.value = matrix;
    }
  }

  Future<void> _cropAndSave() async {
    try {
      // Get the render object of the crop area
      final RenderRepaintBoundary boundary = 
          _cropKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      
      // Capture the widget as an image
      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      
      if (byteData != null) {
        final Uint8List pngBytes = byteData.buffer.asUint8List();
        
        // Save to temporary file
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/cropped_image_${DateTime.now().millisecondsSinceEpoch}.png');
        await tempFile.writeAsBytes(pngBytes);
        
        // Return the cropped file
        if (mounted) {
          Navigator.of(context).pop(tempFile);
        }
      }
    } catch (e) {
      debugPrint('Error cropping image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to crop image. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
