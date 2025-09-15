import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:rucking_app/features/social_sharing/models/instagram_post.dart';
import 'package:rucking_app/features/social_sharing/models/time_range.dart';
import 'package:rucking_app/features/social_sharing/models/post_template.dart';
import 'package:rucking_app/features/social_sharing/services/instagram_post_service.dart';
import 'package:rucking_app/features/social_sharing/widgets/time_range_selector.dart';
import 'package:rucking_app/features/social_sharing/widgets/template_selector.dart';
import 'package:rucking_app/features/social_sharing/widgets/photo_carousel.dart';
import 'package:rucking_app/features/social_sharing/screens/share_edit_screen.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

class SharePreviewScreen extends StatefulWidget {
  final String? sessionId;
  final TimeRange? initialTimeRange;

  const SharePreviewScreen({
    Key? key,
    this.sessionId,
    this.initialTimeRange,
  }) : super(key: key);

  @override
  State<SharePreviewScreen> createState() => _SharePreviewScreenState();
}

class _SharePreviewScreenState extends State<SharePreviewScreen> {
  final InstagramPostService _postService = InstagramPostService();
  final TextEditingController _captionController = TextEditingController();
  final CarouselController _carouselController = CarouselController();

  TimeRange _selectedTimeRange = TimeRange.lastRuck;
  PostTemplate _selectedTemplate = PostTemplate.beastMode;
  InstagramPost? _generatedPost;
  List<String> _selectedPhotos = [];
  bool _isGenerating = false;
  bool _isSharing = false;
  String _generatingText = '';
  bool _blurRoute = false;
  bool _hideLocation = false;

  @override
  void initState() {
    super.initState();
    _selectedTimeRange = widget.initialTimeRange ?? TimeRange.lastRuck;
    // Don't generate post immediately - wait for user to select options
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
        timeRange: _selectedTimeRange,
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
        _selectedPhotos = post.photos.take(3).toList(); // Max 3 photos
        _isGenerating = false;
      });

      // Navigate to edit screen after generation
      _showEditScreen(post);
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
      // Get the updated caption from the text field
      final caption = _captionController.text;
      final hashtags = _generatedPost!.hashtagString;
      final fullText = '$caption\n\n${_generatedPost!.cta}\n\n$hashtags';

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

      // Close the preview screen after sharing
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
        _shareViaSystemSheet(_captionController.text + '\n\n${_generatedPost!.cta}\n\n' + _generatedPost!.hashtagString);
      }
    } catch (e) {
      AppLogger.warning('[SHARE] Instagram Stories not available: $e');
      // Fallback to system share
      _shareViaSystemSheet(_captionController.text + '\n\n${_generatedPost!.cta}\n\n' + _generatedPost!.hashtagString);
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

  void _showEditScreen(InstagramPost post) {
    if (!mounted) return;

    // Navigate to a dedicated edit screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ShareEditScreen(
          post: post,
          selectedPhotos: _selectedPhotos,
          blurRoute: _blurRoute,
          hideLocation: _hideLocation,
        ),
      ),
    ).then((result) {
      // If user completed sharing, close this screen too
      if (result == true && mounted) {
        Navigator.pop(context, true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      appBar: AppBar(
        title: const Text('Share to Instagram'),
        elevation: 0,
        actions: [
          if (_generatedPost != null && !_isSharing)
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
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: _isGenerating
            ? _buildGeneratingView()
            : _generatedPost != null
                ? _buildPreviewView()
                : _buildSelectionView(),
      ),
    );
  }

  Widget _buildGeneratingView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              'Creating your post...',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (_generatingText.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _generatingText,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 10,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewView() {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), // Add extra bottom padding
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time Range Selector
          TimeRangeSelector(
            selectedRange: _selectedTimeRange,
            onRangeSelected: (range) {
              setState(() {
                _selectedTimeRange = range;
              });
              _generatePost();
            },
          ),
          const SizedBox(height: 16),

          // Template Selector
          TemplateSelector(
            selectedTemplate: _selectedTemplate,
            onTemplateSelected: (template) {
              setState(() {
                _selectedTemplate = template;
              });
              _generatePost();
            },
          ),
          const SizedBox(height: 16),

          // Photo Carousel
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _selectedPhotos.isNotEmpty
                ? Column(
                    key: const ValueKey('photos')
                    ,
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
                  maxLines: 10,
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
          if (_generatedPost != null) ...[
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
                        '${_generatedPost!.hashtags.length}/3',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _generatedPost!.hashtags
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
          ],

          // Privacy Settings
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
                  'Privacy',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Blur route start/end'),
                  subtitle: const Text('Hide first and last 500m'),
                  value: _blurRoute,
                  onChanged: (value) {
                    setState(() {
                      _blurRoute = value;
                    });
                  },
                ),
                SwitchListTile(
                  title: const Text('Hide exact location'),
                  subtitle: const Text('Remove specific location tags'),
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
          const SizedBox(height: 24),

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
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSelectionView() {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      color: theme.colorScheme.onPrimaryContainer,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Create Instagram Post',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'AI will create an engaging post based on your selections',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Time Range Selector
          TimeRangeSelector(
            selectedRange: _selectedTimeRange,
            onRangeSelected: (range) {
              setState(() {
                _selectedTimeRange = range;
              });
            },
          ),
          const SizedBox(height: 20),

          // Template Selector
          TemplateSelector(
            selectedTemplate: _selectedTemplate,
            onTemplateSelected: (template) {
              setState(() {
                _selectedTemplate = template;
              });
            },
          ),
          const SizedBox(height: 24),

          // Privacy Settings Preview
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outline.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Privacy Settings',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Blur route start/end'),
                  subtitle: const Text('Hide first and last 500m'),
                  value: _blurRoute,
                  onChanged: (value) {
                    setState(() {
                      _blurRoute = value;
                    });
                  },
                ),
                SwitchListTile(
                  title: const Text('Hide exact location'),
                  subtitle: const Text('Remove specific location tags'),
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
          const SizedBox(height: 32),

          // Generate Button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _generatePost,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Generate Post'),
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to generate post',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text('Please try again'),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _generatePost,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
