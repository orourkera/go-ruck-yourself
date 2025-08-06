import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// 🌟 Smart In-App Review Service
/// 
/// Implements best practices for app reviews:
/// ✅ Two-step approach (satisfaction check first, then review)
/// ✅ Filters out negative feedback to support instead of App Store
/// ✅ Only prompts after meaningful achievements (1km+ ruck)
/// ✅ Respects Apple/Google guidelines (max 3 times per year)
/// ✅ Data-driven approach with analytics
class InAppReviewService {
  static const String _keyReviewRequestCount = 'review_request_count';
  static const String _keyLastReviewRequestDate = 'last_review_request_date';
  static const String _keyHasLeftReview = 'has_left_review';
  static const String _keyCompletedRucksCount = 'completed_rucks_count';
  
  // Constants
  static const int _maxReviewRequestsPerYear = 3;
  static const int _minDaysBetweenRequests = 90; // ~3 months
  static const double _qualifyingRuckDistanceKm = 1.0;
  
  final InAppReview _inAppReview = InAppReview.instance;
  
  /// Check if review prompt should be shown after completing a ruck
  Future<void> checkAndPromptAfterRuck({
    required double distanceKm,
    required BuildContext context,
  }) async {
    try {
      debugPrint('[InAppReview] 🔍 Checking review prompt for ${distanceKm}km ruck');
      
      // Only prompt for qualifying rucks (1km or more)
      if (distanceKm < _qualifyingRuckDistanceKm) {
        debugPrint('[InAppReview] ❌ Distance ${distanceKm}km too short, need >= ${_qualifyingRuckDistanceKm}km');
        return;
      }
      
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      
      // Increment completed rucks count
      final completedRucks = prefs.getInt(_keyCompletedRucksCount) ?? 0;
      await prefs.setInt(_keyCompletedRucksCount, completedRucks + 1);
      debugPrint('[InAppReview] 📊 Total completed rucks: ${completedRucks + 1}');
      
      // Check if user has already left a review
      final hasLeftReview = prefs.getBool(_keyHasLeftReview) ?? false;
      if (hasLeftReview) {
        debugPrint('[InAppReview] ✅ User has already left a review - skipping prompt');
        return;
      }
      
      // Check if we've reached request limit
      final requestCount = prefs.getInt(_keyReviewRequestCount) ?? 0;
      debugPrint('[InAppReview] 💯 Request count: $requestCount / $_maxReviewRequestsPerYear');
      if (requestCount >= _maxReviewRequestsPerYear) {
        debugPrint('[InAppReview] ⚠️ Max review requests reached for this year');
        return;
      }
      
      // Check timing constraints
      final lastRequestDate = prefs.getString(_keyLastReviewRequestDate);
      if (lastRequestDate != null) {
        final lastDate = DateTime.parse(lastRequestDate);
        final daysSinceLastRequest = DateTime.now().difference(lastDate).inDays;
        debugPrint('[InAppReview] 📅 Days since last request: $daysSinceLastRequest / $_minDaysBetweenRequests');
        if (daysSinceLastRequest < _minDaysBetweenRequests) {
          debugPrint('[InAppReview] ⏰ Too soon since last request - waiting');
          return;
        }
      } else {
        debugPrint('[InAppReview] 🎆 First time requesting review!');
      }
      
      // Smart timing: First qualifying ruck, or after multiple rucks for engaged users
      bool shouldPrompt = false;
      
      if (completedRucks + 1 == 1) {
        // First 1km+ ruck - perfect time to ask!
        shouldPrompt = true;
        debugPrint('[InAppReview] 🎆 First qualifying ruck - will prompt!');
      } else if (completedRucks + 1 == 5 && requestCount == 0) {
        // Engaged user, second chance
        shouldPrompt = true;
        debugPrint('[InAppReview] 🔥 5th ruck with no prior requests - will prompt!');
      } else if (completedRucks + 1 == 15 && requestCount == 1) {
        // Very engaged user, final chance  
        shouldPrompt = true;
        debugPrint('[InAppReview] ⭐ 15th ruck, final chance - will prompt!');
      } else {
        debugPrint('[InAppReview] 😴 Not the right time to prompt (ruck ${completedRucks + 1}, requests: $requestCount)');
      }
      
      if (shouldPrompt && context.mounted) {
        debugPrint('[InAppReview] 📱 Showing satisfaction dialog...');
        await _showSatisfactionDialog(context, prefs);
      } else if (!context.mounted) {
        debugPrint('[InAppReview] ⚠️ Context not mounted - skipping dialog');
      }
    } catch (e) {
      debugPrint('[InAppReview] Error checking review prompt: $e');
    }
  }
  
  /// Show two-step satisfaction dialog (best practice)
  /// 
  /// Step 1: "Are you enjoying Ruck!"
  /// - Happy → Go to App Store review
  /// - Unhappy → Send feedback to developer
  Future<void> _showSatisfactionDialog(
    BuildContext context, 
    SharedPreferences prefs,
  ) async {
    if (!context.mounted) return;
    
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            '🎒 How are you enjoying Ruck!?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Your feedback helps us make Ruck! even better for the rucking community.',
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 16),
              Text(
                'How would you rate your experience so far?',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          actions: <Widget>[
            // Negative/Neutral Response
            TextButton.icon(
              icon: const Icon(Icons.sentiment_dissatisfied, color: Colors.orange),
              label: const Text('Could be better'),
              onPressed: () {
                Navigator.of(context).pop();
                _handleNegativeFeedback(context, prefs);
              },
            ),
            
            // Positive Response
            TextButton.icon(
              icon: const Icon(Icons.sentiment_very_satisfied, color: Colors.green),
              label: const Text('I love it!'),
              onPressed: () {
                Navigator.of(context).pop();
                _handlePositiveFeedback(context, prefs);
              },
            ),
          ],
        );
      },
    );
  }
  
  /// Handle positive feedback - direct to App Store review
  Future<void> _handlePositiveFeedback(
    BuildContext context,
    SharedPreferences prefs,
  ) async {
    // Update tracking
    await _updateReviewRequestTracking(prefs);
    
    if (!context.mounted) return;
    
    // Show second dialog for app store review
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            '🌟 That\'s awesome!',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'Would you mind taking a moment to rate Ruck! on the App Store? It really helps other ruckers discover our app.',
            style: TextStyle(fontSize: 16),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Maybe later'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton.icon(
              icon: const Icon(Icons.star, color: Colors.amber),
              label: const Text('Sure, let\'s do it!'),
              onPressed: () async {
                Navigator.of(context).pop();
                await _requestAppStoreReview(prefs);
              },
            ),
          ],
        );
      },
    );
  }
  
  /// Handle negative feedback - direct to support/feedback
  Future<void> _handleNegativeFeedback(
    BuildContext context,
    SharedPreferences prefs,
  ) async {
    // Update tracking (still counts as a request)
    await _updateReviewRequestTracking(prefs);
    
    if (!context.mounted) return;
    
    // Show feedback dialog
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            '💡 Help us improve!',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'We\'d love to hear how we can make Ruck! better for you. Would you like to send us your feedback directly?',
            style: TextStyle(fontSize: 16),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('No thanks'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton.icon(
              icon: const Icon(Icons.feedback, color: Colors.blue),
              label: const Text('Send feedback'),
              onPressed: () {
                Navigator.of(context).pop();
                _openFeedbackChannel();
              },
            ),
          ],
        );
      },
    );
  }
  
  /// Request app store review using native APIs
  Future<void> _requestAppStoreReview(SharedPreferences prefs) async {
    try {
      final isAvailable = await _inAppReview.isAvailable();
      
      if (isAvailable) {
        // Mark as reviewed (they initiated the process)
        await prefs.setBool(_keyHasLeftReview, true);
        
        // Use native in-app review dialog
        await _inAppReview.requestReview();
        
        debugPrint('[InAppReview] Native review dialog shown');
      } else {
        // Fallback to opening app store page
        await _openAppStorePage();
      }
    } catch (e) {
      debugPrint('[InAppReview] Error requesting review: $e');
      // Fallback to app store
      await _openAppStorePage();
    }
  }
  
  /// Open app store page as fallback
  Future<void> _openAppStorePage() async {
    try {
      await _inAppReview.openStoreListing(
appStoreId: '6504239036', // Ruck! App Store ID
      );
    } catch (e) {
      debugPrint('[InAppReview] Error opening store listing: $e');
    }
  }
  
  /// Open feedback channel (email to developer)
  Future<void> _openFeedbackChannel() async {
    try {
      final Uri emailUri = Uri(
        scheme: 'mailto',
path: 'rory@getrucky.com', // Personal support email for Ruck!
        queryParameters: {
          'subject': 'Ruck! App Feedback',
          'body': 'Hi there,\\n\\nI have some feedback about the Ruck! app:\\n\\n[Please describe what could be improved]\\n\\nThanks!',
        },
      );
      
      if (await canLaunchUrl(emailUri)) {
        await launchUrl(emailUri);
      } else {
        debugPrint('[InAppReview] Cannot launch email client');
      }
    } catch (e) {
      debugPrint('[InAppReview] Error opening feedback channel: $e');
    }
  }
  
  /// Update request tracking
  Future<void> _updateReviewRequestTracking(SharedPreferences prefs) async {
    final currentCount = prefs.getInt(_keyReviewRequestCount) ?? 0;
    await prefs.setInt(_keyReviewRequestCount, currentCount + 1);
    await prefs.setString(_keyLastReviewRequestDate, DateTime.now().toIso8601String());
  }
  
  /// Force show review dialog for testing (debug only)
  Future<void> debugForceShowReviewDialog(BuildContext context) async {
    if (!kDebugMode) return;
    
    final prefs = await SharedPreferences.getInstance();
    await _showSatisfactionDialog(context, prefs);
  }
  
  /// Reset review tracking for testing (debug only)
  Future<void> debugResetReviewTracking() async {
    if (!kDebugMode) return;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyReviewRequestCount);
    await prefs.remove(_keyLastReviewRequestDate);
    await prefs.remove(_keyHasLeftReview);
    await prefs.remove(_keyCompletedRucksCount);
    
    debugPrint('[InAppReview] Reset review tracking');
  }
  
  /// Get review status for debug/analytics
  Future<Map<String, dynamic>> getReviewStatus() async {
    final prefs = await SharedPreferences.getInstance();
    
    return {
      'requestCount': prefs.getInt(_keyReviewRequestCount) ?? 0,
      'lastRequestDate': prefs.getString(_keyLastReviewRequestDate),
      'hasLeftReview': prefs.getBool(_keyHasLeftReview) ?? false,
      'completedRucksCount': prefs.getInt(_keyCompletedRucksCount) ?? 0,
    };
  }
}
