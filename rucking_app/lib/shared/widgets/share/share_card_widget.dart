import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_session.dart';
import 'package:rucking_app/core/models/location_point.dart';
import 'package:rucking_app/core/utils/measurement_utils.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/share/share_preview_screen.dart'; // For ShareBackgroundOption
import 'package:rucking_app/shared/widgets/share/route_map_painter.dart';

/// A beautiful share card widget that displays session stats and achievements
class ShareCardWidget extends StatelessWidget {
  final RuckSession session;
  final bool preferMetric;
  final String? backgroundImageUrl;
  final List<String> achievements;
  final bool isLadyMode;
  final ShareBackgroundOption? backgroundOption;

  const ShareCardWidget({
    Key? key,
    required this.session,
    required this.preferMetric,
    this.backgroundImageUrl,
    this.achievements = const [],
    this.isLadyMode = false,
    this.backgroundOption,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Debug print for session location points
    if (backgroundOption?.type == ShareBackgroundType.map && session.locationPoints != null) {
      print('🗺️ ShareCardWidget build - Location points count: ${session.locationPoints!.length}');
    }
    
    // For map backgrounds, we need to handle image loading properly
    if (backgroundOption?.type == ShareBackgroundType.map && session.locationPoints?.isNotEmpty == true) {
      return _buildShareCardWithMap();
    }
    
    // For other backgrounds, use the standard build
    return _buildStandardShareCard();
  }
  
  Widget _buildShareCardWithMap() {
    final mapUrl = _generateMapUrl();
    if (mapUrl == null) {
      return _buildStandardShareCard();
    }
    
    // Simple direct approach
    return Container(
      width: 800,
      height: 800,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Stack(
        children: [
          // Map background
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.network(
              mapUrl,
              width: 800,
              height: 800,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                print('❌ Failed to load map image: $error');
                return Container(
                  width: 800,
                  height: 800,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: _buildBackgroundGradient(),
                  ),
                );
              },
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) {
                  return ColorFiltered(
                    colorFilter: ColorFilter.mode(
                      Colors.black.withOpacity(0.3),
                      BlendMode.darken,
                    ),
                    child: child,
                  );
                }
                return Container(
                  width: 800,
                  height: 800,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: _buildBackgroundGradient(),
                  ),
                  child: Center(
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  ),
                );
              },
            ),
          ),
          // Content on top
          _buildShareCardContent(),
        ],
      ),
    );
  }
  
  String? _generateMapUrl() {
    if (session.locationPoints == null || session.locationPoints!.isEmpty) {
      print('❌ No location points available for map background');
      return null;
    }
    
    print('🗺️ Generating map URL with ${session.locationPoints!.length} location points');

    // Calculate route bounds for map centering
    final points = session.locationPoints!
        .where((point) => (point['lat'] != null || point['latitude'] != null) && 
                        (point['lng'] != null || point['longitude'] != null))
        .map((point) => {
              'lat': (point['lat'] ?? point['latitude'] as num).toDouble(),
              'lng': (point['lng'] ?? point['longitude'] as num).toDouble(),
            })
        .toList();

    if (points.isEmpty) {
      print('❌ No valid lat/lng points found');
      return null;
    }

    // Calculate bounding box
    double minLat = points.first['lat']!;
    double maxLat = points.first['lat']!;
    double minLng = points.first['lng']!;
    double maxLng = points.first['lng']!;

    for (final point in points) {
      minLat = minLat < point['lat']! ? minLat : point['lat']!;
      maxLat = maxLat > point['lat']! ? maxLat : point['lat']!;
      minLng = minLng < point['lng']! ? minLng : point['lng']!;
      maxLng = maxLng > point['lng']! ? maxLng : point['lng']!;
    }
    
    // Add padding to bounding box
    final latPadding = (maxLat - minLat) * 0.1;
    final lngPadding = (maxLng - minLng) * 0.1;
    minLat -= latPadding;
    maxLat += latPadding;
    minLng -= lngPadding;
    maxLng += lngPadding;
    
    // Calculate center
    final centerLat = (minLat + maxLat) / 2;
    final centerLng = (minLng + maxLng) / 2;
    
    // Build Stadia Maps static map URL (correct format)
    // Docs: https://docs.stadiamaps.com/static-maps/
    String apiKey = dotenv.env['STADIA_MAPS_API_KEY'] ?? '';
    if (apiKey.isEmpty) {
      try {
        dotenv.load();
        apiKey = dotenv.env['STADIA_MAPS_API_KEY'] ?? '';
      } catch (_) {}
    }
    if (apiKey.isEmpty) {
      // Fallback dev key (remove in production)
      apiKey = '5e17b67d-2b4c-4337-ba79-91a0e72d8d0c';
    }

    const style = 'alidade_smooth';
    const format = 'png';
    const zoom = 13; // reasonable default; API can auto-fit, but explicit zoom is fine
    const size = '800x800'; // reduce to stay within free-tier limits and avoid @2x 2160px

    final stadiaMapsUrl = 'https://tiles.stadiamaps.com/static/$style.$format?' +
        'center=$centerLat,$centerLng&' +
        'zoom=$zoom&' +
        'size=$size&' +
        'api_key=$apiKey';
    print('🗺️ Stadia static map URL → $stadiaMapsUrl');
    return stadiaMapsUrl;
  }
  
  Widget _buildStandardShareCard() {
    return Container(
      width: 800,
      height: 800,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: _buildBackgroundGradient(),
        image: _buildBackgroundImage(),
      ),
      child: _buildShareCardContent(),
    );
  }
  
  Widget _buildShareCardContent() {
    return Stack(
      children: [
        // Only draw route map overlay when we have a map background
        if (backgroundOption?.type == ShareBackgroundType.map && session.locationPoints?.isNotEmpty == true) ...[  
          // Debug: Print location points info
          Builder(
            builder: (context) {
              print('🗺️ Map background selected - Location points: ${session.locationPoints?.length}');
              if (session.locationPoints?.isNotEmpty == true) {
                print('🗺️ First point: ${session.locationPoints!.first}');
                print('🗺️ Last point: ${session.locationPoints!.last}');
                
                // Test conversion
                final converted = session.locationPoints!
                    .where((point) => (point['lat'] != null || point['latitude'] != null) && 
                                    (point['lng'] != null || point['longitude'] != null))
                    .map((point) => LocationPoint(
                      latitude: (point['lat'] ?? point['latitude'] as num).toDouble(),
                      longitude: (point['lng'] ?? point['longitude'] as num).toDouble(),
                      elevation: 0.0,
                      timestamp: DateTime.now(),
                      accuracy: 0.0,
                    ))
                    .toList();
                print('🗺️ Converted points: ${converted.length}');
                if (converted.isNotEmpty) {
                  print('🗺️ First converted: lat=${converted.first.latitude}, lng=${converted.first.longitude}');
                }
              }
              return const SizedBox.shrink();
            },
          ),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Builder(
                builder: (context) {
                  // Calculate route points for the painter
                  final locationPoints = session.locationPoints!
                      .where((point) => (point['lat'] != null || point['latitude'] != null) && 
                              (point['lng'] != null || point['longitude'] != null))
                      .map((point) => LocationPoint(
                        latitude: (point['lat'] ?? point['latitude'] as num).toDouble(),
                        longitude: (point['lng'] ?? point['longitude'] as num).toDouble(),
                        elevation: 0.0,
                        timestamp: DateTime.now(),
                        accuracy: 0.0,
                      ))
                      .toList();
                  
                  if (locationPoints.isEmpty) {
                    return Container(
                      width: 800,
                      height: 800,
                      color: Colors.grey[300],
                      child: const Center(child: Text('No route data')),
                    );
                  }
                  
                  print('🎨 RouteMapPainter.paint called - Size: Size(800.0, 800.0), Points: ${locationPoints.length}');
                  return CustomPaint(
                    size: Size(800, 800),
                    painter: RouteMapPainter(
                      locationPoints: locationPoints,
                      routeColor: AppColors.secondary,
                      strokeWidth: 3.0,
                    ),
                    child: Container(
                      width: 800,
                      height: 800,
                    ),
                  );
                },
              ),
            ),
          ),
        ] else ... [
          // Debug: Why map is not showing
          Builder(
            builder: (context) {
              print('🗺️ Map background selected but no location points');
              print('🗺️ Background type: ${backgroundOption?.type}');
              print('🗺️ Location points null: ${session.locationPoints == null}');
              print('🗺️ Location points empty: ${session.locationPoints?.isEmpty}');
              return const SizedBox.shrink();
            },
          ),
        ],
        
        // Overlay for text readability
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withAlpha(25),
                Colors.black.withAlpha(100),
                Colors.black.withAlpha(175),
              ],
            ),
          ),
        ),
        
        // Content on top of the background
        Column(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 12),
                    _buildMainStats(),
                    const SizedBox(height: 10),
                    // Only show achievements if there's space
                    if (achievements.isNotEmpty && achievements.length <= 3) ...[  
                      _buildAchievements(),
                      const SizedBox(height: 8), 
                    ],
                  ],
                ),
              ),
            ),
            _buildFooter(),
          ],
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date
        Text(
          MeasurementUtils.formatDate(session.startTime),
          style: AppTextStyles.bodyMedium.copyWith(
            color: Colors.white.withAlpha(230),
          ),
        ),
      ],
    );
  }

  Widget _buildMainStats() {
    // Determine if it's metric or imperial
    final preferMetric = this.preferMetric;
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Time in a large display
          Text(
            'TIME',
            style: AppTextStyles.labelSmall.copyWith(
              color: Colors.white.withAlpha(204),
              letterSpacing: 1.2,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${session.duration.inHours}:${(session.duration.inMinutes % 60).toString().padLeft(2, '0')}',
            style: AppTextStyles.displayLarge.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 42, // Slightly smaller for better fit
            ),
          ),
          
          // Elevation gain (if significant) - more compact
          if (session.elevationGain > 0) ...[  
            const SizedBox(height: 4),
            Text(
              'ELEVATION GAIN',
              style: AppTextStyles.labelSmall.copyWith(
                color: Colors.white.withAlpha(204),
                letterSpacing: 1.2,
                fontSize: 10,
              ),
            ),
            Text(
              MeasurementUtils.formatSingleElevation(session.elevationGain, metric: preferMetric),
              style: AppTextStyles.titleMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ],
          
          const SizedBox(height: 12),
          
          // Distance and Weight in a row - more compact
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  'DISTANCE',
                  MeasurementUtils.formatDistance(session.distance, metric: preferMetric),
                ),
              ),
              Container(
                width: 1,
                height: 30,
                color: Colors.white.withAlpha(76),
              ),
              Expanded(
                child: _buildStatItem(
                  'RUCK WEIGHT',
                  session.ruckWeightKg == 0.0 
                    ? 'Hike' 
                    : MeasurementUtils.formatWeight(session.ruckWeightKg, metric: preferMetric),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: AppTextStyles.labelSmall.copyWith(
            color: Colors.white.withAlpha(204),
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTextStyles.titleLarge.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildSecondaryStats() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildSmallStat('🔥', '${session.caloriesBurned}', 'calories'),
        if (session.elevationGain > 50) // Only show if significant elevation
          _buildSmallStat('⛰️', '${session.elevationGain.round()}m', 'elevation'),
        _buildSmallStat('⚡', _formatPace(), 'pace'),
      ],
    );
  }

  Widget _buildSmallStat(String emoji, String value, String label) {
    return Column(
      children: [
        Text(
          emoji,
          style: const TextStyle(fontSize: 20),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTextStyles.titleMedium.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: AppTextStyles.labelSmall.copyWith(
            color: Colors.white.withAlpha(204),
          ),
        ),
      ],
    );
  }

  Widget _buildAchievements() {
    final achievementList = achievements.take(2).toList(); // Only show first 2 achievements to save space
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'ACHIEVEMENTS',
          style: AppTextStyles.labelSmall.copyWith(
            color: Colors.white.withAlpha(204),
            letterSpacing: 1.2,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: achievementList.map((achievement) => 
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(51),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                achievement,
                style: AppTextStyles.labelSmall.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 10,
                ),
              ),
            ),
          ).toList(),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Session completed! 💪',
          style: AppTextStyles.titleMedium.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Shared from Ruck, the world\'s #1 Rucking App.',
          style: AppTextStyles.bodySmall.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  String _formatPace() {
    final distance = session.distance;
    if (distance <= 0) return '--';
    
    final durationSeconds = session.duration.inSeconds;
    if (durationSeconds <= 0) return '--';
    
    final totalMinutes = durationSeconds / 60.0;
    final pacePerUnit = totalMinutes / (preferMetric ? distance : distance * 0.621371);
    
    final minutes = pacePerUnit.floor();
    final seconds = ((pacePerUnit - minutes) * 60).round();
    
    final unit = preferMetric ? '/km' : '/mi';
    return '${minutes}:${seconds.toString().padLeft(2, '0')}$unit';
  }

  LinearGradient _buildBackgroundGradient() {
    // Handle custom color variation backgrounds
    if (backgroundOption?.type == ShareBackgroundType.colorVariation && 
        backgroundOption?.primaryColor != null && 
        backgroundOption?.secondaryColor != null) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          backgroundOption!.primaryColor!,
          backgroundOption!.secondaryColor!,
        ],
      );
    }
    
    // If there's a background image from backgroundOption, use transparent gradient
    if (backgroundOption?.type == ShareBackgroundType.photo && 
        backgroundOption?.imageUrl != null) {
      return const LinearGradient(colors: [Colors.transparent, Colors.transparent]);
    }
    
    // Handle map backgrounds with a distinctive green/blue gradient
    if (backgroundOption?.type == ShareBackgroundType.map) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF0D4F3C), // Dark forest green
          const Color(0xFF1E3A8A), // Dark blue
          const Color(0xFF1F2937), // Dark gray
        ],
        stops: const [0.0, 0.6, 1.0],
      );
    }
    
    // Legacy: If there's a background image, use transparent gradient
    if (backgroundImageUrl != null) {
      return const LinearGradient(colors: [Colors.transparent, Colors.transparent]);
    }
    
    // Default gradients based on lady mode
    if (isLadyMode) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppColors.ladyPrimary,
          AppColors.ladyPrimaryLight,
        ],
      );
    } else {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppColors.primary,
          AppColors.secondary,
        ],
      );
    }
  }

  DecorationImage? _buildBackgroundImage() {
    // Don't build background image if we're already handling map in _buildShareCardWithMap
    if (backgroundOption?.type == ShareBackgroundType.map) {
      return null;
    }
    
    // Handle photo backgrounds
    if (backgroundOption?.type == ShareBackgroundType.photo && 
        backgroundOption?.imageUrl != null) {
      return DecorationImage(
        image: NetworkImage(backgroundOption!.imageUrl!),
        fit: BoxFit.cover,
        colorFilter: ColorFilter.mode(
          Colors.black.withAlpha(102),
          BlendMode.darken,
        ),
      );
    }
    
    // Legacy background image handling
    if (backgroundImageUrl != null) {
      return DecorationImage(
        image: NetworkImage(backgroundImageUrl!),
        fit: BoxFit.cover,
        colorFilter: ColorFilter.mode(
          Colors.black.withAlpha(76),
          BlendMode.darken,
        ),
      );
    }
    
    return null;
  }
}
