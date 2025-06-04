import 'package:flutter/material.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_session.dart';
import 'package:rucking_app/core/services/share_service.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/share/share_card_widget.dart';
import 'package:rucking_app/shared/widgets/styled_snackbar.dart';

/// Different background types for the share card
enum ShareBackgroundType {
  defaultGradient,
  map,
  photo,
  colorVariation,
}

/// Background option model
class ShareBackgroundOption {
  final ShareBackgroundType type;
  final String? imageUrl;
  final String? mapImageUrl;
  final Color? primaryColor;
  final Color? secondaryColor;
  final String displayName;

  const ShareBackgroundOption({
    required this.type,
    this.imageUrl,
    this.mapImageUrl,
    this.primaryColor,
    this.secondaryColor,
    required this.displayName,
  });
}

/// Screen that shows a preview of the share card before sharing
class SharePreviewScreen extends StatefulWidget {
  final RuckSession session;
  final bool preferMetric;
  final String? backgroundImageUrl;
  final List<String> achievements;
  final bool isLadyMode;
  final List<String>? sessionPhotos;

  const SharePreviewScreen({
    Key? key,
    required this.session,
    required this.preferMetric,
    this.backgroundImageUrl,
    this.achievements = const [],
    this.isLadyMode = false,
    this.sessionPhotos,
  }) : super(key: key);

  @override
  State<SharePreviewScreen> createState() => _SharePreviewScreenState();
}

class _SharePreviewScreenState extends State<SharePreviewScreen> {
  bool _isSharing = false;
  late PageController _pageController;
  late PageController _thumbnailController;
  int _currentBackgroundIndex = 0;
  late List<ShareBackgroundOption> _backgroundOptions;
  
  // Color overlay options for swiping
  final List<Map<String, dynamic>> _colorOverlays = [
    {
      'name': 'None',
      'overlay': Colors.transparent,
      'opacity': 0.0,
    },
    {
      'name': 'Light Dark',
      'overlay': Colors.black,
      'opacity': 0.2,
    },
    {
      'name': 'Dark',
      'overlay': Colors.black,
      'opacity': 0.4,
    },
    {
      'name': 'Blue Tint',
      'overlay': Colors.blue.shade900,
      'opacity': 0.3,
    },
    {
      'name': 'Warm',
      'overlay': Colors.amber.shade900,
      'opacity': 0.2,
    },
    {
      'name': 'Vintage',
      'overlay': Colors.brown.shade800,
      'opacity': 0.3,
    },
  ];
  
  int _currentOverlayIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _thumbnailController = PageController(viewportFraction: 0.25);
    _initializeBackgroundOptions();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _thumbnailController.dispose();
    super.dispose();
  }

  void _initializeBackgroundOptions() {
    _backgroundOptions = [
      // None option (default gradient with transparency)
      const ShareBackgroundOption(
        type: ShareBackgroundType.defaultGradient,
        displayName: 'None',
      ),
    ];

    // Add photo backgrounds FIRST (before map and color variations)
    if (widget.sessionPhotos?.isNotEmpty == true) {
      for (int i = 0; i < widget.sessionPhotos!.length; i++) {
        _backgroundOptions.add(ShareBackgroundOption(
          type: ShareBackgroundType.photo,
          imageUrl: widget.sessionPhotos![i],
          displayName: 'Photo ${i + 1}',
        ));
      }
    }

    // Add map background if available
    if (widget.session.locationPoints?.isNotEmpty == true) {
      _backgroundOptions.add(const ShareBackgroundOption(
        type: ShareBackgroundType.map,
        displayName: 'Map',
      ));
      print('📍 Added map background option - Location points: ${widget.session.locationPoints!.length}');
    } else {
      print('📍 No map background - Location points null: ${widget.session.locationPoints == null}, empty: ${widget.session.locationPoints?.isEmpty}');
      print('📍 Session locationPoints type: ${widget.session.locationPoints.runtimeType}');
      if (widget.session.locationPoints != null) {
        print('📍 First few location points: ${widget.session.locationPoints!.take(2).toList()}');
      }
    }

    // Add color variations at the end
    _backgroundOptions.addAll([
      ShareBackgroundOption(
        type: ShareBackgroundType.colorVariation,
        primaryColor: AppColors.primary,
        secondaryColor: AppColors.secondary,
        displayName: 'Ruck Green',
      ),
      ShareBackgroundOption(
        type: ShareBackgroundType.colorVariation,
        primaryColor: AppColors.ladyPrimary,
        secondaryColor: AppColors.ladyPrimaryLight,
        displayName: 'Lady Mode',
      ),
      const ShareBackgroundOption(
        type: ShareBackgroundType.colorVariation,
        primaryColor: Color(0xFF2E7D32),
        secondaryColor: Color(0xFF81C784),
        displayName: 'Forest',
      ),
      const ShareBackgroundOption(
        type: ShareBackgroundType.colorVariation,
        primaryColor: Color(0xFF1565C0),
        secondaryColor: Color(0xFF64B5F6),
        displayName: 'Ocean',
      ),
      const ShareBackgroundOption(
        type: ShareBackgroundType.colorVariation,
        primaryColor: Color(0xFFEF6C00),
        secondaryColor: Color(0xFFFFB74D),
        displayName: 'Sunset',
      ),
      const ShareBackgroundOption(
        type: ShareBackgroundType.colorVariation,
        primaryColor: Color(0xFF6A1B9A),
        secondaryColor: Color(0xFFBA68C8),
        displayName: 'Mountain',
      ),
    ]);

    // Set initial background to first option
    if (_backgroundOptions.isNotEmpty) {
      _currentBackgroundIndex = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Share Preview',
          style: AppTextStyles.displaySmall.copyWith(color: Colors.white),
        ),
        centerTitle: true,
        actions: [
          if (!_isSharing)
            TextButton(
              onPressed: _shareSession,
              child: Text(
                'SHARE',
                style: AppTextStyles.labelLarge.copyWith(
                  color: widget.isLadyMode ? AppColors.ladyPrimary : AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // First: Background selection carousel at the top
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 16, bottom: 4),
              child: Row(
                children: [
                  Text(
                    'Background:',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _backgroundOptions[_currentBackgroundIndex].displayName,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: Colors.white.withAlpha(200),
                    ),
                  ),
                ],
              ),
            ),
            
            // Background thumbnails
            SizedBox(
              height: 60,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _backgroundOptions.length,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemBuilder: (context, index) {
                  final option = _backgroundOptions[index];
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _currentBackgroundIndex = index;
                        _pageController.animateToPage(
                          index,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      });
                    },
                    child: Container(
                      width: 60,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: index == _currentBackgroundIndex
                              ? (widget.isLadyMode ? AppColors.ladyPrimary : AppColors.primary)
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: _buildBackgroundThumbnail(option),
                      ),
                    ),
                  );
                },
              ),
            ),
            
            // Second: Color overlay selector
            Padding(
              padding: const EdgeInsets.only(top: 12, left: 16, bottom: 4),
              child: Row(
                children: [
                  Text(
                    'Color overlay:',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _colorOverlays[_currentOverlayIndex]['name'],
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: Colors.white.withAlpha(200),
                    ),
                  ),
                ],
              ),
            ),
            
            // Color overlay options
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _colorOverlays.length,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemBuilder: (context, index) {
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _currentOverlayIndex = index;
                      });
                    },
                    child: Container(
                      width: 40,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _colorOverlays[index]['overlay'] == Colors.transparent
                            ? Colors.grey.withOpacity(0.3)
                            : _colorOverlays[index]['overlay'].withOpacity(0.7),
                        border: Border.all(
                          color: index == _currentOverlayIndex
                              ? (widget.isLadyMode ? AppColors.ladyPrimary : AppColors.primary)
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: index == 0
                          ? const Icon(Icons.not_interested, color: Colors.white54, size: 20)
                          : null,
                    ),
                  );
                },
              ),
            ),
            
            // Third: The actual share card preview (takes most space)
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _backgroundOptions.length,
                onPageChanged: (index) {
                  setState(() {
                    _currentBackgroundIndex = index;
                  });
                },
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Center(
                      child: _buildShareCardWithBackground(_backgroundOptions[index]),
                    ),
                  );
                },
              ),
            ),
            
            // Loading indicator during sharing
            if (_isSharing)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildShareCardWithBackground(ShareBackgroundOption backgroundOption) {
    return GestureDetector(
      // Swipe to change color overlay
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity! > 0) {
          // Swipe right - previous overlay
          setState(() {
            _currentOverlayIndex = (_currentOverlayIndex - 1) % _colorOverlays.length;
            if (_currentOverlayIndex < 0) _currentOverlayIndex = _colorOverlays.length - 1;
          });
        } else if (details.primaryVelocity! < 0) {
          // Swipe left - next overlay
          setState(() {
            _currentOverlayIndex = (_currentOverlayIndex + 1) % _colorOverlays.length;
          });
        }
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(76),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          children: [
            // The share card
            ShareCardWidget(
              session: widget.session,
              preferMetric: widget.preferMetric,
              achievements: widget.achievements,
              isLadyMode: widget.isLadyMode,
              backgroundOption: backgroundOption,
            ),
            // The color overlay
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 1080, // Match share card dimensions
                height: 1080,
                color: _colorOverlays[_currentOverlayIndex]['overlay']
                    .withOpacity(_colorOverlays[_currentOverlayIndex]['opacity']),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildBackgroundThumbnail(ShareBackgroundOption option) {
    switch (option.type) {
      case ShareBackgroundType.map:
        return Container(
          color: const Color(0xFF1E3A8A), // Dark blue background for map
          child: const Center(
            child: Icon(
              Icons.map_outlined, 
              color: Colors.white,
              size: 24,
            ),
          ),
        );
        
      case ShareBackgroundType.photo:
        if (option.imageUrl != null) {
          return Image.network(
            option.imageUrl!,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => const Center(
              child: Icon(Icons.broken_image, color: Colors.white),
            ),
          );
        }
        return const Center(
          child: Icon(Icons.image, color: Colors.white),
        );
        
      case ShareBackgroundType.colorVariation:
        if (option.primaryColor != null && option.secondaryColor != null) {
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  option.primaryColor!,
                  option.secondaryColor!,
                ],
              ),
            ),
          );
        }
        return Container(color: option.primaryColor ?? Colors.grey);
        
      case ShareBackgroundType.defaultGradient:
      default:
        return Container(
          color: Colors.grey.shade300,
          child: const Center(
            child: Text(
              'None',
              style: TextStyle(color: Colors.black54),
            ),
          ),
        );
    }
  }

  Future<void> _shareSession() async {
    setState(() {
      _isSharing = true;
    });

    try {
      final selectedBackground = _backgroundOptions[_currentBackgroundIndex];
      
      await ShareService.shareSessionCard(
        context: context,
        session: widget.session,
        preferMetric: widget.preferMetric,
        backgroundImageUrl: selectedBackground.imageUrl,
        achievements: widget.achievements,
        isLadyMode: widget.isLadyMode,
        backgroundOption: selectedBackground, // Pass the selected background option
      );
      
      if (mounted) {
        StyledSnackBar.show(
          context: context,
          message: 'Share card created successfully!',
          type: SnackBarType.success,
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      AppLogger.error('Failed to share session: $e', exception: e);
      
      if (mounted) {
        StyledSnackBar.show(
          context: context,
          message: 'Failed to share session. Please try again.',
          type: SnackBarType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSharing = false;
        });
      }
    }
  }
}
