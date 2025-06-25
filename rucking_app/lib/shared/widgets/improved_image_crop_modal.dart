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
    _loadImage();
  }

  @override
  void dispose() {
    _controller.dispose();
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

    // Auto-fit image when loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fitImageToCropArea();
    });
  }

  void _fitImageToCropArea() {
    if (!_imageLoaded) return;
    
    final imageAspectRatio = _image.width / _image.height;
    final cropAspectRatio = widget.aspectRatio;
    
    // Calculate scale to fill crop area
    double scale;
    if (imageAspectRatio > cropAspectRatio) {
      // Image is wider - scale to fill height
      scale = _cropHeight / _image.height;
    } else {
      // Image is taller - scale to fill width
      scale = _cropWidth / _image.width;
    }
    
    // Ensure minimum useful scale
    scale = math.max(scale, 0.5);
    
    // Calculate centering offsets
    final scaledImageWidth = _image.width * scale;
    final scaledImageHeight = _image.height * scale;
    
    final offsetX = (_screenSize.width - scaledImageWidth) / 2;
    final offsetY = (_screenSize.height - scaledImageHeight) / 2;
    
    final matrix = Matrix4.identity()
      ..translate(offsetX, offsetY)
      ..scale(scale);
    
    _controller.value = matrix;
  }

  void _resetView() {
    _controller.value = Matrix4.identity();
    _fitImageToCropArea();
  }

  @override
  Widget build(BuildContext context) {
    _screenSize = MediaQuery.of(context).size;
    _cropWidth = _screenSize.width * 0.9;
    _cropHeight = widget.cropShape == CropShape.rectangle 
        ? _cropWidth / widget.aspectRatio 
        : _cropWidth;
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Full-screen interactive image
            if (_imageLoaded)
              InteractiveViewer(
                transformationController: _controller,
                minScale: 0.1,
                maxScale: 10.0,
                panEnabled: true,
                scaleEnabled: true,
                child: Container(
                  width: _screenSize.width,
                  height: _screenSize.height,
                  child: Image.file(
                    widget.imageFile,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            
            // Crop overlay (non-interactive)
            IgnorePointer(
              child: Container(
                width: _screenSize.width,
                height: _screenSize.height,
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
            
            // Top app bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 28),
                      onPressed: () => Navigator.of(context).pop(),
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
                        'DONE',
                        style: TextStyle(
                          color: AppColors.accent,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Bottom controls
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.8),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildControlButton(
                      icon: Icons.refresh,
                      label: 'Reset',
                      onPressed: _resetView,
                    ),
                    _buildControlButton(
                      icon: Icons.center_focus_strong,
                      label: 'Fit',
                      onPressed: _fitImageToCropArea,
                    ),
                  ],
                ),
              ),
            ),
            
            // Crop area preview (for positioning reference)
            if (_imageLoaded)
              Positioned.fill(
                child: RepaintBoundary(
                  key: _cropKey,
                  child: ClipPath(
                    clipper: CropAreaClipper(
                      cropRect: Rect.fromCenter(
                        center: Offset(_screenSize.width / 2, _screenSize.height / 2),
                        width: _cropWidth,
                        height: _cropHeight,
                      ),
                      cropShape: widget.cropShape,
                    ),
                    child: InteractiveViewer(
                      transformationController: _controller,
                      minScale: 0.1,
                      maxScale: 10.0,
                      panEnabled: false,
                      scaleEnabled: false,
                      child: Container(
                        width: _screenSize.width,
                        height: _screenSize.height,
                        child: Image.file(
                          widget.imageFile,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
            color: Colors.white.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _cropAndSave() async {
    try {
      final RenderRepaintBoundary boundary = 
          _cropKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      
      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      
      if (byteData != null) {
        final Uint8List pngBytes = byteData.buffer.asUint8List();
        
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/cropped_image_${DateTime.now().millisecondsSinceEpoch}.png');
        await tempFile.writeAsBytes(pngBytes);
        
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
