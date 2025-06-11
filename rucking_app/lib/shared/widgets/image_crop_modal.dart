import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

/// A modal that allows users to crop, pan, and zoom images
class ImageCropModal extends StatefulWidget {
  final File imageFile;
  final String title;
  final double aspectRatio;
  
  const ImageCropModal({
    super.key,
    required this.imageFile,
    this.title = 'Crop Image',
    this.aspectRatio = 1.0, // 1.0 for square (profile pictures)
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
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.grey[900],
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : Colors.grey[900],
        foregroundColor: Colors.white,
        title: Text(
          widget.title,
          style: AppTextStyles.titleLarge.copyWith(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
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
      body: _imageLoaded ? _buildCropInterface() : _buildLoadingIndicator(),
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
    final cropSize = screenSize.width * 0.8;
    
    return Column(
      children: [
        // Instructions
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Move and pinch to adjust your image',
            style: AppTextStyles.bodyMedium.copyWith(
              color: Colors.white70,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        
        // Crop area
        Expanded(
          child: Center(
            child: Container(
              width: cropSize,
              height: cropSize / widget.aspectRatio,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: widget.aspectRatio == 1.0 
                    ? BorderRadius.circular(cropSize / 2) 
                    : BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: widget.aspectRatio == 1.0 
                    ? BorderRadius.circular(cropSize / 2) 
                    : BorderRadius.circular(6),
                child: RepaintBoundary(
                  key: _cropKey,
                  child: InteractiveViewer(
                    transformationController: _transformationController,
                    minScale: 0.5,
                    maxScale: 3.0,
                    constrained: false,
                    child: Image.file(
                      widget.imageFile,
                      fit: BoxFit.cover,
                      width: cropSize * 2, // Give more room for panning
                      height: (cropSize / widget.aspectRatio) * 2,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        
        // Controls
        _buildControls(),
      ],
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.all(16),
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onPressed,
          icon: Icon(icon, color: Colors.white),
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.1),
            padding: const EdgeInsets.all(12),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  void _resetTransformation() {
    _transformationController.value = Matrix4.identity();
  }

  void _centerImage() {
    // Calculate center position
    final matrix = Matrix4.identity();
    matrix.translate(0.0, 0.0);
    
    _transformationController.value = matrix;
  }

  void _fitImage() {
    final screenSize = MediaQuery.of(context).size;
    final cropSize = screenSize.width * 0.8;
    
    if (_image.width > 0 && _image.height > 0) {
      final imageAspectRatio = _image.width / _image.height;
      final containerAspectRatio = widget.aspectRatio;
      
      double scale;
      if (imageAspectRatio > containerAspectRatio) {
        // Image is wider, fit to height
        scale = (cropSize / widget.aspectRatio) / _image.height;
      } else {
        // Image is taller, fit to width
        scale = cropSize / _image.width;
      }
      
      final matrix = Matrix4.identity();
      matrix.scale(scale);
      
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
