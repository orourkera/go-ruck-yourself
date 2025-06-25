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

/// An improved modal for cropping images with better UX
class ImprovedImageCropModal extends StatefulWidget {
  final File imageFile;
  final String title;
  final double aspectRatio;
  final CropShape cropShape;
  
  const ImprovedImageCropModal({
    super.key,
    required this.imageFile,
    this.title = 'Crop Image',
    this.aspectRatio = 1.0,
    this.cropShape = CropShape.circle,
  });

  @override
  State<ImprovedImageCropModal> createState() => _ImprovedImageCropModalState();
}

class _ImprovedImageCropModalState extends State<ImprovedImageCropModal> {
  final GlobalKey _cropKey = GlobalKey();
  final TransformationController _controller = TransformationController();
  
  late ui.Image _image;
  bool _imageLoaded = false;
  late Size _screenSize;
  late double _cropWidth;
  late double _cropHeight;
  
  @override
  void initState() {
    super.initState();
    debugPrint('🖼️ [CROP] ImprovedImageCropModal initState');
    debugPrint('🖼️ [CROP] Image file: ${widget.imageFile.path}');
    debugPrint('🖼️ [CROP] Aspect ratio: ${widget.aspectRatio}');
    debugPrint('🖼️ [CROP] Crop shape: ${widget.cropShape}');
    
    // Delay loading the image slightly to ensure the widget is fully built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('🖼️ [CROP] PostFrameCallback - starting image load');
      _loadImage();
    });
  }

  @override
  void dispose() {
    debugPrint('🖼️ [CROP] ImprovedImageCropModal dispose');
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadImage() async {
    try {
      debugPrint('🖼️ [CROP] Starting to load image: ${widget.imageFile.path}');
      debugPrint('🖼️ [CROP] File exists: ${await widget.imageFile.exists()}');
      
      final bytes = await widget.imageFile.readAsBytes();
      debugPrint('🖼️ [CROP] Read ${bytes.length} bytes from file');
      
      final codec = await ui.instantiateImageCodec(bytes);
      final frameInfo = await codec.getNextFrame();
      
      debugPrint('🖼️ [CROP] Image loaded: ${frameInfo.image.width}x${frameInfo.image.height}');
      
      if (mounted) {
        setState(() {
          _image = frameInfo.image;
          _imageLoaded = true;
        });

        // Auto-fit image when loaded
        WidgetsBinding.instance.addPostFrameCallback((_) {
          debugPrint('🖼️ [CROP] Auto-fitting image to crop area');
          if (mounted) {
            _fitImageToCropArea();
          }
        });
      } else {
        debugPrint('❌ [CROP] Widget not mounted when image loaded');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [CROP] Error loading image: $e');
      debugPrint('❌ [CROP] Stack trace: $stackTrace');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load image. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.of(context).pop(null);
      }
    }
  }

  void _fitImageToCropArea() {
    if (!_imageLoaded) return;
    
    // Get the actual rendered size of the image
    final imageAspectRatio = _image.width / _image.height;
    final screenAspectRatio = _screenSize.width / _screenSize.height;
    
    // Calculate the actual image display size when using BoxFit.cover
    double displayWidth, displayHeight;
    if (imageAspectRatio > screenAspectRatio) {
      // Image is wider - height fills screen, width is clipped
      displayHeight = _screenSize.height;
      displayWidth = displayHeight * imageAspectRatio;
    } else {
      // Image is taller - width fills screen, height is clipped
      displayWidth = _screenSize.width;
      displayHeight = displayWidth / imageAspectRatio;
    }
    
    // Calculate scale to make crop area fill properly
    final cropAspectRatio = widget.aspectRatio;
    double scale;
    
    if (cropAspectRatio > imageAspectRatio) {
      // Crop is wider than image - scale to fill crop width
      scale = _cropWidth / displayWidth;
    } else {
      // Crop is taller than image - scale to fill crop height  
      scale = _cropHeight / displayHeight;
    }
    
    // Ensure we have a reasonable minimum scale
    scale = math.max(scale, 0.3);
    
    // Calculate centering offsets to center the crop area
    final scaledWidth = displayWidth * scale;
    final scaledHeight = displayHeight * scale;
    
    final offsetX = (_screenSize.width - scaledWidth) / 2;
    final offsetY = (_screenSize.height - scaledHeight) / 2;
    
    // Apply transformation
    final matrix = Matrix4.identity()
      ..translate(offsetX, offsetY)
      ..scale(scale);
    
    setState(() {
      _controller.value = matrix;
    });
  }

  void _resetCrop() {
    setState(() {
      _controller.value = Matrix4.identity();
    });
    // Auto-fit after reset
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fitImageToCropArea();
    });
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('🖼️ [CROP] Building crop modal - _imageLoaded: $_imageLoaded');
    
    _screenSize = MediaQuery.of(context).size;
    _cropWidth = _screenSize.width * 0.8;
    _cropHeight = widget.cropShape == CropShape.rectangle 
        ? _cropWidth / widget.aspectRatio 
        : _cropWidth;
    
    debugPrint('🖼️ [CROP] Screen size: $_screenSize');
    debugPrint('🖼️ [CROP] Crop dimensions: ${_cropWidth}x$_cropHeight');
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Full-screen interactive image
          if (_imageLoaded)
            RepaintBoundary(
              key: _cropKey,
              child: InteractiveViewer(
                transformationController: _controller,
                minScale: 0.05, // Allow much smaller cropping
                maxScale: 8.0, // Allow more zoom in
                panEnabled: true,
                scaleEnabled: true,
                constrained: false,
                boundaryMargin: EdgeInsets.all(_screenSize.width * 1.5), // More room to pan
                child: Image.file(
                  widget.imageFile,
                  fit: BoxFit.contain,
                ),
              ),
            )
          else
            // Show loading indicator while image is loading
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 16),
                  Text(
                    'Loading image...',
                    style: AppTextStyles.bodyLarge.copyWith(color: Colors.white),
                  ),
                ],
              ),
            ),
          
          // Crop overlay (non-interactive)
          IgnorePointer(
            child: Container(
              width: double.infinity,
              height: double.infinity,
              child: CustomPaint(
                painter: CropOverlayPainter(
                  cropRect: Rect.fromCenter(
                    center: Offset(_screenSize.width / 2, _screenSize.height / 2),
                    width: _cropWidth,
                    height: _cropHeight,
                  ),
                  cropShape: widget.cropShape,
                ),
              ),
            ),
          ),
          
          // Top app bar with proper status bar handling
          Positioned(
            top: 60, // Move header down significantly from the top
            left: 0,
            right: 0,
            child: Container(
              // Add normal padding without status bar calculations
              padding: const EdgeInsets.only(
                top: 16, // Increased padding for better spacing
                left: 16,
                right: 16,
                bottom: 12,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.8),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 28),
                    onPressed: () => Navigator.of(context).pop(null), // Explicitly return null on close
                  ),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: AppTextStyles.titleLarge.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  TextButton(
                    onPressed: _cropAndSave,
                    child: Text(
                      'Save',
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Bottom controls
          Positioned(
            bottom: 120, // Move save button down significantly from the bottom
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: _resetCrop,
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    label: const Text('Reset', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black.withOpacity(0.7),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _fitImageToCropArea,
                    icon: const Icon(Icons.fit_screen, color: Colors.white),
                    label: const Text('Fit', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black.withOpacity(0.7),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _cropAndSave() async {
    File? resultFile;
    
    try {
      debugPrint('🖼️ Starting _cropAndSave...');
      debugPrint('🖼️ _imageLoaded: $_imageLoaded');
      debugPrint('🖼️ _cropKey.currentContext: ${_cropKey.currentContext}');
      
      if (!_imageLoaded) {
        debugPrint('❌ Image not loaded, aborting crop');
        _returnResult(null);
        return;
      }
      
      if (_cropKey.currentContext == null) {
        debugPrint('❌ Crop key context is null, aborting crop');
        _returnResult(null);
        return;
      }
      
      // Capture the entire transformed image from RepaintBoundary
      final RenderRepaintBoundary boundary = 
          _cropKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      
      debugPrint('🖼️ Found boundary, capturing image...');
      
      // Get the full screen image with all transformations applied
      final ui.Image fullScreenImage = await boundary.toImage(pixelRatio: 3.0);
      
      debugPrint('🖼️ Captured full screen image: ${fullScreenImage.width}x${fullScreenImage.height}');
      
      // Calculate the exact crop area coordinates on the captured image
      final double pixelRatio = 3.0; // Same as used above
      final cropRect = Rect.fromCenter(
        center: Offset(_screenSize.width / 2 * pixelRatio, _screenSize.height / 2 * pixelRatio),
        width: _cropWidth * pixelRatio,
        height: _cropHeight * pixelRatio,
      );
      
      debugPrint('🖼️ Crop rect: $cropRect');
      
      // Ensure crop rect is within image bounds
      final clampedCropRect = Rect.fromLTRB(
        math.max(0, cropRect.left),
        math.max(0, cropRect.top),
        math.min(fullScreenImage.width.toDouble(), cropRect.right),
        math.min(fullScreenImage.height.toDouble(), cropRect.bottom),
      );
      
      debugPrint('🖼️ Clamped crop rect: $clampedCropRect');
      
      // Ensure the crop rect has valid dimensions
      if (clampedCropRect.width <= 0 || clampedCropRect.height <= 0) {
        debugPrint('❌ Invalid crop dimensions: ${clampedCropRect.width}x${clampedCropRect.height}');
        _returnResult(null);
        return;
      }
      
      // Create the final cropped image
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      
      // Set the destination size to the crop area dimensions
      final outputWidth = _cropWidth * pixelRatio;
      final outputHeight = _cropHeight * pixelRatio;
      
      debugPrint('🖼️ Output size: ${outputWidth.toInt()}x${outputHeight.toInt()}');
      
      // Draw only the crop area from the full image
      canvas.drawImageRect(
        fullScreenImage,
        clampedCropRect,
        Rect.fromLTWH(0, 0, outputWidth, outputHeight),
        Paint(),
      );
      
      // Finalize the cropped image
      final picture = recorder.endRecording();
      final croppedImage = await picture.toImage(outputWidth.toInt(), outputHeight.toInt());
      
      debugPrint('🖼️ Created cropped image: ${croppedImage.width}x${croppedImage.height}');
      
      // Convert to bytes and save
      final ByteData? byteData = await croppedImage.toByteData(format: ui.ImageByteFormat.png);
      
      if (byteData != null) {
        debugPrint('🖼️ Converting to bytes...');
        final Uint8List pngBytes = byteData.buffer.asUint8List();
        
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/cropped_image_${DateTime.now().millisecondsSinceEpoch}.png');
        await tempFile.writeAsBytes(pngBytes);
        
        // Verify the file was written successfully
        final fileExists = await tempFile.exists();
        final fileSize = await tempFile.length();
        
        debugPrint('✅ Cropped image saved to: ${tempFile.path}');
        debugPrint('✅ File exists: $fileExists');
        debugPrint('✅ File size: $fileSize bytes');
        
        if (fileExists && fileSize > 0) {
          resultFile = tempFile;
        } else {
          debugPrint('❌ Failed to write cropped image to file');
        }
      } else {
        debugPrint('❌ Failed to convert image to bytes');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error cropping image: $e');
      debugPrint('❌ Stack trace: $stackTrace');
    } finally {
      _returnResult(resultFile);
    }
  }
  
  void _returnResult(File? file) {
    if (mounted) {
      Navigator.of(context).pop(file);
    } else {
      debugPrint('⚠️ Context not mounted, cannot return result');
    }
  }
}

class CropOverlayPainter extends CustomPainter {
  final Rect cropRect;
  final CropShape cropShape;

  CropOverlayPainter({required this.cropRect, required this.cropShape});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..style = PaintingStyle.fill;

    // Draw overlay with hole for crop area
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    if (cropShape == CropShape.circle) {
      path.addOval(cropRect);
    } else {
      final radius = cropShape == CropShape.rectangle ? 16.0 : 12.0;
      path.addRRect(RRect.fromRectAndRadius(cropRect, Radius.circular(radius)));
    }

    path.fillType = PathFillType.evenOdd;
    canvas.drawPath(path, paint);

    // Draw crop area border
    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    if (cropShape == CropShape.circle) {
      canvas.drawOval(cropRect, borderPaint);
    } else {
      final radius = cropShape == CropShape.rectangle ? 16.0 : 12.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(cropRect, Radius.circular(radius)),
        borderPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class CropAreaClipper extends CustomClipper<Path> {
  final Rect cropRect;
  final CropShape cropShape;

  CropAreaClipper({required this.cropRect, required this.cropShape});

  @override
  Path getClip(Size size) {
    final path = Path();

    if (cropShape == CropShape.circle) {
      path.addOval(cropRect);
    } else {
      final radius = cropShape == CropShape.rectangle ? 16.0 : 12.0;
      path.addRRect(RRect.fromRectAndRadius(cropRect, Radius.circular(radius)));
    }

    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
