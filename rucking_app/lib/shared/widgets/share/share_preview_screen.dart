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
  int _currentBackgroundIndex = 0;
  late List<ShareBackgroundOption> _backgroundOptions;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _initializeBackgroundOptions();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _initializeBackgroundOptions() {
    _backgroundOptions = [
      // Default gradient
      const ShareBackgroundOption(
        type: ShareBackgroundType.defaultGradient,
        displayName: 'Default',
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
      body: Column(
        children: [
          // Background selection info
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Swipe to change background • ${_backgroundOptions[_currentBackgroundIndex].displayName}',
              style: AppTextStyles.bodyMedium.copyWith(
                color: Colors.white.withAlpha(178),
              ),
              textAlign: TextAlign.center,
            ),
          ),
          
          // Share card preview with swipeable backgrounds
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() {
                  _currentBackgroundIndex = index;
                });
              },
              itemCount: _backgroundOptions.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: _buildShareCardWithBackground(_backgroundOptions[index]),
                  ),
                );
              },
            ),
          ),
          
          // Background indicator dots
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _backgroundOptions.length,
                (index) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: index == _currentBackgroundIndex
                        ? (widget.isLadyMode ? AppColors.ladyPrimary : AppColors.primary)
                        : Colors.white.withAlpha(76),
                  ),
                ),
              ),
            ),
          ),
          
          // Share button
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSharing ? null : _shareSession,
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.isLadyMode ? AppColors.ladyPrimary : AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSharing
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(
                        'Share Your Achievement',
                        style: AppTextStyles.labelLarge.copyWith(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShareCardWithBackground(ShareBackgroundOption backgroundOption) {
    return Container(
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
      child: ShareCardWidget(
        session: widget.session,
        preferMetric: widget.preferMetric,
        achievements: widget.achievements,
        isLadyMode: widget.isLadyMode,
        backgroundOption: backgroundOption,
      ),
    );
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
