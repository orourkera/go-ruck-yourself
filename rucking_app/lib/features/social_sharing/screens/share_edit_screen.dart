import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:rucking_app/features/social_sharing/models/instagram_post.dart';
import 'package:rucking_app/features/social_sharing/widgets/photo_carousel.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

class ShareEditScreen extends StatefulWidget {
  final InstagramPost post;
  final List<String> selectedPhotos;
  final bool blurRoute;
  final bool hideLocation;

  const ShareEditScreen({
    Key? key,
    required this.post,
    required this.selectedPhotos,
    required this.blurRoute,
    required this.hideLocation,
  }) : super(key: key);

  @override
  State<ShareEditScreen> createState() => _ShareEditScreenState();
}

class _ShareEditScreenState extends State<ShareEditScreen> {
  final TextEditingController _captionController = TextEditingController();
  final CarouselController _carouselController = CarouselController();

  bool _isSharing = false;
  late List<String> _selectedPhotos;

  @override
  void initState() {
    super.initState();
    _captionController.text = widget.post.caption;
    _selectedPhotos = List.from(widget.selectedPhotos);
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _shareToInstagram() async {
    setState(() {
      _isSharing = true;
    });

    try {
      // Get the updated caption from the text field
      final caption = _captionController.text;
      final hashtags = widget.post.hashtagString;
      final fullText = '$caption\n\n${widget.post.cta}\n\n$hashtags';

      // Copy to clipboard for user convenience
      await Clipboard.setData(ClipboardData(text: fullText));

      // Show sharing options dialog
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

      // Track share event
      AppLogger.info('[SHARE] Post shared to Instagram');

      // Return to indicate successful sharing
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

  /// Share via system share sheet for best Instagram integration
  Future<void> _shareViaSystemSheet(String text) async {
    try {
      // For optimal Instagram integration, we should share with an image if available
      if (_selectedPhotos.isNotEmpty) {
        // Share with first photo for Instagram compatibility
        await Share.shareXFiles(
          [XFile(_selectedPhotos.first)],
          text: text,
          subject: 'Check out my ruck!',
        );
      } else {
        // Fallback to text-only sharing
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

  /// Share directly to Instagram Stories using URL scheme
  Future<void> _shareToInstagramStories() async {
    try {
      final uri = Uri.parse('instagram-stories://share?source_application=${Uri.encodeComponent('com.rucking.app')}');

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        AppLogger.info('[SHARE] Opened Instagram Stories');

        // Show helpful message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Instagram Stories opened! Your caption is in the clipboard - paste it when adding text.'),
              duration: Duration(seconds: 4),
            ),
          );
        }
      } else {
        // Fallback to system share if Instagram not installed
        _shareViaSystemSheet(_captionController.text + '\n\n${widget.post.cta}\n\n' + widget.post.hashtagString);
      }
    } catch (e) {
      AppLogger.warning('[SHARE] Instagram Stories not available: $e');
      // Fallback to system share
      _shareViaSystemSheet(_captionController.text + '\n\n${widget.post.cta}\n\n' + widget.post.hashtagString);
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
        title: const Text('Edit & Share'),
        elevation: 0,
        actions: [
          if (!_isSharing)
            TextButton.icon(
              onPressed: (_captionController.text.length > 2200)
                  ? null
                  : _shareToInstagram,
              icon: const Icon(Icons.share),
              label: const Text('Share'),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Photo Carousel
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _selectedPhotos.isNotEmpty
                  ? Column(
                      key: const ValueKey('photos'),
                      children: [
                        PhotoCarousel(
                          photos: _selectedPhotos,
                          onPhotosReordered: (photos) {
                            setState(() {
                              _selectedPhotos = photos;
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                    )
                  : Container(
                      key: const ValueKey('no-photos'),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.1)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.photo_library_outlined, color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'No photos selected',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),

            // Caption Editor
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.outline.withOpacity(0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Caption',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${_captionController.text.length}/2200',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _captionController.text.length > 2200
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _captionController,
                    maxLines: 12,
                    decoration: InputDecoration(
                      hintText: 'Edit your caption...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.surfaceVariant,
                    ),
                    onChanged: (text) {
                      setState(() {});
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Hashtags Display
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Hashtags',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${widget.post.hashtags.length}/30',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.post.hashtags
                        .map((tag) => Chip(
                              label: Text(tag.startsWith('#') ? tag : '#$tag'),
                              backgroundColor:
                                  theme.colorScheme.primaryContainer,
                              labelStyle: TextStyle(
                                color: theme.colorScheme.onPrimaryContainer,
                                fontSize: 12,
                              ),
                              visualDensity: VisualDensity.compact,
                            ))
                        .toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Call to Action Display
            if (widget.post.cta.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Call to Action',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.post.cta,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 32),

            // Share Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _isSharing || _captionController.text.length > 2200
                    ? null
                    : _shareToInstagram,
                icon: _isSharing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.share),
                label: Text(_isSharing
                    ? 'Sharing...'
                    : (_captionController.text.length > 2200
                        ? 'Caption too long'
                        : 'Share to Instagram')),
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}