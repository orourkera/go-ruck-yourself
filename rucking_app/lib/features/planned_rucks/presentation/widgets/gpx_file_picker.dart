import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

/// Widget for picking GPX files from device
class GpxFilePicker extends StatefulWidget {
  final Function(File) onFileSelected;
  final bool isLoading;

  const GpxFilePicker({
    super.key,
    required this.onFileSelected,
    this.isLoading = false,
  });

  @override
  State<GpxFilePicker> createState() => _GpxFilePickerState();
}

class _GpxFilePickerState extends State<GpxFilePicker>
    with SingleTickerProviderStateMixin {
  File? _selectedFile;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // File picker button/area
        GestureDetector(
          onTapDown: (_) => _animationController.forward(),
          onTapUp: (_) => _animationController.reverse(),
          onTapCancel: () => _animationController.reverse(),
          onTap: widget.isLoading ? null : _pickFile,
          child: AnimatedBuilder(
            animation: _scaleAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: _buildPickerArea(),
              );
            },
          ),
        ),

        // Selected file info
        if (_selectedFile != null) ...[
          const SizedBox(height: 16),
          _buildFileInfo(),
        ],
      ],
    );
  }

  Widget _buildPickerArea() {
    return Container(
      height: 160,
      width: double.infinity,
      decoration: BoxDecoration(
        color: _selectedFile != null
            ? AppColors.success.withOpacity(0.1)
            : AppColors.backgroundLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _selectedFile != null
              ? AppColors.success.withOpacity(0.3)
              : AppColors.primary.withOpacity(0.3),
          width: 2,
          style: _selectedFile != null ? BorderStyle.solid : BorderStyle.solid,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.isLoading)
            const CircularProgressIndicator()
          else
            Icon(
              _selectedFile != null ? Icons.check_circle : Icons.file_upload,
              size: 48,
              color:
                  _selectedFile != null ? AppColors.success : AppColors.primary,
            ),
          const SizedBox(height: 12),
          Text(
            _selectedFile != null ? 'GPX File Selected' : 'Select GPX File',
            style: AppTextStyles.titleMedium.copyWith(
              fontWeight: FontWeight.bold,
              color:
                  _selectedFile != null ? AppColors.success : AppColors.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _selectedFile != null
                ? 'Tap to change file'
                : 'Tap to browse files',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textDarkSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileInfo() {
    if (_selectedFile == null) return const SizedBox.shrink();

    final fileName = _selectedFile!.path.split('/').last;
    final fileSize = _selectedFile!.lengthSync();
    final fileSizeFormatted = _formatFileSize(fileSize);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.description,
                  size: 20,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Selected File',
                  style: AppTextStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // File name
            Row(
              children: [
                Icon(
                  Icons.insert_drive_file,
                  size: 16,
                  color: AppColors.textDarkSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    fileName,
                    style: AppTextStyles.bodyMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // File size
            Row(
              children: [
                Icon(
                  Icons.storage,
                  size: 16,
                  color: AppColors.textDarkSecondary,
                ),
                const SizedBox(width: 8),
                Text(
                  fileSizeFormatted,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textDarkSecondary,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickFile,
                    icon: const Icon(Icons.folder_open, size: 16),
                    label: const Text('Change File'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: BorderSide(color: AppColors.primary),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => widget.onFileSelected(_selectedFile!),
                    icon: const Icon(Icons.upload, size: 16),
                    label: const Text('Import'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result;

      // First try with custom type and gpx extension
      try {
        result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['gpx'],
          allowMultiple: false,
        );
      } catch (e) {
        // If the custom type fails (Android issue), try with any file type
        debugPrint('Custom file picker failed, trying fallback: $e');
        result = await FilePicker.platform.pickFiles(
          type: FileType.any,
          allowMultiple: false,
        );

        // Validate that the selected file is a GPX file
        if (result?.files.isNotEmpty == true &&
            result!.files.single.path != null) {
          final fileName = result.files.single.name?.toLowerCase() ?? '';
          if (!fileName.endsWith('.gpx')) {
            _showErrorSnackBar(
                'Please select a GPX file (.gpx extension required)');
            return;
          }
        }
      }

      if (result?.files.isNotEmpty == true &&
          result!.files.single.path != null) {
        setState(() {
          _selectedFile = File(result!.files.single.path!);
        });
      }
    } catch (e) {
      _showErrorSnackBar('Failed to pick file: $e');
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }
}

/// Drag and drop file picker for web/desktop
class DragDropGpxFilePicker extends StatefulWidget {
  final Function(File) onFileSelected;
  final bool isLoading;

  const DragDropGpxFilePicker({
    super.key,
    required this.onFileSelected,
    this.isLoading = false,
  });

  @override
  State<DragDropGpxFilePicker> createState() => _DragDropGpxFilePickerState();
}

class _DragDropGpxFilePickerState extends State<DragDropGpxFilePicker> {
  bool _isDragOver = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        color: _isDragOver
            ? AppColors.primary.withOpacity(0.1)
            : AppColors.backgroundLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isDragOver
              ? AppColors.primary
              : AppColors.primary.withOpacity(0.3),
          width: 2,
          style: _isDragOver ? BorderStyle.solid : BorderStyle.solid,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.isLoading ? null : _pickFile,
          borderRadius: BorderRadius.circular(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.isLoading)
                const CircularProgressIndicator()
              else
                Icon(
                  Icons.cloud_upload,
                  size: 64,
                  color: _isDragOver
                      ? AppColors.primary
                      : AppColors.textDarkSecondary,
                ),
              const SizedBox(height: 16),
              Text(
                'Drag & Drop GPX File',
                style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: _isDragOver ? AppColors.primary : AppColors.textDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'or click to browse',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textDarkSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result;

      // First try with custom type and gpx extension
      try {
        result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['gpx'],
          allowMultiple: false,
        );
      } catch (e) {
        // If the custom type fails (Android issue), try with any file type
        debugPrint('Custom file picker failed, trying fallback: $e');
        result = await FilePicker.platform.pickFiles(
          type: FileType.any,
          allowMultiple: false,
        );

        // Validate that the selected file is a GPX file
        if (result?.files.isNotEmpty == true &&
            result!.files.single.path != null) {
          final fileName = result.files.single.name?.toLowerCase() ?? '';
          if (!fileName.endsWith('.gpx')) {
            _showErrorSnackBar(
                'Please select a GPX file (.gpx extension required)');
            return;
          }
        }
      }

      if (result?.files.isNotEmpty == true &&
          result!.files.single.path != null) {
        widget.onFileSelected(File(result!.files.single.path!));
      }
    } catch (e) {
      _showErrorSnackBar('Failed to pick file: $e');
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
}

/// Compact file picker for smaller spaces
class CompactGpxFilePicker extends StatelessWidget {
  final Function(File) onFileSelected;
  final bool isLoading;
  final String? selectedFileName;

  const CompactGpxFilePicker({
    super.key,
    required this.onFileSelected,
    this.isLoading = false,
    this.selectedFileName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.backgroundLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.greyLight,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            selectedFileName != null ? Icons.check_circle : Icons.file_upload,
            size: 24,
            color: selectedFileName != null
                ? AppColors.success
                : AppColors.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selectedFileName ?? 'No file selected',
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontWeight: selectedFileName != null
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'GPX files only',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textDarkSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: isLoading ? null : _pickFile,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(80, 36),
            ),
            child: isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text('Browse'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result;

      // First try with custom type and gpx extension
      try {
        result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['gpx'],
          allowMultiple: false,
        );
      } catch (e) {
        // If the custom type fails (Android issue), try with any file type
        debugPrint('Custom file picker failed, trying fallback: $e');
        result = await FilePicker.platform.pickFiles(
          type: FileType.any,
          allowMultiple: false,
        );

        // Validate that the selected file is a GPX file
        if (result?.files.isNotEmpty == true &&
            result!.files.single.path != null) {
          final fileName = result.files.single.name?.toLowerCase() ?? '';
          if (!fileName.endsWith('.gpx')) {
            // For compact picker, we can't show snackbar, so just return
            debugPrint('Selected file is not a GPX file: $fileName');
            return;
          }
        }
      }

      if (result?.files.isNotEmpty == true &&
          result!.files.single.path != null) {
        onFileSelected(File(result!.files.single.path!));
      }
    } catch (e) {
      // Handle error appropriately
      debugPrint('File picker error: $e');
    }
  }
}
