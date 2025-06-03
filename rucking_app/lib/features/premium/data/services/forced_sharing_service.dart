import 'package:flutter/foundation.dart';
import 'package:rucking_app/features/premium/domain/services/premium_service.dart';
import 'package:rucking_app/features/ruck_tracking/domain/models/ruck_session.dart';

/// Service that handles forced sharing for free users
/// As per implementation plan: "All sessions are automatically shared publicly"
class ForcedSharingService {
  final PremiumService _premiumService;

  ForcedSharingService(this._premiumService);

  /// Automatically shares session publicly for all users
  /// Free users have NO control over this - it's forced
  Future<void> autoShareSession(RuckSession session) async {
    try {
      final isPremium = await _premiumService.isPremium();
      
      // Force sharing for free users (as per implementation plan)
      if (!isPremium) {
        await _createForcedPublicPost(session);
        await _trackEngagementMetrics(session.userId);
        
        debugPrint('🔒 FREE USER: Session automatically shared publicly (forced)');
      } else {
        // Premium users can choose, but default to public for content ecosystem
        await _createPublicPost(session);
        debugPrint('👑 PREMIUM USER: Session shared publicly');
      }
    } catch (e) {
      debugPrint('Error in auto-sharing session: $e');
    }
  }

  /// Forces a session to be public regardless of user preference
  /// This builds the content ecosystem for premium users to engage with
  Future<void> _createForcedPublicPost(RuckSession session) async {
    // Create public post for EVERY completed session
    // Free users create content that premium users can engage with
    // This builds a vibrant community ecosystem
    
    final publicPost = {
      'sessionId': session.id,
      'userId': session.userId,
      'distance': session.distance,
      'duration': session.duration.inMinutes,
      'weight': session.weight,
      'route': session.route?.map((point) => {
        'latitude': point.latitude,
        'longitude': point.longitude,
        'timestamp': point.timestamp.toIso8601String(),
      }).toList(),
      'isPublic': true, // FORCED for free users
      'canUserControl': false, // Free users cannot change this
      'shareType': 'forced_free_user',
      'createdAt': DateTime.now().toIso8601String(),
    };

    // Save to database with forced public visibility
    await _savePublicPost(publicPost);
    
    // Notify user that session was shared (they can't control it)
    await _notifyUserOfForcedShare(session);
  }

  /// Creates a normal public post for premium users
  Future<void> _createPublicPost(RuckSession session) async {
    final publicPost = {
      'sessionId': session.id,
      'userId': session.userId,
      'distance': session.distance,
      'duration': session.duration.inMinutes,
      'weight': session.weight,
      'route': session.route?.map((point) => {
        'latitude': point.latitude,
        'longitude': point.longitude,
        'timestamp': point.timestamp.toIso8601String(),
      }).toList(),
      'isPublic': true,
      'canUserControl': true, // Premium users have control
      'shareType': 'premium_user_choice',
      'createdAt': DateTime.now().toIso8601String(),
    };

    await _savePublicPost(publicPost);
  }

  /// Tracks engagement metrics for FOMO notifications
  Future<void> _trackEngagementMetrics(String userId) async {
    // Track metrics that will be used for teaser notifications
    final metrics = {
      'userId': userId,
      'totalSessions': await _getUserSessionCount(userId),
      'totalLikes': await _getUserLikeCount(userId),
      'totalComments': await _getUserCommentCount(userId),
      'lastEngagement': DateTime.now().toIso8601String(),
    };

    await _saveEngagementMetrics(metrics);
  }

  /// Shows user that their session was automatically shared
  /// Free users are informed but cannot change it
  Future<void> _notifyUserOfForcedShare(RuckSession session) async {
    final notification = {
      'type': 'forced_share_notification',
      'title': 'Session Shared!',
      'message': 'Your ruck is now live in the community! You\'ll get notified when people engage.',
      'sessionId': session.id,
      'canDismiss': true,
      'showUpgradeOption': true, // Hint about premium control
      'timestamp': DateTime.now().toIso8601String(),
    };

    await _showInAppNotification(notification);
  }

  /// Checks if user can control sharing (premium users only)
  Future<bool> canUserControlSharing() async {
    return await _premiumService.isPremium();
  }

  /// Gets the sharing status text for UI
  Future<String> getSharingStatusText() async {
    final isPremium = await _premiumService.isPremium();
    
    if (isPremium) {
      return 'Your sessions are shared publicly';
    } else {
      return 'All sessions are automatically shared publicly';
    }
  }

  /// Gets sharing control availability for UI
  Future<bool> isShareToggleVisible() async {
    // Only show toggle for premium users
    return await _premiumService.isPremium();
  }

  // Private helper methods for database operations
  Future<void> _savePublicPost(Map<String, dynamic> post) async {
    // TODO: Implement database save
    debugPrint('Saving public post: ${post['sessionId']}');
  }

  Future<void> _saveEngagementMetrics(Map<String, dynamic> metrics) async {
    // TODO: Implement metrics save
    debugPrint('Saving engagement metrics for user: ${metrics['userId']}');
  }

  Future<void> _showInAppNotification(Map<String, dynamic> notification) async {
    // TODO: Implement in-app notification
    debugPrint('Showing notification: ${notification['title']}');
  }

  Future<int> _getUserSessionCount(String userId) async {
    // TODO: Implement database query
    return 0;
  }

  Future<int> _getUserLikeCount(String userId) async {
    // TODO: Implement database query
    return 0;
  }

  Future<int> _getUserCommentCount(String userId) async {
    // TODO: Implement database query
    return 0;
  }
}

/// Extension to add forced sharing to session completion
extension ForcedSharingExtension on RuckSession {
  /// Automatically shares this session if user is on free tier
  Future<void> autoShare(ForcedSharingService sharingService) async {
    await sharingService.autoShareSession(this);
  }
}
