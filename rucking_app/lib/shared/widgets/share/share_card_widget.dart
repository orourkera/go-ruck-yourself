import 'dart:math' as math;
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:rucking_app/features/ruck_session/domain/models/ruck_session.dart';
import 'package:rucking_app/core/models/location_point.dart';
import 'package:rucking_app/core/utils/measurement_utils.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
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
    // For map backgrounds, we need to handle image loading properly
    if (backgroundOption?.type == ShareBackgroundType.map && session.locationPoints?.isNotEmpty == true) {
      return _buildShareCardWithMap();
    }
    
    // For other backgrounds, use the standard build
    return _buildStandardShareCard();
  }
  
  Widget _buildShareCardWithMap() {
    return Container(
      width: 800,
      height: 800,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
      ),
      child: FutureBuilder<Uint8List?>(
        future: _fetchMapImage(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            // Show loading state with gradient background
            return Container(
              width: 800,
              height: 800,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: _buildBackgroundGradient(),
              ),
              child: const Center(child: CircularProgressIndicator()),
            );
          } else if (snapshot.hasError) {
            // Log the error
            print('❌ Error loading map image: ${snapshot.error}');
            
            // Try fallback to URL-based approach
            final mapUrl = _generateMapUrl();
            if (mapUrl != null) {
              return Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.network(
                      mapUrl,
                      width: 800,
                      height: 800,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        print('❌ Fallback map image failed: $error');
                        return Container(
                          width: 800,
                          height: 800,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            gradient: _buildBackgroundGradient(),
                          ),
                        );
                      },
                    ),
                  ),
                  // Content overlay
                  _buildShareCardContent(),
                ],
              );
            } else {
              // Fallback with gradient if no map available
              return _buildStandardShareCard();
            }
          } else if (snapshot.hasData && snapshot.data != null) {
            // We have image bytes - render using Image.memory
            return Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.memory(
                    snapshot.data!,
                    width: 800,
                    height: 800,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      print('❌ Memory image failed: $error');
                      return Container(
                        width: 800,
                        height: 800,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: _buildBackgroundGradient(),
                        ),
                      );
                    },
                  ),
                ),
                // Content overlay
                _buildShareCardContent(),
              ],
            );
          } else {
            // No data but no error - fallback
            return _buildStandardShareCard();
          }
        },
      ),
    );
  }
  
  /// Fetch map image using Stadia Maps POST API
  Future<Uint8List?> _fetchMapImage() async {
    try {
      // Get API key
      String apiKey = dotenv.env['STADIA_MAPS_API_KEY'] ?? '';
      if (apiKey.isEmpty) {
        try {
          dotenv.load();
          apiKey = dotenv.env['STADIA_MAPS_API_KEY'] ?? '';
        } catch (_) {}
      }
      
      if (apiKey.isEmpty) {
        AppLogger.error('STADIA_MAPS_API_KEY is not set. Map generation will fail.', exception: null);
        return null;
      }
      
      // Get location points
      final points = session.locationPoints ?? [];
      if (points.isEmpty) return null;
      
      // Convert to lat/lng pairs and simplify the route
      final coordinates = <Map<String, double>>[];
      for (final point in points) {
        final lat = (point['lat'] ?? point['latitude'] as num?)?.toDouble();
        final lng = (point['lng'] ?? point['longitude'] as num?)?.toDouble();
        
        if (lat != null && lng != null) {
          coordinates.add({'lat': lat, 'lng': lng});
        }
      }
      
      if (coordinates.isEmpty) return null;
      
      // Simplify the route by sampling points (max 50 points for better performance)
      final simplifiedCoordinates = _simplifyRoute(coordinates, 50);
      
      // Calculate bounds for better zoom
      final lats = simplifiedCoordinates.map((p) => p['lat']!);
      final lngs = simplifiedCoordinates.map((p) => p['lng']!);
      final minLat = lats.reduce((a, b) => a < b ? a : b);
      final maxLat = lats.reduce((a, b) => a > b ? a : b);
      final minLng = lngs.reduce((a, b) => a < b ? a : b);
      final maxLng = lngs.reduce((a, b) => a > b ? a : b);
      
      final latSpan = maxLat - minLat;
      final lngSpan = maxLng - minLng;
      
      // Calculate center point
      final centerLat = (minLat + maxLat) / 2;
      final centerLng = (minLng + maxLng) / 2;
      
      // Calculate zoom level based on span (smaller span = higher zoom)
      final maxSpan = latSpan > lngSpan ? latSpan : lngSpan;
      int zoom;
      if (maxSpan > 0.1) {
        zoom = 10; // Very large area
      } else if (maxSpan > 0.05) {
        zoom = 12; // Large area  
      } else if (maxSpan > 0.02) {
        zoom = 14; // Medium area
      } else if (maxSpan > 0.01) {
        zoom = 15; // Small area
      } else {
        zoom = 16; // Very small area
      }
      
      // Build request body using center/zoom approach
      final encodedPolyline = _encodePolyline(simplifiedCoordinates);
      
      final requestBody = {
        'center': '$centerLat,$centerLng',
        'zoom': zoom,
        'size': '800x800',
        'style': 'stamen_terrain',
        'lines': [
          {
            'shape': encodedPolyline,
            'color': 'FF9500',
            'width': 5,
            'cap': 'round',
            'join': 'round'
          }
        ],
      };
      
      // Send POST request to the cacheable endpoint
      final response = await http.post(
        Uri.parse('https://tiles.stadiamaps.com/static_cacheable/stamen_terrain?api_key=$apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );
      
      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        AppLogger.error('Stadia Maps API error: ${response.statusCode} ${response.body}', exception: null);
        return null;
      }
    } catch (e) {
      AppLogger.error('Error in _fetchMapImage', exception: e);
      return null;
    }
  }

  List<Map<String, double>> _simplifyRoute(List<Map<String, double>> coordinates, int maxPoints) {
    if (coordinates.length <= maxPoints) return coordinates;
    
    final simplified = <Map<String, double>>[];
    final step = coordinates.length / maxPoints;
    
    for (int i = 0; i < coordinates.length; i += step.floor()) {
      simplified.add(coordinates[i]);
    }
    
    return simplified;
  }
  
  String _encodePolyline(List<Map<String, double>> coordinates) {
    if (coordinates.isEmpty) return '';
    
    // Implement Google polyline encoding algorithm
    int lat = 0;
    int lng = 0;
    final result = StringBuffer();
    
    for (final coord in coordinates) {
      final newLat = (coord['lat']! * 1e5).round();
      final newLng = (coord['lng']! * 1e5).round();
      
      final deltaLat = newLat - lat;
      final deltaLng = newLng - lng;
      
      lat = newLat;
      lng = newLng;
      
      result.write(_encodeNumber(deltaLat));
      result.write(_encodeNumber(deltaLng));
    }
    
    return result.toString();
  }
  
  String _encodeNumber(int num) {
    // Left-shift the binary value one bit and apply bitwise XOR
    int sgn_num = num << 1;
    if (num < 0) {
      sgn_num = ~sgn_num;
    }
    
    final result = StringBuffer();
    while (sgn_num >= 0x20) {
      result.writeCharCode((0x20 | (sgn_num & 0x1f)) + 63);
      sgn_num >>= 5;
    }
    result.writeCharCode(sgn_num + 63);
    
    return result.toString();
  }
  
  String? _generateMapUrl() {
    if (session.locationPoints == null || session.locationPoints!.isEmpty) {
      return null;
    }
    
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
    
    // Add padding to bounding box (increased padding for better visibility)
    final latPadding = (maxLat - minLat) * 0.15;
    final lngPadding = (maxLng - minLng) * 0.15;
    minLat -= latPadding;
    maxLat += latPadding;
    minLng -= lngPadding;
    maxLng += lngPadding;
    
    // Calculate zoom level dynamically based on the bounding box
    double zoom = _calculateZoomLevel(minLat, maxLat, minLng, maxLng, 800, 800);
    
    // Build the path parameter for route drawing
    final pathPoints = <String>[];
    // Only include up to 100 points to keep URL length reasonable
    final step = points.length > 100 ? (points.length / 100).ceil() : 1;
    for (int i = 0; i < points.length; i += step) {
      final point = points[i];
      pathPoints.add('${point['lat']},${point['lng']}');
    }

    // Build Stadia Maps static map URL with path
    // Docs: https://docs.stadiamaps.com/static-maps/
    String apiKey = dotenv.env['STADIA_MAPS_API_KEY'] ?? '';
    if (apiKey.isEmpty) {
      try {
        dotenv.load();
        apiKey = dotenv.env['STADIA_MAPS_API_KEY'] ?? '';
      } catch (_) {}
    }
    if (apiKey.isEmpty) {
      // If no API key is found, the map request might fail or use a default.
      // Consider logging this or handling it gracefully.
    }

    const style = 'stamen_terrain';
    const format = 'png';
    const size = '800x800'; // reduce to stay within free-tier limits and avoid @2x 2160px

    // Path style: color, opacity, weight, fillcolor, fillopacity
    const pathStyle = 'color:FF9500,weight:4';

    final stadiaMapsUrl = 'https://tiles.stadiamaps.com/static/$style.$format?' +
        'bbox=$minLng,$minLat,$maxLng,$maxLat&' +
        'size=$size&' +
        'path=$pathStyle|${pathPoints.join('|')}&' +
        'api_key=$apiKey';
    return stadiaMapsUrl;
  }
  
  // Calculate appropriate zoom level based on geographic bounds
  double _calculateZoomLevel(double minLat, double maxLat, double minLng, double maxLng, double mapWidth, double mapHeight) {
    const GLOBE_WIDTH = 256; // a constant in Google's map projection
    double latDiff = maxLat - minLat;
    double lngDiff = maxLng - minLng;
    
    // Calculate zoom based on the larger of the two differences
    double latZoom = math.log(mapHeight / GLOBE_WIDTH / latDiff * 360) / math.ln2;
    double lngZoom = math.log(mapWidth / GLOBE_WIDTH / lngDiff * 360) / math.ln2;
    
    // Use the smaller zoom level to ensure everything fits
    double zoom = math.min(latZoom, lngZoom);
    
    // Ensure reasonable bounds
    if (zoom > 18) zoom = 18;
    if (zoom < 1) zoom = 1;
    
    // Round to nearest 0.5 for better consistency
    return (zoom * 2).round() / 2;
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
                  
                  return CustomPaint(
                    size: Size(800, 800),
                    painter: RouteMapPainter(
                      locationPoints: locationPoints,
                      routeColor: AppColors.secondary,
                      strokeWidth: 3.0,
                      simplifyRoute: true,
                      // Use aggressive simplification to prevent URL length issues
                      epsilon: locationPoints.length > 100 ? 0.0002 : 0.00005,
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
        // Debug: More accurate background info
        Builder(
          builder: (context) {
            if (backgroundOption?.type == ShareBackgroundType.map) {
              AppLogger.debug('Map background selected but missing data to display');
              AppLogger.debug('Location points null: ${session.locationPoints == null}');
              AppLogger.debug('Location points empty: ${session.locationPoints?.isEmpty}');
            } else {
              AppLogger.debug('Non-map background type: ${backgroundOption?.type}');
            }
            return const SizedBox.shrink();
          },
        ),
        ],
        
        // Overlay for text readability
        Container(
          width: double.infinity,
          height: double.infinity,
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
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 18.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top section with header
                _buildHeader(),
                
                // Spacing between header and main content
                const SizedBox(height: 24),
                
                // Middle section with main stats
                _buildMainStats(),
                
                // Spacing between main stats and bottom
                const SizedBox(height: 24),
                
                // Bottom section with achievements and footer
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Only show achievements if there are any
                    if (achievements.isNotEmpty) 
                      _buildAchievements(),
                    
                    const SizedBox(height: 12),
                    
                    // Footer
                    _buildFooter(),
                  ],
                ),
              ],
            ),
          ),
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
            fontSize: 18,
          ),
        ),
      ],
    );
  }

  Widget _buildMainStats() {
    // Determine if it's metric or imperial
    final preferMetric = this.preferMetric;
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6), // Reduced vertical padding
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min, // More compact layout
        children: [
          // Time in a large display
          Text(
            'TIME',
            style: AppTextStyles.labelSmall.copyWith(
              color: Colors.white.withAlpha(204),
              letterSpacing: 1.2,
              fontSize: 12, // Smaller font size
            ),
          ),
          const SizedBox(height: 1), // Reduced spacing
          Text(
            _formatDurationDisplay(session.duration),
            style: AppTextStyles.displayLarge.copyWith(
              color: Colors.white, // Changed back to white
              fontWeight: FontWeight.bold,
              fontSize: 40, // Smaller for better fit in Instagram post
            ),
          ),
          
          // Elevation gain (if significant) - more compact
          if (session.elevationGain > 0) ...[  
            const SizedBox(height: 2), // Reduced spacing
            Text(
              'ELEVATION GAIN',
              style: AppTextStyles.labelSmall.copyWith(
                color: Colors.white.withAlpha(204),
                letterSpacing: 1.2,
                fontSize: 10, // Smaller font
              ),
            ),
            Text(
              MeasurementUtils.formatSingleElevation(session.elevationGain, metric: preferMetric),
              style: AppTextStyles.titleMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 16, // Slightly smaller
              ),
            ),
          ],
          
          const SizedBox(height: 8), // Reduced spacing
          
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
                height: 36,
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
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTextStyles.labelSmall.copyWith(
            color: Colors.white.withAlpha(204),
            letterSpacing: 1.0,
            fontSize: 12, // Smaller font
          ),
        ),
        const SizedBox(height: 1), // Reduced spacing
        Text(
          value,
          style: AppTextStyles.titleMedium.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 18, // Smaller font
          ),
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
          style: const TextStyle(fontSize: 24),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: AppTextStyles.titleMedium.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        Text(
          label,
          style: AppTextStyles.labelSmall.copyWith(
            color: Colors.white.withAlpha(204),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildAchievements() {
    final achievementList = achievements.take(2).toList(); // Only show first 2 achievements to save space
  
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'ACHIEVEMENTS',
          style: AppTextStyles.labelSmall.copyWith(
            color: Colors.white.withAlpha(204),
            letterSpacing: 1.0,
            fontSize: 10, // Smaller font
          ),
        ),
        const SizedBox(height: 4), // Reduced spacing
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: achievementList.map((achievement) => 
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), // Smaller padding
              margin: const EdgeInsets.only(right: 6), // Smaller margin
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(51),
                borderRadius: BorderRadius.circular(16), // Smaller radius
              ),
              child: Text(
                achievement,
                style: AppTextStyles.labelSmall.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 10, // Smaller font
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
            fontWeight: FontWeight.bold,
            fontSize: 22, // Increased from 18
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16), // Increased from 10
        Text(
          'Shared from Ruck, the world\'s #1 Rucking App.',
          style: AppTextStyles.bodySmall.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w500,
            fontSize: 12, // Reduced from 14 to fit on one line
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
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
  
  /// Formats a duration to display as h:mm:ss or mm:ss if hours = 0
  /// No leading zeros for hours, but minutes and seconds have leading zeros
  String _formatDurationDisplay(Duration duration) {
    final hours = duration.inHours;
    final minutes = (duration.inMinutes % 60);
    final seconds = (duration.inSeconds % 60);
    
    // Format with zero-padded minutes and seconds for consistency
    final formattedMinutes = minutes.toString().padLeft(2, '0');
    final formattedSeconds = seconds.toString().padLeft(2, '0');
    
    if (hours > 0) {
      // Show hours:minutes:seconds when there are hours
      return '$hours:$formattedMinutes:$formattedSeconds';
    } else {
      // Show only minutes:seconds when no hours
      return '$minutes:$formattedSeconds';
    }
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
      if (session.locationPoints != null && session.locationPoints!.isNotEmpty) {
        try {
          // We'll handle map rendering through the FutureBuilder in the build method
          // because static maps now use POST requests, not GET with URL params
          return null;
        } catch (e) {
          AppLogger.error('Error preparing map background: $e', exception: e);
          return null;
        }
      }
      return null;
    } else if (backgroundOption?.type == ShareBackgroundType.photo) {
      return backgroundOption?.imageUrl != null
          ? DecorationImage(
              image: NetworkImage(backgroundOption!.imageUrl!),
              fit: BoxFit.cover,
              colorFilter: const ColorFilter.mode(
                Colors.black26,
                BlendMode.darken,
              ),
            )
          : null;
    }
    return null;
  }
}
