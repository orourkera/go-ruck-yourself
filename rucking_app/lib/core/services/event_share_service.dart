import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:rucking_app/features/events/domain/models/event.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

/// Service for sharing events with deeplinks and app store fallback
class EventShareService {
  
  /// Share an event with deeplink
  static Future<void> shareEvent(Event event) async {
    try {
      AppLogger.info('Sharing event ${event.id}: ${event.title}');
      
      // Create deeplink URL that fallsback to app stores
      final eventUrl = _createEventDeeplink(event.id);
      
      // Create share text with event details
      final shareText = _createEventShareText(event, eventUrl);
      
      // Share with iOS/Android native share sheet
      await Share.share(
        shareText,
        subject: 'Join me at ${event.title}!',
      );
      
      AppLogger.info('Event share completed successfully');
      
    } catch (e) {
      AppLogger.error('Failed to share event: $e', exception: e);
      
      // Fallback to text-only sharing without deeplink
      await _shareEventTextOnly(event);
    }
  }
  
  /// Create deeplink URL with app store fallback
  static String _createEventDeeplink(String eventId) {
    // This URL will:
    // 1. Open in app if installed (via Universal Links/App Links)
    // 2. Redirect to App Store/Play Store if app not installed
    return 'https://getrucky.com/events/$eventId';
  }
  
  /// Create compelling share text with event details
  static String _createEventShareText(Event event, String eventUrl) {
    final formattedDate = DateFormat('EEEE, MMM d').format(event.scheduledStartTime);
    final formattedTime = DateFormat('h:mm a').format(event.scheduledStartTime);
    
    String shareText = '''🎯 Join me at ${event.title}!

📅 $formattedDate at $formattedTime''';

    // Add location if available
    if (event.locationName.isNotEmpty) {
      shareText += '\n📍 ${event.locationName}';
    }
    
    // Add distance if available
    if (event.targetDistanceKm > 0) {
      shareText += '\n🏃‍♂️ ${event.targetDistanceKm.toStringAsFixed(1)} km';
    }
    
    // Add duration if available
    if (event.estimatedDurationMinutes > 0) {
      final hours = event.estimatedDurationMinutes ~/ 60;
      final minutes = event.estimatedDurationMinutes % 60;
      if (hours > 0) {
        shareText += '\n⏱️ ${hours}h ${minutes}m';
      } else {
        shareText += '\n⏱️ ${minutes}m';
      }
    }
    
    // Add participant info
    final spotsLeft = event.maxParticipants - event.currentParticipants;
    if (event.maxParticipants > 0) {
      shareText += '\n👥 $spotsLeft spots left (${event.currentParticipants}/${event.maxParticipants})';
    } else {
      shareText += '\n👥 ${event.currentParticipants} people joining';
    }
    
    shareText += '''

Join the event here:
$eventUrl

Get the Ruck app and start your rucking journey!
#Ruck #Rucking #Fitness''';
    
    return shareText;
  }
  
  /// Fallback text-only sharing without deeplink
  static Future<void> _shareEventTextOnly(Event event) async {
    try {
      final formattedDate = DateFormat('EEEE, MMM d').format(event.scheduledStartTime);
      final formattedTime = DateFormat('h:mm a').format(event.scheduledStartTime);
      
      String shareText = '''🎯 Join me at ${event.title}!

📅 $formattedDate at $formattedTime''';

      if (event.locationName.isNotEmpty) {
        shareText += '\n📍 ${event.locationName}';
      }
      
      shareText += '''

Download the Ruck app to join this event!
#Ruck #Rucking #Fitness''';
      
      await Share.share(
        shareText,
        subject: 'Join me at ${event.title}!',
      );
      
      AppLogger.info('Fallback text-only event share completed');
    } catch (e) {
      AppLogger.error('Failed to share event text-only: $e');
    }
  }
}
