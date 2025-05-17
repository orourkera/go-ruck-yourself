import 'dart:io';
import 'package:flutter/material.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

/// A widget for selecting and uploading photos to a ruck session
class PhotoUploadSection extends StatefulWidget {
  /// The ID of the ruck this upload is for
  final String ruckId;
  
  /// Callback when photos are selected and ready for upload
  final Function(List<File> photos)? onPhotosSelected;
  
  /// Callback when upload is completed successfully
  final VoidCallback? onUploadSuccess;
  
  /// Maximum number of photos that can be selected
  final int maxPhotos;
  
  /// Whether photos are currently being uploaded
  final bool isUploading;
  
  const PhotoUploadSection({
    Key? key,
    required this.ruckId,
    this.onPhotosSelected,
    this.onUploadSuccess,
    this.maxPhotos = 5,
    this.isUploading = false,
  }) : super(key: key);

  @override
  State<PhotoUploadSection> createState() => _PhotoUploadSectionState();
}

class _PhotoUploadSectionState extends State<PhotoUploadSection> {
  final List<File> _selectedPhotos = [];
  bool _showPhotoPreview = false;
  
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text('Share Your Experience', style: AppTextStyles.titleMedium),
        const SizedBox(height: 8),
        Text(
          'Add photos from your ruck to share with the community',
          style: AppTextStyles.bodyMedium,
        ),
        const SizedBox(height: 16),
        
        // Photo Upload Button
        if (!_showPhotoPreview)
          _buildUploadButton(context),
        
        // Photo Preview Grid (when photos are selected)
        if (_showPhotoPreview)
          _buildPhotoPreview(),
      ],
    );
  }
  
  Widget _buildUploadButton(BuildContext context) {
    return InkWell(
      onTap: _selectPhotos,
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add_photo_alternate_outlined,
                size: 48,
                color: AppColors.primary,
              ),
              const SizedBox(height: 8),
              Text(
                'Add Photos',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Up to ${widget.maxPhotos} photos',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildPhotoPreview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Photo Grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1,
          ),
          itemCount: _selectedPhotos.length + (_selectedPhotos.length < widget.maxPhotos ? 1 : 0),
          itemBuilder: (context, index) {
            // Add photo button at the end if we haven't reached max
            if (index == _selectedPhotos.length) {
              return _buildAddMorePhotosButton();
            }
            
            // Photo preview with delete option
            return _buildPhotoPreviewItem(index);
          },
        ),
        
        const SizedBox(height: 16),
        
        // Upload Button
        if (_selectedPhotos.isNotEmpty)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: widget.isUploading ? null : _handleUpload,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: widget.isUploading
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text('Uploading...'),
                    ],
                  )
                : Text('Upload ${_selectedPhotos.length} Photos'),
            ),
          ),
        
        // Cancel Button  
        if (_selectedPhotos.isNotEmpty)
          TextButton(
            onPressed: widget.isUploading ? null : () {
              setState(() {
                _selectedPhotos.clear();
                _showPhotoPreview = false;
              });
            },
            child: Text(
              'Cancel',
              style: TextStyle(
                color: widget.isUploading ? Colors.grey : Colors.black54,
              ),
            ),
          ),
      ],
    );
  }
  
  Widget _buildPhotoPreviewItem(int index) {
    return Stack(
      children: [
        // Photo preview
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Image.file(
              _selectedPhotos[index],
              fit: BoxFit.cover,
            ),
          ),
        ),
        
        // Remove button
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: widget.isUploading ? null : () {
              setState(() {
                _selectedPhotos.removeAt(index);
                if (_selectedPhotos.isEmpty) {
                  _showPhotoPreview = false;
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildAddMorePhotosButton() {
    return GestureDetector(
      onTap: widget.isUploading ? null : _selectPhotos,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.grey.shade300,
          ),
        ),
        child: Center(
          child: Icon(
            Icons.add_circle_outline,
            color: widget.isUploading ? Colors.grey : AppColors.primary,
            size: 32,
          ),
        ),
      ),
    );
  }
  
  Future<void> _selectPhotos() async {
    // For frontend preview only, we'll mock image selection
    // This will be replaced with actual image_picker implementation later
    
    // Mock function that simulates selecting photos
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Assuming we got 3 photos back for our UI development
    // In a real implementation, this would use image_picker
    setState(() {
      // For now, just show the photo preview UI - mock data will be passed later
      _showPhotoPreview = true;
      
      // When we integrate image_picker, this is where we'll add the actual files
      // For now, we'll leave _selectedPhotos empty but still show the UI
    });
  }
  
  void _handleUpload() {
    // In real implementation, this would call the onPhotosSelected callback
    // For now, we'll just simulate the upload process
    
    if (widget.onPhotosSelected != null) {
      widget.onPhotosSelected!(_selectedPhotos);
    }
    
    // For UI demo only - we'll simulate success after a delay
    Future.delayed(const Duration(seconds: 2), () {
      if (widget.onUploadSuccess != null) {
        widget.onUploadSuccess!();
      }
      
      // Reset the UI
      setState(() {
        _selectedPhotos.clear();
        _showPhotoPreview = false;
      });
      
      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Photos uploaded successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    });
  }
}
