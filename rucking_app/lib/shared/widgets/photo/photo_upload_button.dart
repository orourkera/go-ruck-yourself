import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/widgets/styled_snackbar.dart';

/// A reusable button widget for photo selection and upload
class PhotoUploadButton extends StatelessWidget {
  /// Callback for when photos are selected
  final Function(List<File> photos)? onPhotosSelected;

  /// Button label
  final String label;

  /// Button icon
  final IconData icon;

  /// Maximum number of photos that can be selected
  final int maxPhotos;

  /// Whether to allow selecting multiple photos
  final bool allowMultiple;

  /// Button size
  final PhotoUploadButtonSize size;

  /// Whether button is in a loading state
  final bool isLoading;

  /// Button style
  final PhotoUploadButtonStyle style;

  /// Custom button width
  final double? width;

  /// Custom button height
  final double? height;

  /// Custom button border radius
  final double borderRadius;

  /// Constructor
  const PhotoUploadButton({
    Key? key,
    this.onPhotosSelected,
    this.label = 'Add Photos',
    this.icon = Icons.add_photo_alternate_outlined,
    this.maxPhotos = 5,
    this.allowMultiple = true,
    this.size = PhotoUploadButtonSize.medium,
    this.isLoading = false,
    this.style = PhotoUploadButtonStyle.outlined,
    this.width,
    this.height,
    this.borderRadius = 12.0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Size configurations
    double buttonHeight;
    double buttonWidth;
    double iconSize;
    double fontSize;

    switch (size) {
      case PhotoUploadButtonSize.small:
        buttonHeight = 60.0;
        buttonWidth = 100.0;
        iconSize = 24.0;
        fontSize = 12.0;
        break;
      case PhotoUploadButtonSize.medium:
        buttonHeight = 100.0;
        buttonWidth = 180.0;
        iconSize = 36.0;
        fontSize = 14.0;
        break;
      case PhotoUploadButtonSize.large:
        buttonHeight = 120.0;
        buttonWidth = 220.0;
        iconSize = 48.0;
        fontSize = 16.0;
        break;
      case PhotoUploadButtonSize.custom:
        buttonHeight = height ?? 100.0;
        buttonWidth = width ?? 180.0;
        iconSize = 36.0;
        fontSize = 14.0;
        break;
    }

    // Button style configurations
    Color backgroundColor;
    Color borderColor;
    Color iconColor;
    Color textColor;

    switch (style) {
      case PhotoUploadButtonStyle.filled:
        backgroundColor = AppColors.primary;
        borderColor = AppColors.primary;
        iconColor = Colors.white;
        textColor = Colors.white;
        break;
      case PhotoUploadButtonStyle.outlined:
        backgroundColor = Colors.grey.shade100;
        borderColor = Colors.grey.shade300;
        iconColor = AppColors.primary;
        textColor = AppColors.primary;
        break;
      case PhotoUploadButtonStyle.minimal:
        backgroundColor = Colors.transparent;
        borderColor = Colors.transparent;
        iconColor = AppColors.primary;
        textColor = AppColors.primary;
        break;
    }

    return InkWell(
      onTap: isLoading ? null : () => _handlePhotoSelection(context),
      child: Container(
        width: width ?? buttonWidth,
        height: height ?? buttonHeight,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(color: borderColor),
        ),
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: iconSize,
                    color: iconColor,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: fontSize,
                    ),
                  ),
                  if (maxPhotos > 1)
                    Text(
                      'Up to $maxPhotos photos',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: fontSize - 2,
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _handlePhotoSelection(BuildContext context) async {
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
                  await _getImageFrom(context, ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Camera'),
                onTap: () async {
                  Navigator.pop(context);
                  await _getImageFrom(context, ImageSource.camera);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _getImageFrom(BuildContext context, ImageSource source) async {
    final ImagePicker imagePicker = ImagePicker();

    try {
      if (source == ImageSource.gallery && allowMultiple) {
        // For gallery, we can select multiple photos at once
        final List<XFile> pickedFiles = await imagePicker.pickMultiImage(
          maxWidth: 1800,
          maxHeight: 1800,
          imageQuality: 85,
        );

        if (pickedFiles.isNotEmpty) {
          // Only add up to the max number of photos
          final filesToAdd = pickedFiles
              .take(maxPhotos)
              .map((xFile) => File(xFile.path))
              .toList();

          if (onPhotosSelected != null) {
            onPhotosSelected!(filesToAdd);
          }
        }
      } else {
        // For camera or single selection, we get one photo at a time
        final XFile? pickedFile = await imagePicker.pickImage(
          source: source,
          maxWidth: 1800,
          maxHeight: 1800,
          imageQuality: 85,
        );

        if (pickedFile != null && onPhotosSelected != null) {
          onPhotosSelected!([File(pickedFile.path)]);
        }
      }
    } catch (e) {
      if (!context.mounted) return;
      StyledSnackBar.show(
        context: context,
        message: 'Error selecting image: ${e.toString()}',
        type: SnackBarType.error,
      );
    }
  }
}

/// Enum for button sizes
enum PhotoUploadButtonSize {
  small,
  medium,
  large,
  custom,
}

/// Enum for button styles
enum PhotoUploadButtonStyle {
  filled,
  outlined,
  minimal,
}
