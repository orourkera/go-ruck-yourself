import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/utils/measurement_utils.dart';
import 'package:rucking_app/features/social_sharing/models/time_range.dart';
import 'package:rucking_app/features/social_sharing/models/post_template.dart';

/// Service for generating stats visualization cards for social sharing
class StatsVisualizationService {
  static const double _cardWidth = 1080.0;
  static const double _cardHeight = 1080.0;

  /// Generate a stats visualization card for Instagram sharing
  /// Returns the image as bytes, or null if generation fails
  Future<Uint8List?> generateStatsCard({
    required Map<String, dynamic> insights,
    required TimeRange timeRange,
    required PostTemplate template,
    bool preferMetric = true,
  }) async {
    try {
      AppLogger.info('[STATS_VIZ] Generating stats card for ${timeRange.displayName}');

      // Extract stats based on time range
      final stats = _extractTimeRangeStats(insights, timeRange);
      if (stats.isEmpty) {
        AppLogger.warning('[STATS_VIZ] No stats available for ${timeRange.displayName}');
        return null;
      }

      // Create the visualization widget
      final cardWidget = _buildStatsCard(
        stats: stats,
        timeRange: timeRange,
        template: template,
        preferMetric: preferMetric,
        insights: insights,
      );

      // Convert widget to image bytes
      final imageBytes = await _widgetToBytes(
        cardWidget,
        insights: insights,
        timeRange: timeRange,
        template: template,
        preferMetric: preferMetric,
      );

      if (imageBytes != null) {
        AppLogger.info('[STATS_VIZ] Successfully generated stats card');
        return imageBytes;
      } else {
        AppLogger.warning('[STATS_VIZ] Failed to generate stats card');
        return null;
      }
    } catch (e) {
      AppLogger.error('[STATS_VIZ] Error generating stats card: $e');
      return null;
    }
  }

  /// Extract relevant stats based on time range
  Map<String, dynamic> _extractTimeRangeStats(Map<String, dynamic> insights, TimeRange timeRange) {
    switch (timeRange) {
      case TimeRange.week:
        return _mapWithStringKeys(insights['weekly_stats']);
      case TimeRange.month:
        return _mapWithStringKeys(insights['monthly_stats']);
      case TimeRange.allTime:
        return _mapWithStringKeys(insights['all_time_stats']);
      case TimeRange.lastRuck:
        // Check if we have time_range data from backend (when time_range=last_ruck is specified)
        if (insights['time_range'] != null) {
          final timeRangeData = _mapWithStringKeys(insights['time_range']);
          // Convert backend format to expected frontend format
          return {
            'total_distance': timeRangeData['total_distance_km'],
            'total_duration': timeRangeData['total_duration_seconds'],
            'total_calories': timeRangeData['total_calories'],
            'total_elevation_gain': timeRangeData['elevation_gain_m'],
            'session_count': timeRangeData['sessions_count'],
          };
        }
        // Fallback to recent_sessions format if available
        final recentSessions = insights['recent_sessions'] as List? ?? [];
        if (recentSessions.isNotEmpty) {
          return _mapWithStringKeys(recentSessions[0]);
        }
        return {};
    }
  }

  /// Safely convert dynamic map-like objects to `Map<String, dynamic>`.
  Map<String, dynamic> _mapWithStringKeys(dynamic value) {
    if (value == null) return {};
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return {};
  }

  /// Build the stats card widget
  Widget _buildStatsCard({
    required Map<String, dynamic> stats,
    required TimeRange timeRange,
    required PostTemplate template,
    required bool preferMetric,
    required Map<String, dynamic> insights,
  }) {
    return Container(
      width: _cardWidth,
      height: _cardHeight,
      decoration: BoxDecoration(
        gradient: _getTemplateGradient(template),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Stack(
        children: [
          // Background pattern
          Positioned.fill(
            child: CustomPaint(
              painter: _BackgroundPatternPainter(template),
            ),
          ),
          // Main content
          Padding(
            padding: const EdgeInsets.all(60),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                _buildHeader(timeRange, template),
                const Spacer(),
                // Main stats grid
                _buildStatsGrid(stats, preferMetric, template),
                const Spacer(),
                // Achievements section
                _buildAchievementsSection(insights, template),
                const SizedBox(height: 40),
                // Footer
                _buildFooter(template),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build the card header
  Widget _buildHeader(TimeRange timeRange, PostTemplate template) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          timeRange.displayName.toUpperCase(),
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w900,
            color: _getTextColor(template),
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'RUCKING STATS',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: _getTextColor(template).withOpacity(0.8),
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  /// Build the main stats grid
  Widget _buildStatsGrid(Map<String, dynamic> stats, bool preferMetric, PostTemplate template) {
    final statsList = _getDisplayStats(stats, preferMetric);

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.2,
      crossAxisSpacing: 30,
      mainAxisSpacing: 30,
      children: statsList.map((stat) => _buildStatCard(stat, template)).toList(),
    );
  }

  /// Build individual stat card
  Widget _buildStatCard(Map<String, String> stat, PostTemplate template) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            stat['value']!,
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              color: _getTextColor(template),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            stat['label']!,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _getTextColor(template).withOpacity(0.9),
            ),
            textAlign: TextAlign.center,
          ),
          if (stat['subtitle'] != null) ...[
            const SizedBox(height: 4),
            Text(
              stat['subtitle']!,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _getTextColor(template).withOpacity(0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  /// Build achievements section
  Widget _buildAchievementsSection(Map<String, dynamic> insights, PostTemplate template) {
    final achievements = insights['achievements'] as List? ?? [];
    if (achievements.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ACHIEVEMENTS',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _getTextColor(template),
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: achievements.take(3).map((achievement) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '🏆',
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    achievement.toString(),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _getTextColor(template),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  /// Build footer with branding
  Widget _buildFooter(PostTemplate template) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.hiking,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '@get.rucky',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _getTextColor(template),
              ),
            ),
          ],
        ),
        Text(
          _getTemplateTagline(template),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: _getTextColor(template).withOpacity(0.8),
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  /// Get display stats based on available data
  List<Map<String, String>> _getDisplayStats(Map<String, dynamic> stats, bool preferMetric) {
    final displayStats = <Map<String, String>>[];

    // Total distance
    if (stats['total_distance'] != null) {
      final distance = stats['total_distance'] as double;
      displayStats.add({
        'value': MeasurementUtils.formatDistance(distance, metric: preferMetric),
        'label': 'DISTANCE',
      });
    }

    // Total time
    if (stats['total_duration'] != null) {
      final duration = Duration(seconds: (stats['total_duration'] as num).round());
      displayStats.add({
        'value': _formatDuration(duration),
        'label': 'TIME',
      });
    }

    // Sessions count
    if (stats['session_count'] != null) {
      displayStats.add({
        'value': stats['session_count'].toString(),
        'label': 'SESSIONS',
      });
    }

    // Average pace
    if (stats['avg_pace'] != null) {
      final paceSeconds = (stats['avg_pace'] as num).toDouble();
      displayStats.add({
        'value': MeasurementUtils.formatPace(paceSeconds, metric: preferMetric),
        'label': 'AVG PACE',
      });
    }

    // Total elevation
    if (stats['total_elevation_gain'] != null) {
      final elevation = stats['total_elevation_gain'] as double;
      displayStats.add({
        'value': MeasurementUtils.formatElevation(elevation, 0.0, metric: preferMetric),
        'label': 'ELEVATION',
      });
    }

    // Total calories
    if (stats['total_calories'] != null) {
      displayStats.add({
        'value': (stats['total_calories'] as num).round().toString(),
        'label': 'CALORIES',
      });
    }

    return displayStats.take(4).toList(); // Maximum 4 stats for 2x2 grid
  }

  /// Format duration for display
  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }

  /// Get template-specific gradient
  LinearGradient _getTemplateGradient(PostTemplate template) {
    switch (template) {
      case PostTemplate.beastMode:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1a1a2e),
            Color(0xFF16213e),
            Color(0xFF0f3460),
          ],
        );
      case PostTemplate.journey:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF667eea),
            Color(0xFF764ba2),
            Color(0xFF8e44ad),
          ],
        );
      case PostTemplate.community:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF11998e),
            Color(0xFF38ef7d),
            Color(0xFF2ed573),
          ],
        );
    }
  }

  /// Get template-specific text color
  Color _getTextColor(PostTemplate template) {
    return Colors.white; // All templates use white text for contrast
  }

  /// Get template-specific tagline
  String _getTemplateTagline(PostTemplate template) {
    switch (template) {
      case PostTemplate.beastMode:
        return 'Beast Mode Activated';
      case PostTemplate.journey:
        return 'Every Step Counts';
      case PostTemplate.community:
        return 'Stronger Together';
    }
  }

  /// Convert widget to image bytes using proper Canvas rendering
  Future<Uint8List?> _widgetToBytes(
    Widget widget, {
    required Map<String, dynamic> insights,
    required TimeRange timeRange,
    required PostTemplate template,
    required bool preferMetric,
  }) async {
    try {
      // Create a picture recorder to capture drawing commands
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);

      // Create a custom painter that renders the stats card
      final painter = _StatsPainter(
        stats: insights,
        timeRange: timeRange,
        template: template,
        preferMetric: preferMetric,
      );
      painter.paint(canvas, const Size(_cardWidth, _cardHeight));

      // End recording and create the image
      final ui.Picture picture = recorder.endRecording();
      final ui.Image image = await picture.toImage(_cardWidth.toInt(), _cardHeight.toInt());

      // Convert to PNG bytes
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      // Dispose of resources
      picture.dispose();
      image.dispose();

      return byteData?.buffer.asUint8List();
    } catch (e) {
      AppLogger.error('[STATS_VIZ] Error converting widget to bytes: $e');
      return null;
    }
  }
}

/// Custom painter for background patterns
class _BackgroundPatternPainter extends CustomPainter {
  final PostTemplate template;

  _BackgroundPatternPainter(this.template);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // Draw subtle grid pattern
    const spacing = 40.0;

    // Vertical lines
    for (double x = spacing; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Horizontal lines
    for (double y = spacing; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Add template-specific accent
    _drawTemplateAccent(canvas, size);
  }

  void _drawTemplateAccent(Canvas canvas, Size size) {
    final accentPaint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..style = PaintingStyle.fill;

    switch (template) {
      case PostTemplate.beastMode:
        // Lightning bolt style accent
        final path = Path();
        path.moveTo(size.width * 0.8, 0);
        path.lineTo(size.width * 0.9, size.height * 0.3);
        path.lineTo(size.width * 0.85, size.height * 0.3);
        path.lineTo(size.width * 0.95, size.height * 0.6);
        path.lineTo(size.width, size.height * 0.6);
        path.lineTo(size.width, 0);
        path.close();
        canvas.drawPath(path, accentPaint);
        break;
      case PostTemplate.journey:
        // Mountain silhouette
        final path = Path();
        path.moveTo(size.width * 0.7, size.height);
        path.lineTo(size.width * 0.75, size.height * 0.8);
        path.lineTo(size.width * 0.8, size.height * 0.9);
        path.lineTo(size.width * 0.85, size.height * 0.7);
        path.lineTo(size.width * 0.9, size.height * 0.85);
        path.lineTo(size.width * 0.95, size.height * 0.75);
        path.lineTo(size.width, size.height * 0.9);
        path.lineTo(size.width, size.height);
        path.close();
        canvas.drawPath(path, accentPaint);
        break;
      case PostTemplate.community:
        // Connected circles
        const radius = 20.0;
        final positions = [
          Offset(size.width * 0.85, size.height * 0.15),
          Offset(size.width * 0.92, size.height * 0.22),
          Offset(size.width * 0.88, size.height * 0.28),
        ];

        for (final pos in positions) {
          canvas.drawCircle(pos, radius, accentPaint);
        }

        // Connect with lines
        final linePaint = Paint()
          ..color = Colors.white.withOpacity(0.08)
          ..strokeWidth = 2;
        canvas.drawLine(positions[0], positions[1], linePaint);
        canvas.drawLine(positions[1], positions[2], linePaint);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Custom painter that renders a stats card directly to canvas
class _StatsPainter extends CustomPainter {
  final Map<String, dynamic> stats;
  final TimeRange timeRange;
  final PostTemplate template;
  final bool preferMetric;

  _StatsPainter({
    required this.stats,
    required this.timeRange,
    required this.template,
    required this.preferMetric,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Create the stats card painting manually
    _paintStatsCard(canvas, size);
  }

  void _paintStatsCard(Canvas canvas, Size size) {
    // Get template-specific gradient colors
    final gradientColors = _getGradientColors(template);

    // Background gradient
    final Paint backgroundPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: gradientColors,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    // Draw background
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(20),
      ),
      backgroundPaint,
    );

    // Draw grid pattern
    final Paint gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    const spacing = 40.0;
    // Vertical lines
    for (double x = spacing; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    // Horizontal lines
    for (double y = spacing; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Draw header text
    _drawText(
      canvas,
      timeRange.displayName.toUpperCase(),
      const Offset(60, 80),
      const TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w900,
        color: Colors.white,
        letterSpacing: 2,
      ),
    );

    _drawText(
      canvas,
      'RUCKING STATS',
      const Offset(60, 120),
      TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: Colors.white.withOpacity(0.8),
        letterSpacing: 1,
      ),
    );

    // Draw dynamic stats
    final displayStats = _getDisplayStats();
    if (displayStats.isNotEmpty) {
      for (int i = 0; i < displayStats.length && i < 4; i++) {
        final stat = displayStats[i];
        final x = i % 2 == 0 ? 60.0 : 580.0;
        final y = i < 2 ? 300.0 : 480.0;
        _drawStatCard(canvas, stat['value']!, stat['label']!, Offset(x, y));
      }
    }

    // Draw footer
    _drawText(
      canvas,
      '@get.rucky',
      Offset(60, size.height - 100),
      const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    );

    _drawText(
      canvas,
      _getTagline(),
      Offset(size.width - 200, size.height - 100),
      TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: Colors.white.withOpacity(0.8),
        fontStyle: FontStyle.italic,
      ),
    );
  }

  void _drawStatCard(Canvas canvas, String value, String label, Offset position) {
    // Card background
    final Paint cardPaint = Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..style = PaintingStyle.fill;

    final Paint borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.2)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final cardRect = Rect.fromLTWH(position.dx, position.dy, 460, 140);
    final cardRRect = RRect.fromRectAndRadius(cardRect, const Radius.circular(16));

    canvas.drawRRect(cardRRect, cardPaint);
    canvas.drawRRect(cardRRect, borderPaint);

    // Draw value
    _drawText(
      canvas,
      value,
      Offset(position.dx + 230, position.dy + 40),
      const TextStyle(
        fontSize: 36,
        fontWeight: FontWeight.w800,
        color: Colors.white,
      ),
      textAlign: TextAlign.center,
    );

    // Draw label
    _drawText(
      canvas,
      label,
      Offset(position.dx + 230, position.dy + 90),
      TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Colors.white.withOpacity(0.9),
      ),
      textAlign: TextAlign.center,
    );
  }

  void _drawText(Canvas canvas, String text, Offset position, TextStyle style, {TextAlign textAlign = TextAlign.left}) {
    final textSpan = TextSpan(text: text, style: style);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
      textAlign: textAlign,
    );

    textPainter.layout();

    // Adjust position for center alignment
    Offset drawPosition = position;
    if (textAlign == TextAlign.center) {
      drawPosition = Offset(position.dx - textPainter.width / 2, position.dy);
    }

    textPainter.paint(canvas, drawPosition);
  }

  /// Get template-specific gradient colors
  List<Color> _getGradientColors(PostTemplate template) {
    switch (template) {
      case PostTemplate.beastMode:
        return [
          const Color(0xFF1a1a2e),
          const Color(0xFF16213e),
          const Color(0xFF0f3460),
        ];
      case PostTemplate.journey:
        return [
          const Color(0xFF667eea),
          const Color(0xFF764ba2),
          const Color(0xFF8e44ad),
        ];
      case PostTemplate.community:
        return [
          const Color(0xFF11998e),
          const Color(0xFF38ef7d),
          const Color(0xFF2ed573),
        ];
    }
  }

  /// Get display stats for the painter
  List<Map<String, String>> _getDisplayStats() {
    final displayStats = <Map<String, String>>[];
    final statsData = _extractTimeRangeStats();

    // Total distance
    if (statsData['total_distance'] != null) {
      final distance = statsData['total_distance'] as double;
      displayStats.add({
        'value': MeasurementUtils.formatDistance(distance, metric: preferMetric),
        'label': 'DISTANCE',
      });
    }

    // Total time
    if (statsData['total_duration'] != null) {
      final duration = Duration(seconds: (statsData['total_duration'] as num).round());
      displayStats.add({
        'value': _formatDuration(duration),
        'label': 'TIME',
      });
    }

    // Sessions count
    if (statsData['session_count'] != null) {
      displayStats.add({
        'value': statsData['session_count'].toString(),
        'label': 'SESSIONS',
      });
    }

    // Average pace
    if (statsData['avg_pace'] != null) {
      final paceSeconds = (statsData['avg_pace'] as num).toDouble();
      displayStats.add({
        'value': MeasurementUtils.formatPace(paceSeconds, metric: preferMetric),
        'label': 'AVG PACE',
      });
    }

    return displayStats.take(4).toList();
  }

  /// Extract stats based on time range
  Map<String, dynamic> _extractTimeRangeStats() {
    switch (timeRange) {
      case TimeRange.week:
        return stats['weekly_stats'] ?? {};
      case TimeRange.month:
        return stats['monthly_stats'] ?? {};
      case TimeRange.allTime:
        return stats['all_time_stats'] ?? {};
      case TimeRange.lastRuck:
        // Check if we have time_range data from backend (when time_range=last_ruck is specified)
        if (stats['time_range'] != null) {
          final timeRangeData = stats['time_range'] as Map<String, dynamic>;
          // Convert backend format to expected frontend format
          return {
            'total_distance': timeRangeData['total_distance_km'],
            'total_duration': timeRangeData['total_duration_seconds'],
            'total_calories': timeRangeData['total_calories'],
            'total_elevation_gain': timeRangeData['elevation_gain_m'],
            'session_count': timeRangeData['sessions_count'],
          };
        }
        // Fallback to recent_sessions format if available
        final recentSessions = stats['recent_sessions'] as List? ?? [];
        if (recentSessions.isNotEmpty) {
          return recentSessions[0] as Map<String, dynamic>;
        }
        return {};
    }
  }

  /// Format duration for display
  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }

  /// Get template-specific tagline
  String _getTagline() {
    switch (template) {
      case PostTemplate.beastMode:
        return 'Beast Mode Activated';
      case PostTemplate.journey:
        return 'Every Step Counts';
      case PostTemplate.community:
        return 'Stronger Together';
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
