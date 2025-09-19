import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:async';
import 'package:permission_handler/permission_handler.dart';
import 'package:rucking_app/features/social_sharing/models/time_range.dart';
import 'package:rucking_app/features/social_sharing/widgets/photo_carousel.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

class SharePreviewScreen extends StatefulWidget {
  final String sessionId;
  final TimeRange? timeRange;

  const SharePreviewScreen({
    Key? key,
    required this.sessionId,
    this.timeRange,
  }) : super(key: key);

  @override
  State<SharePreviewScreen> createState() => _SharePreviewScreenState();
}

class _SharePreviewScreenState extends State<SharePreviewScreen> {
  List<String> _selectedPhotos = [];
  bool _isSharing = false;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    // TODO: Load photos for the session
    // For now, just initialize empty
    setState(() {
      _selectedPhotos = [];
    });
  }

  Future<void> _sharePhotos() async {
    if (_selectedPhotos.isEmpty) {
      _showMessage('No photos to share');
      return;
    }

    setState(() {
      _isSharing = true;
    });

    try {
      List<XFile> filesToShare = [];

      for (final photo in _selectedPhotos) {
        XFile fileToShare;

        if (photo.startsWith('http')) {
          final response = await http.get(Uri.parse(photo));
          if (response.statusCode == 200) {
            final tempDir = await getTemporaryDirectory();
            final tempFile = File('${tempDir.path}/share_${DateTime.now().millisecondsSinceEpoch}.jpg');
            await tempFile.writeAsBytes(response.bodyBytes);
            fileToShare = XFile(tempFile.path, mimeType: 'image/jpeg');
          } else {
            continue; // Skip failed downloads
          }
        } else {
          fileToShare = XFile(photo, mimeType: 'image/jpeg');
        }

        filesToShare.add(fileToShare);
      }

      if (filesToShare.isNotEmpty) {
        await Share.shareXFiles(filesToShare, subject: 'Share Rucking Session');

        if (mounted) {
          _showMessage('Photos shared successfully');
          Navigator.pop(context, true);
        }
      } else {
        _showMessage('Failed to prepare photos for sharing');
      }
    } catch (e) {
      AppLogger.error('[SHARE] Share failed: $e', exception: e);
      _showMessage('Share failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSharing = false;
        });
      }
    }
  }

  Future<void> _saveToGallery() async {
    if (_selectedPhotos.isEmpty) {
      _showMessage('No photos to save');
      return;
    }

    final hasAccess = await Gal.hasAccess();
    if (!hasAccess) {
      final granted = await Gal.requestAccess();
      if (!granted) {
        _showMessage('Gallery permission denied');
        return;
      }
    }

    int savedCount = 0;
    for (final photo in _selectedPhotos) {
      try {
        if (photo.startsWith('http')) {
          final response = await http.get(Uri.parse(photo));
          if (response.statusCode == 200) {
            final tempDir = await getTemporaryDirectory();
            final tempFile = File('${tempDir.path}/save_${DateTime.now().millisecondsSinceEpoch}.jpg');
            await tempFile.writeAsBytes(response.bodyBytes);
            await Gal.putImage(tempFile.path);
            savedCount++;
          }
        } else {
          await Gal.putImage(photo);
          savedCount++;
        }
      } catch (e) {
        AppLogger.error('[SAVE] Failed to save photo: $e');
      }
    }

    if (savedCount > 0) {
      _showMessage('$savedCount photo${savedCount > 1 ? 's' : ''} saved to gallery');
    } else {
      _showMessage('Failed to save photos');
    }
  }

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Share Session'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_alt),
            onPressed: _selectedPhotos.isNotEmpty ? _saveToGallery : null,
            tooltip: 'Save to Gallery',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Photo carousel
            if (_selectedPhotos.isNotEmpty)
              Expanded(
                child: PhotoCarousel(
                  photos: _selectedPhotos,
                  onPhotosReordered: (reorderedPhotos) {
                    setState(() {
                      _selectedPhotos = reorderedPhotos;
                    });
                  },
                ),
              )
            else
              const Expanded(
                child: Center(
                  child: Text(
                    'No photos available for this session',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),

            // Share button
            Container(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSharing || _selectedPhotos.isEmpty
                      ? null
                      : _sharePhotos,
                  icon: _isSharing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.share),
                  label: Text(_isSharing ? 'Sharing...' : 'Share Photos'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}