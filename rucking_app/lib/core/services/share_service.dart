import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_session.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/shared/widgets/share/share_card_widget.dart';
import 'package:rucking_app/shared/widgets/share/share_preview_screen.dart';

/// Service for handling session sharing with visual share cards
class ShareService {
  static final ScreenshotController _screenshotController = ScreenshotController();

  /// Share a ruck session with a beautiful visual share card (enhanced version)
  static Future<void> shareSessionCard({
    required BuildContext context,
    required RuckSession session,
    required bool preferMetric,
    String? backgroundImageUrl,
    List<String> achievements = const [],
    bool isLadyMode = false,
    ShareBackgroundOption? backgroundOption,
  }) async {
    try {
      AppLogger.info('Starting session share with custom background for session ${session.id}');

      // Create the share card widget with background option
      final shareCard = ShareCardWidget(
        session: session,
        preferMetric: preferMetric,
        backgroundImageUrl: backgroundImageUrl,
        achievements: achievements,
        isLadyMode: isLadyMode,
        backgroundOption: backgroundOption,
      );

      // Capture screenshot of the share card
      final Uint8List? imageBytes = await _captureShareCard(shareCard);
      
      if (imageBytes == null) {
        throw Exception('Failed to capture share card image');
      }

      // Save image to temporary file
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'ruck_session_$timestamp.png';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(imageBytes);

      // Create share text
      final shareText = _createShareText(session, preferMetric);

      // Share the image with text
      await Share.shareXFiles(
        [XFile(file.path)],
        text: shareText,
        subject: 'Ruck - Session Completed!',
      );

      AppLogger.info('Session share with custom background completed successfully');

    } catch (e, stackTrace) {
      AppLogger.error('Failed to share session: $e', exception: e);
      
      // Fallback to text-only sharing
      await _shareTextOnly(session, preferMetric);
    }
  }

  /// Share a ruck session with a beautiful visual share card (legacy version)
  static Future<void> shareSession({
    required BuildContext context,
    required RuckSession session,
    required bool preferMetric,
    String? backgroundImageUrl,
    List<String> achievements = const [],
    bool isLadyMode = false,
  }) async {
    try {
      AppLogger.info('Starting session share for session ${session.id}');

      // Create the share card widget
      final shareCard = ShareCardWidget(
        session: session,
        preferMetric: preferMetric,
        backgroundImageUrl: backgroundImageUrl,
        achievements: achievements,
        isLadyMode: isLadyMode,
      );

      // Capture screenshot of the share card
      final Uint8List? imageBytes = await _captureShareCard(shareCard);
      
      if (imageBytes == null) {
        throw Exception('Failed to capture share card image');
      }

      // Save image to temporary file
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'ruck_session_$timestamp.png';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(imageBytes);

      // Create share text
      final shareText = _createShareText(session, preferMetric);

      // Share the image with text
      await Share.shareXFiles(
        [XFile(file.path)],
        text: shareText,
        subject: 'Ruck - Session Completed!',
      );

      AppLogger.info('Session share completed successfully');

    } catch (e, stackTrace) {
      AppLogger.error('Failed to share session: $e', exception: e);
      
      // Fallback to text-only sharing
      await _shareTextOnly(session, preferMetric);
    }
  }

  /// Capture a screenshot of the share card widget
  static Future<Uint8List?> _captureShareCard(Widget shareCard) async {
    try {
      return await _screenshotController.captureFromWidget(
        shareCard,
        pixelRatio: 3.0, // High quality image
        delay: const Duration(milliseconds: 100),
      );
    } catch (e) {
      AppLogger.error('Failed to capture share card: $e');
      return null;
    }
  }

  /// Create share text with session details
  static String _createShareText(RuckSession session, bool preferMetric) {
    final formattedDate = session.startTime.day.toString().padLeft(2, '0') + 
                         '/' + session.startTime.month.toString().padLeft(2, '0') + 
                         '/' + session.startTime.year.toString();
    
    return '''🏋️ Ruck - Session Completed!

📅 $formattedDate
🔄 ${session.formattedDuration}
📏 ${_formatDistance(session.distance, preferMetric)}
🔥 ${session.caloriesBurned} calories
⚖️ ${session.ruckWeightKg == 0.0 ? 'Hike' : _formatWeight(session.ruckWeightKg, preferMetric)}

Get the app and start your rucking journey!
#Ruck #Rucking #Fitness''';
  }

  /// Fallback text-only sharing
  static Future<void> _shareTextOnly(RuckSession session, bool preferMetric) async {
    try {
      final shareText = _createShareText(session, preferMetric);
      await Share.share(
        shareText,
        subject: 'Ruck - Session Completed!',
      );
      AppLogger.info('Fallback text-only share completed');
    } catch (e) {
      AppLogger.error('Failed to share text-only: $e');
    }
  }

  /// Format distance with proper units
  static String _formatDistance(double distanceKm, bool metric) {
    if (metric) {
      return '${distanceKm.toStringAsFixed(2)} km';
    } else {
      final miles = distanceKm * 0.621371;
      return '${miles.toStringAsFixed(2)} mi';
    }
  }

  /// Format weight with proper units
  static String _formatWeight(double weightKg, bool metric) {
    if (metric) {
      return '${weightKg.toStringAsFixed(1)} kg';
    } else {
      final pounds = weightKg * 2.20462;
      return '${pounds.toStringAsFixed(1)} lbs';
    }
  }

  /// Share session with custom background image
  static Future<void> shareSessionWithImage({
    required BuildContext context,
    required RuckSession session,
    required bool preferMetric,
    required String backgroundImageUrl,
    List<String> achievements = const [],
    bool isLadyMode = false,
  }) async {
    await shareSession(
      context: context,
      session: session,
      preferMetric: preferMetric,
      backgroundImageUrl: backgroundImageUrl,
      achievements: achievements,
      isLadyMode: isLadyMode,
    );
  }

  /// Quick share with default styling
  static Future<void> quickShare({
    required BuildContext context,
    required RuckSession session,
    required bool preferMetric,
    bool isLadyMode = false,
  }) async {
    await shareSession(
      context: context,
      session: session,
      preferMetric: preferMetric,
      isLadyMode: isLadyMode,
    );
  }
}
