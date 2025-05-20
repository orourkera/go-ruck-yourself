import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/styled_snackbar.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

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
  final ImagePicker _imagePicker = ImagePicker();
  final List<File> _selectedPhotos = [];
  bool _showPhotoPreview = false;
  
  // Helper method to show styled snackbar
  void showStyledSnackBar(BuildContext context, String message, SnackBarType type) {
    StyledSnackBar.show(
      context: context,
      message: message,
      type: type,
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Removed duplicate header and subtitle. Only show the photo picker and add button below.

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
        
        // No Upload/Cancel buttons here - photos will be uploaded when user hits Save and Continue
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
    if (_selectedPhotos.length >= widget.maxPhotos) {
      showStyledSnackBar(
        context,
        'Maximum ${widget.maxPhotos} photos allowed',
        SnackBarType.normal,
      );
      return;
    }

    // Show option to choose camera or gallery
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Photo Gallery'),
                onTap: () async {
                  Navigator.pop(context);
                  await _getImageFrom(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Camera'),
                onTap: () async {
                  Navigator.pop(context);
                  await _getImageFrom(ImageSource.camera);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _getImageFrom(ImageSource source) async {
    try {
      final remainingSlots = widget.maxPhotos - _selectedPhotos.length;
      AppLogger.info('[PHOTO_UPLOAD] Selecting photos from ${source.toString()}, remaining slots: $remainingSlots');
      
      if (source == ImageSource.gallery && remainingSlots > 1) {
        // For gallery, we can select multiple photos at once
        // Don't specify imageQuality for PNG images since it's not supported on iOS
        // and generates warnings/errors
        final List<XFile> pickedFiles = await _imagePicker.pickMultiImage(
          imageQuality: 80,  // Only applies to JPG images
        );
        
        AppLogger.info('[PHOTO_UPLOAD] Picked ${pickedFiles.length} photos from gallery');
        
        if (pickedFiles.isNotEmpty) {
          // Only add up to the max number of photos
          final toAdd = pickedFiles.take(remainingSlots).toList();
          final filesToAdd = <File>[];
          
          // Log each photo's details
          for (var xFile in toAdd) {
            final file = File(xFile.path);
            filesToAdd.add(file);
            
            final fileExists = await file.exists();
            final fileSize = fileExists ? await file.length() : 0;
            AppLogger.info('[PHOTO_UPLOAD] Gallery photo: path=${xFile.path}, exists=$fileExists, size=$fileSize bytes, name=${xFile.name}');
          }
          
          setState(() {
            _selectedPhotos.addAll(filesToAdd);
            _showPhotoPreview = true;
          });
          
          // Notify callback of photos selected
          if (widget.onPhotosSelected != null) {
            AppLogger.info('[PHOTO_UPLOAD] Notifying listener of ${filesToAdd.length} photos selected');
            widget.onPhotosSelected?.call(_selectedPhotos);
          }
        }
      } else {
        // For camera, we get one photo at a time
        AppLogger.info('[PHOTO_UPLOAD] Opening camera picker');
        final XFile? pickedFile = await _imagePicker.pickImage(
          source: source,
          imageQuality: 80,  // Only applies to JPG images
        );
        
        AppLogger.info('[PHOTO_UPLOAD] Camera photo selected: ${pickedFile != null}');
        
        if (pickedFile != null) {
          final file = File(pickedFile.path);
          final fileExists = await file.exists();
          final fileSize = fileExists ? await file.length() : 0;
          AppLogger.info('[PHOTO_UPLOAD] Camera photo: path=${pickedFile.path}, exists=$fileExists, size=$fileSize bytes, name=${pickedFile.name}');
          
          setState(() {
            _selectedPhotos.add(file);
            _showPhotoPreview = true;
          });
          
          // Notify callback of photos selected
          if (widget.onPhotosSelected != null) {
            AppLogger.info('[PHOTO_UPLOAD] Notifying listener of camera photo selected');
            widget.onPhotosSelected?.call(_selectedPhotos);
          }
        }
      }
    } catch (e) {
      showStyledSnackBar(
        context,
        'Error selecting image: ${e.toString()}',
        SnackBarType.error,
      );
    }
  }
  
  void _handleUpload() {
    if (_selectedPhotos.isEmpty) {
      showStyledSnackBar(
        context, 
        'Please select at least one photo', 
        SnackBarType.normal,
      );
      return;
    }
    
    // Call the onPhotosSelected callback to initiate the upload
    if (widget.onPhotosSelected != null) {
      widget.onPhotosSelected!(_selectedPhotos);
    }
    
    // If onUploadSuccess is provided, the parent widget will handle the reset
    // Otherwise, we'll handle it here after a delay for demo purposes
    if (widget.onUploadSuccess == null) {
      // Demo-only simulation of upload success
      Future.delayed(const Duration(seconds: 2), () {
        // Reset the UI
        setState(() {
          _selectedPhotos.clear();
          _showPhotoPreview = false;
        });
        
        // Show success message
        showStyledSnackBar(
          context,
          'Photos uploaded successfully!',
          SnackBarType.success,
        );
      });
    }
  }
}
