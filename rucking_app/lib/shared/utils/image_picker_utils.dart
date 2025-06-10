import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

/// Utility class for handling image selection and processing
class ImagePickerUtils {
  static final ImagePicker _picker = ImagePicker();

  /// Show a dialog to choose between camera and gallery
  static Future<File?> pickImage(BuildContext context) async {
    final result = await showDialog<String?>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Select Image'),
          content: const Text('Choose how you\'d like to select your avatar image:'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'camera'),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.camera_alt),
                  SizedBox(width: 8),
                  Text('Camera'),
                ],
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'gallery'),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.photo_library),
                  SizedBox(width: 8),
                  Text('Gallery'),
                ],
              ),
            ),
            // Cancel button moved to bottom left
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => Navigator.pop(dialogContext, null),
                child: const Text('Cancel'),
              ),
            ),
          ],
        );
      },
    );

    if (result == null) return null;
    
    if (result == 'camera') {
      return await _pickImageFromCamera();
    } else if (result == 'gallery') {
      return await _pickImageFromGallery();
    }
    
    return null;
  }

  /// Pick image from camera
  static Future<File?> _pickImageFromCamera() async {
    try {
      // Check camera permission
      final cameraStatus = await Permission.camera.status;
      if (cameraStatus.isDenied) {
        final result = await Permission.camera.request();
        if (result.isDenied) {
          return null;
        }
      }

      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null) {
        return File(image.path);
      }
      return null;
    } catch (e) {
      debugPrint('Error picking image from camera: $e');
      return null;
    }
  }

  /// Pick image from gallery
  static Future<File?> _pickImageFromGallery() async {
    try {
      // Check photos permission (iOS) / storage permission (Android)
      PermissionStatus photosStatus;
      if (Platform.isIOS) {
        photosStatus = await Permission.photos.status;
        if (photosStatus.isDenied) {
          final result = await Permission.photos.request();
          if (result.isDenied) {
            return null;
          }
        }
      } else {
        // For Android, we might need storage permission depending on API level
        photosStatus = await Permission.storage.status;
        if (photosStatus.isDenied) {
          final result = await Permission.storage.request();
          if (result.isDenied) {
            // Try with newer media permissions for Android 13+
            final mediaStatus = await Permission.photos.request();
            if (mediaStatus.isDenied) {
              return null;
            }
          }
        }
      }

      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null) {
        return File(image.path);
      }
      return null;
    } catch (e) {
      debugPrint('Error picking image from gallery: $e');
      return null;
    }
  }

  /// Validate image file
  static bool isValidImage(File file) {
    final validExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp'];
    final extension = file.path.toLowerCase().split('.').last;
    return validExtensions.contains(extension);
  }

  /// Check if file size is reasonable (under 10MB)
  static Future<bool> isValidSize(File file) async {
    try {
      final size = await file.length();
      const maxSize = 10 * 1024 * 1024; // 10MB in bytes
      return size <= maxSize;
    } catch (e) {
      return false;
    }
  }
}
