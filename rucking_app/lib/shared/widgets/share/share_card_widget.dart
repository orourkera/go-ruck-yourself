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
    return Container(
      width: 400,
      height: 600,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: _buildBackgroundGradient(),
        image: _buildBackgroundImage(),
      ),
      child: Stack(
        children: [
          // Route map overlay (only for map backgrounds)
          if (backgroundOption?.type == ShareBackgroundType.map) ...[
            if (session.locationPoints?.isNotEmpty == true) ...[
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
                          color: Colors.grey[300],
                          child: const Center(child: Text('No route data')),
                        );
                      }
                      
                      return CustomPaint(
                        painter: RouteMapPainter(
                          locationPoints: locationPoints,
                          routeColor: AppColors.secondary,
                          strokeWidth: 3.0,
                        ),
                        child: Container(
                          width: 400,
                          height: 600,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ] else ...[
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
          
          // Content
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with app branding
                _buildHeader(),
                
                const Spacer(),
                
                // Main stats section
                _buildMainStats(),
                
                const SizedBox(height: 20),
                
                // Additional stats
                _buildSecondaryStats(),
                
                const SizedBox(height: 20),
                
                // Achievements (if any)
                if (achievements.isNotEmpty) ...[
                  _buildAchievements(),
                  const SizedBox(height: 20),
                ],
                
                // Footer with call to action
                _buildFooter(),
              ],
            ),
          ),
        ],
      ),
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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(38),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withAlpha(51),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // Duration - Main highlight
          Column(
            children: [
              Text(
                'TIME',
                style: AppTextStyles.labelSmall.copyWith(
                  color: Colors.white.withAlpha(204),
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                session.formattedDuration,
                style: AppTextStyles.headlineLarge.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 36,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'ELEVATION GAIN',
                style: AppTextStyles.labelSmall.copyWith(
                  color: Colors.white.withAlpha(204),
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                MeasurementUtils.formatSingleElevation(session.elevationGain, metric: preferMetric),
                style: AppTextStyles.titleMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          // Distance and Weight in a row
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
                height: 40,
                color: Colors.white.withAlpha(76),
              ),
              Expanded(
                child: _buildStatItem(
                  'WEIGHT',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ACHIEVEMENTS',
          style: AppTextStyles.labelMedium.copyWith(
            color: Colors.white.withAlpha(230),
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: achievements.map((achievement) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: (isLadyMode ? AppColors.ladyPrimary : AppColors.primary).withAlpha(204),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              achievement,
              style: AppTextStyles.labelSmall.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          )).toList(),
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
    
    // Handle map backgrounds - create a simple route visualization
    if (backgroundOption?.type == ShareBackgroundType.map) {
      // For now, return null and use a special map gradient background
      // In the future, you could generate an actual map image from session.locationPoints
      return null; // This will use the map gradient from _buildBackgroundGradient
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
