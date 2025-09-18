import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:rucking_app/features/social_sharing/models/instagram_post.dart';
import 'package:rucking_app/features/social_sharing/models/post_template.dart';
import 'package:rucking_app/features/social_sharing/models/time_range.dart';
import 'package:rucking_app/features/social_sharing/services/instagram_post_service.dart';
import 'package:rucking_app/features/social_sharing/services/reel_builder_service.dart';
import 'package:rucking_app/features/social_sharing/widgets/template_selector.dart';
import 'package:rucking_app/features/social_sharing/widgets/photo_carousel.dart';
import 'package:rucking_app/features/social_sharing/screens/share_edit_screen.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/social_sharing/services/reel_builder_service.dart';
import 'package:path/path.dart' as p;

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
  final InstagramPostService _postService = InstagramPostService();
  final TextEditingController _captionController = TextEditingController();

  PostTemplate _selectedTemplate = PostTemplate.beastMode;
  InstagramPost? _generatedPost;
  List<String> _selectedPhotos = [];
  bool _isGenerating = false;
  bool _isSharing = false;
  String _generatingText = '';
  bool _blurRoute = false;
  bool _hideLocation = false;
  bool _isBuildingReel = false;
  String? _builtReelPath;
  
  Future<T> _runWithProgress<T>(
    String initialMessage,
    Future<T> Function(
      void Function(String) updateText,
      void Function(double) updateProgress,
    ) task,
  ) async {
    final text = ValueNotifier<String>(initialMessage);
    final progress = ValueNotifier<double>(0.02);
    final fun = [
      'Sweating…',
      'Frappeing…',
      'Smelting…',
      'Grunting…',
      'Cogitating…',
      'Pontificating…',
      'Scrambling…',
      'Assembling…',
      'Crunching…',
      'Rendering…',
      'Compressing…',
      'Chiseling…',
      'Buffing…',
      'Calibrating…',
      'Tightening straps…',
      'Lacing boots…',
      'Marching in place…',
      'Mapping trails…',
      'Taming pixels…',
      'Sharpening axes…',
      'Packing sand…',
      'Stoking furnace…',
      'Counting steps…',
      'Herding cats…',
    ];
    fun.shuffle(math.Random());
    int funIdx = 0;
    DateTime lastManual = DateTime.now();

    Timer? rot;

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ValueListenableBuilder<String>(
                  valueListenable: text,
                  builder: (_, v, __) => Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 12),
                ValueListenableBuilder<double>(
                  valueListenable: progress,
                  builder: (_, p, __) => LinearProgressIndicator(value: p.clamp(0.0, 1.0)),
                ),
              ],
            ),
          ),
        ),
      );

      rot = Timer.periodic(const Duration(seconds: 2), (_) {
        // Only rotate if no manual update in last ~1.5s
        if (DateTime.now().difference(lastManual).inMilliseconds > 1500) {
          funIdx = (funIdx + 1) % fun.length;
          text.value = fun[funIdx];
        }
      });
    }

    void updateText(String v) {
      lastManual = DateTime.now();
      text.value = v;
    }

    void updateProgress(double v) {
      progress.value = v;
    }

    try {
      final res = await task(updateText, updateProgress);
      return res;
    } finally {
      rot?.cancel();
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      text.dispose();
      progress.dispose();
    }
  }

  @override
  void initState() {
    super.initState();
  }

  Future<void> _shareToInstagram() async {
    print('DEBUG: _shareToInstagram called');
    print('DEBUG: _selectedPhotos.length = ${_selectedPhotos.length}');
    print('DEBUG: _selectedPhotos = $_selectedPhotos');

    if (_selectedPhotos.isEmpty) {
      print('DEBUG: No photos, showing error');
      _showError('No photos to share');
      return;
    }

    setState(() {
      _isSharing = true;
    });

    try {
      // Copy caption to clipboard
      final caption = _captionController.text;
      final hashtags = _generatedPost?.hashtagString ?? '';
      final cta = _generatedPost?.cta ?? '';
      final fullText = '$caption\n\n$cta\n\n$hashtags';

      await Clipboard.setData(ClipboardData(text: fullText));

      // For single photo, just share it
      if (_selectedPhotos.length == 1) {
        print('DEBUG: Single photo path');
        final photo = _selectedPhotos.first;
        XFile fileToShare;

        if (photo.startsWith('http')) {
          final response = await http.get(Uri.parse(photo));
          if (response.statusCode == 200) {
            final tempDir = await getTemporaryDirectory();
            final tempFile = File('${tempDir.path}/instagram_share.jpg');
            await tempFile.writeAsBytes(response.bodyBytes);
            fileToShare = XFile(tempFile.path, mimeType: 'image/jpeg');
          } else {
            _showError('Failed to download image');
            return;
          }
        } else {
          fileToShare = XFile(photo, mimeType: 'image/jpeg');
        }

        await Share.shareXFiles([fileToShare], subject: 'Share to Instagram');

        if (mounted) {
          await _showSuccessDialog();
          Navigator.pop(context, true);
        }
      } else {
        // Multiple photos - create MP4 reel
        print('DEBUG: Multiple photos path - creating reel');
        print('DEBUG: Calling _createAndShareReel...');
        await _createAndShareReel();
        print('DEBUG: _createAndShareReel completed');
      }
    } catch (e) {
      AppLogger.error('[INSTAGRAM] Share failed: $e', exception: e);
      _showError('Failed to share: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSharing = false;
        });
      }
    }
  }

  Future<void> _createAndShareReel() async {
    print('REEL: _createAndShareReel called with ${_selectedPhotos.length} photos');
    AppLogger.info('[REEL] Creating MP4 from ${_selectedPhotos.length} photos');

    setState(() {
      _isBuildingReel = true;
    });

    try {
      final videoPath = await _runWithProgress<String>('Preparing photos...', (update, setProg) async {
        // Download remote images first
        final localPhotos = <String>[];
        for (int i = 0; i < _selectedPhotos.length; i++) {
          update('Preparing photos ${i + 1}/${_selectedPhotos.length}');
          setProg(((i + 1) / _selectedPhotos.length) * 0.4);
          final photo = _selectedPhotos[i];
          if (photo.startsWith('http')) {
            final response = await http.get(Uri.parse(photo));
            if (response.statusCode == 200) {
              final tempDir = await getTemporaryDirectory();
              final tempFile = File('${tempDir.path}/reel_image_$i.jpg');
              await tempFile.writeAsBytes(response.bodyBytes);
              localPhotos.add(tempFile.path);
            }
          } else {
            localPhotos.add(photo);
          }
        }

        if (localPhotos.isEmpty) {
          throw Exception('No photos available to create reel');
        }

        update('Encoding video (~${(localPhotos.length * 2.5).round()}s)');
        setProg(0.6);
        final builder = const ReelBuilderService();
        final path = await builder.buildReel(localPhotos);
        setProg(0.9);
        return path;
      });

      print('REEL: MP4 created at: $videoPath');
      AppLogger.info('[REEL] MP4 created at: $videoPath');

      // Save to camera roll first (best effort). If permission not granted, skip.
      bool savedToGallery = false;
      try {
        // Check if we have permission first
        final hasAccess = await Gal.hasAccess(toAlbum: true);
        if (!hasAccess) {
          await Gal.requestAccess(toAlbum: true);
        }

        // Inline quick modal for save step
        await _runWithProgress('Saving reel to camera roll...', (update, setProg) async {
          try {
            await Gal.putVideo(
              videoPath,
              album: 'Ruck',
            );
            savedToGallery = true;
          } catch (e) {
            AppLogger.warning('[REEL] Failed to save video: $e');
            savedToGallery = false;
          }
          setProg(1.0);
          return 0; // dummy
        });
      } catch (e) {
        AppLogger.warning('[REEL] Save to gallery skipped: $e');
      }

      // Share the MP4 (whether saved to gallery or not)
      await Share.shareXFiles(
        [XFile(videoPath, mimeType: 'video/mp4')],
        subject: 'Share Reel to Instagram',
      );

      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Reel Created!'),
            content: Text(
              savedToGallery
                ? 'Your reel has been saved to camera roll!\n\n'
                  'Caption copied to clipboard.\n'
                  'Share as a Reel in Instagram and paste your caption.'
                : 'Caption copied to clipboard!\n\n'
                  'Share the video to Instagram as a Reel and paste your caption.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(this.context, true);
                },
                child: const Text('Got it'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      AppLogger.error('[REEL] Failed to create reel: $e', exception: e);
      _showError('Failed to create reel: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isBuildingReel = false;
        });
      }
    }
  }

  Future<void> _showSuccessDialog() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Caption Copied!'),
        content: const Text(
          'Your caption has been copied to clipboard.\n\n'
          'Paste it in Instagram to complete your post!',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Future<String?> _showPhotoSelectionDialog() async {
    return await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Photo to Share'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: GridView.builder(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: _selectedPhotos.length,
            itemBuilder: (context, index) {
              final photo = _selectedPhotos[index];
              final isRemoteImage = photo.startsWith('http');

              return GestureDetector(
                onTap: () => Navigator.pop(context, photo),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: isRemoteImage
                        ? Image.network(photo, fit: BoxFit.cover)
                        : Image.file(File(photo), fit: BoxFit.cover),
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _generatePost() async {
    setState(() {
      _isGenerating = true;
      _generatingText = '';
    });

    try {
      final post = await _postService.generatePost(
        timeRange: widget.timeRange ?? TimeRange.lastRuck,
        template: _selectedTemplate,
        sessionId: widget.sessionId,
        onDelta: (delta) {
          setState(() {
            _generatingText += delta;
          });
        },
        onError: (error) {
          AppLogger.error('[SHARE] Generation error: $error');
          _showError('Failed to generate post. Please try again.');
        },
      );

      setState(() {
        _generatedPost = post;
        _captionController.text = post.caption;
        // Keep all photos for reel generation
        _selectedPhotos = post.photos;
        _isGenerating = false;
      });

      await _showEditScreen(post);
    } catch (e) {
      setState(() {
        _isGenerating = false;
      });
      _showError('Failed to generate post: $e');
    }
  }

  Future<void> _showPhotoSelectionDialogOld(String fullText) async {
    final selectedPhoto = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Photo to Share'),
        content: SizedBox(
          width: double.maxFinite,
          child: GridView.builder(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: _selectedPhotos.length,
            itemBuilder: (context, index) {
              final photo = _selectedPhotos[index];
              final isRemoteImage = photo.startsWith('http');

              return GestureDetector(
                onTap: () => Navigator.pop(context, photo),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: isRemoteImage
                        ? Image.network(photo, fit: BoxFit.cover)
                        : Image.file(File(photo), fit: BoxFit.cover),
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (selectedPhoto != null) {
      _shareSelectedPhoto(selectedPhoto, fullText);
    }
  }

  Future<void> _showInstagramShareDialog(String fullText) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Share to Instagram'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your caption has been copied to clipboard. Choose your sharing method:',
            ),
            SizedBox(height: 16),
            Text(
              '📱 System Share: Opens native share sheet (recommended)',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            SizedBox(height: 8),
            Text(
              '📖 Instagram Stories: Direct share to Stories',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _shareToInstagramStories();
            },
            child: const Text('Stories'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _shareViaSystemSheet(fullText);
            },
            child: const Text('System Share'),
          ),
        ],
      ),
    );
  }

  Future<void> _shareSelectedPhoto(String selectedPhoto, String fullText) async {
    // Override the selected photos to just the chosen one BEFORE opening share options,
    // so the subsequent share action uses the user's selection.
    setState(() {
      _selectedPhotos = [selectedPhoto];
    });
    await _showInstagramShareDialog(fullText);
  }

  Future<void> _shareViaSystemSheet(String text) async {
    try {
      if (_selectedPhotos.isNotEmpty) {
        // Instagram only accepts 1 photo, so share just the first one (route map)
        await Share.shareXFiles(
          [XFile(_selectedPhotos.first)],
          text: text,
          subject: 'Check out my ruck!',
        );
      } else {
        await Share.share(
          text,
          subject: 'Check out my ruck!',
        );
      }

      AppLogger.info('[SHARE] Shared via system sheet');
    } catch (e) {
      _showError('Failed to open system share: $e');
    }
  }

  Future<void> _shareToInstagramStories() async {
    try {
      final uri = Uri.parse(
        'instagram-stories://share?source_application=${Uri.encodeComponent('com.rucking.app')}',
      );

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        AppLogger.info('[SHARE] Opened Instagram Stories');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Instagram Stories opened! Your caption is in the clipboard - paste it when adding text.'),
              duration: Duration(seconds: 4),
            ),
          );
        }
      } else {
        _shareViaSystemSheet(_captionController.text + '\n\n${_generatedPost?.cta ?? ''}\n\n' + _generatedPost!.hashtagString);
      }
    } catch (e) {
      AppLogger.warning('[SHARE] Instagram Stories not available: $e');
      _shareViaSystemSheet(_captionController.text + '\n\n${_generatedPost?.cta ?? ''}\n\n' + _generatedPost!.hashtagString);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      appBar: AppBar(
        title: const Text('Share to Instagram'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TemplateSelector(
              selectedTemplate: _selectedTemplate,
              onTemplateSelected: (template) {
                setState(() {
                  _selectedTemplate = template;
                });
              },
            ),
            const SizedBox(height: 24),

            // Privacy controls (show different options based on time range)
            if (widget.timeRange != TimeRange.lastRuck) ...[
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(
                        'Privacy Options',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    SwitchListTile(
                      title: const Text('Hide Location'),
                      subtitle: const Text('Remove location information'),
                      value: _hideLocation,
                      onChanged: (value) {
                        setState(() {
                          _hideLocation = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ] else ...[
              // For Last Ruck, just show privacy notice
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.privacy_tip, color: Colors.green[600]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Route privacy automatically applied - start and end locations are hidden',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.green[600],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            if (_isGenerating) ...[
              Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _generatingText.isEmpty
                          ? 'Generating your Instagram post...'
                          : _generatingText,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ] else if (_generatedPost == null) ...[
              Text(
                'Choose a template and tap Generate to craft an Instagram-ready recap of this ruck.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _generatePost,
                  icon: const Icon(Icons.bolt),
                  label: const Text('Generate Content'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
            if (_generatedPost != null) ...[
              PhotoCarousel(
                photos: _selectedPhotos,
                onPhotosReordered: (updated) {
                  setState(() {
                    _selectedPhotos = updated;
                  });
                },
              ),
              const SizedBox(height: 24),
              Text(
                'Caption Preview',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _captionController,
                maxLines: 6,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  fillColor: theme.colorScheme.surfaceVariant,
                  filled: true,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Hashtags',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _generatedPost!.hashtags
                    .map((tag) => Chip(
                          label: Text(tag.startsWith('#') ? tag : '#$tag'),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: (_isSharing || _selectedPhotos.isEmpty)
                      ? null
                      : _shareToInstagram,
                  icon: const Icon(Icons.share),
                  label: Text(_isSharing
                      ? 'Sharing...'
                      : 'Share to Instagram'),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showEditScreen(InstagramPost post) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ShareEditScreen(
          post: post,
          selectedPhotos: _selectedPhotos,
          blurRoute: _blurRoute,
          hideLocation: _hideLocation,
        ),
      ),
    );
  }
}
