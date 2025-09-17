import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:rucking_app/features/social_sharing/models/instagram_post.dart';
import 'package:rucking_app/features/social_sharing/models/post_template.dart';
import 'package:rucking_app/features/social_sharing/models/time_range.dart';
import 'package:rucking_app/features/social_sharing/services/instagram_post_service.dart';
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

  @override
  void initState() {
    super.initState();
  }

  Future<void> _createAndShareReel() async {
    AppLogger.info('[REEL_DEBUG] Starting reel creation');
    AppLogger.info('[REEL_DEBUG] Selected photos count: ${_selectedPhotos.length}');
    for (int i = 0; i < _selectedPhotos.length; i++) {
      AppLogger.info('[REEL_DEBUG] Photo $i: ${_selectedPhotos[i]}');
    }

    if (_selectedPhotos.isEmpty) {
      AppLogger.error('[REEL_DEBUG] No photos selected!');
      _showError('No photos selected');
      return;
    }

    setState(() {
      _isBuildingReel = true;
      _builtReelPath = null;
    });

    try {
      AppLogger.info('[REEL_DEBUG] Building reel with FFmpeg...');
      final builder = const ReelBuilderService();
      final videoPath = await builder.buildReel(_selectedPhotos);
      _builtReelPath = videoPath;

      AppLogger.info('[REEL_DEBUG] Reel built successfully at: $videoPath');

      // Check if file exists
      final videoFile = File(videoPath);
      if (await videoFile.exists()) {
        final fileSize = await videoFile.length();
        AppLogger.info('[REEL_DEBUG] Video file exists, size: ${fileSize / 1024 / 1024} MB');
      } else {
        AppLogger.error('[REEL_DEBUG] Video file does not exist at path: $videoPath');
      }

      // Note: Instagram on iOS doesn't support direct video sharing via share sheet
      // Videos need to be saved to camera roll first, then shared from there
      AppLogger.warning('[REEL_DEBUG] Sharing MP4 to Instagram via share sheet (may not work on iOS)');

      // Share the generated MP4 via system sheet
      await Share.shareXFiles([
        XFile(videoPath, name: p.basename(videoPath), mimeType: 'video/mp4'),
      ], text: _captionController.text);

      AppLogger.info('[REEL_DEBUG] Share sheet dismissed');
    } catch (e) {
      AppLogger.error('[REEL_DEBUG] Build failed: $e', exception: e);
      _showError('Failed to build reel: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isBuildingReel = false;
        });
      }
    }
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

  Future<void> _shareToInstagram() async {
    if (_generatedPost == null) return;

    setState(() {
      _isSharing = true;
    });

    try {
      final caption = _captionController.text;
      final hashtags = _generatedPost!.hashtagString;
      final fullText = '$caption\n\n${_generatedPost!.cta}\n\n$hashtags';

      await Clipboard.setData(ClipboardData(text: fullText));

      // If multiple photos, let user select which one to share
      if (_selectedPhotos.length > 1) {
        await _showPhotoSelectionDialog(fullText);
      } else {
        await _showInstagramShareDialog(fullText);
      }

      AppLogger.info('[SHARE] Post shared to Instagram');

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      _showError('Failed to share: $e');
    } finally {
      setState(() {
        _isSharing = false;
      });
    }
  }

  Future<void> _showPhotoSelectionDialog(String fullText) async {
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
                  onPressed: _isSharing ? null : _shareToInstagram,
                  icon: const Icon(Icons.share),
                  label: Text(_isSharing ? 'Sharing...' : 'Post to Insta'),
                ),
              ),
              const SizedBox(height: 16),
              // Create Reel button (works with 1+ images)
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton.icon(
                  onPressed: _isBuildingReel
                      ? null
                      : () async {
                          await _createAndShareReel();
                        },
                  icon: const Icon(Icons.movie_creation_outlined),
                  label: Text(_isBuildingReel
                      ? 'Building Reel...'
                      : 'Create Reel (MP4)'),
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
