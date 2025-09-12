import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rucking_app/core/navigation/alltrails_router.dart';
import 'package:rucking_app/core/navigation/bottom_navigation_config.dart';
import 'package:rucking_app/core/services/analytics_service.dart';
import 'package:rucking_app/core/services/sharing_service.dart';

/// Handles deep links, sharing, and universal links for AllTrails integration
class DeepLinkHandler {
  static const String appScheme = 'goruck';
  static const String appHost = 'rucking.app';

  /// Initialize deep link handling
  static void initialize() {
    // This would typically set up platform-specific deep link listeners
    _setupDeepLinkListeners();
  }

  /// Handle incoming deep links
  static Future<void> handleDeepLink(
    BuildContext context,
    String link,
  ) async {
    try {
      final uri = Uri.parse(link);

      // Track deep link analytics
      AnalyticsService.trackDeepLink(link);

      // Handle different types of links
      if (_isRouteShareLink(uri)) {
        await _handleRouteShareLink(context, uri);
      } else if (_isSessionLink(uri)) {
        await _handleSessionLink(context, uri);
      } else if (_isAllTrailsLink(uri)) {
        await _handleAllTrailsLink(context, uri);
      } else if (_isGPXLink(uri)) {
        await _handleGPXLink(context, uri);
      } else {
        await _handleGenericLink(context, uri);
      }

      // Provide haptic feedback
      HapticFeedback.lightImpact();
    } catch (e) {
      // Handle malformed links gracefully
      _showErrorDialog(context, 'Invalid link format');
    }
  }

  /// Generate shareable links for routes
  static String generateRouteShareLink(
    String routeId, {
    String? routeName,
    Map<String, dynamic>? metadata,
  }) {
    final params = <String, String>{
      'type': 'route',
      'id': routeId,
    };

    if (routeName != null) {
      params['name'] = routeName;
    }

    if (metadata != null) {
      // Add relevant metadata
      if (metadata['distance'] != null) {
        params['distance'] = metadata['distance'].toString();
      }
      if (metadata['difficulty'] != null) {
        params['difficulty'] = metadata['difficulty'].toString();
      }
    }

    return Uri(
      scheme: 'https',
      host: appHost,
      path: '/route/$routeId',
      queryParameters: params,
    ).toString();
  }

  /// Generate shareable links for planned rucks
  static String generatePlannedRuckShareLink(
    String ruckId, {
    String? ruckName,
    DateTime? plannedDate,
  }) {
    final params = <String, String>{
      'type': 'planned_ruck',
      'id': ruckId,
    };

    if (ruckName != null) {
      params['name'] = ruckName;
    }

    if (plannedDate != null) {
      params['date'] = plannedDate.toIso8601String();
    }

    return Uri(
      scheme: 'https',
      host: appHost,
      path: '/ruck/$ruckId',
      queryParameters: params,
    ).toString();
  }

  /// Generate session invite links
  static String generateSessionInviteLink(
    String sessionId, {
    String? sessionName,
    String? inviterName,
  }) {
    final params = <String, String>{
      'type': 'session_invite',
      'id': sessionId,
    };

    if (sessionName != null) {
      params['name'] = sessionName;
    }

    if (inviterName != null) {
      params['inviter'] = inviterName;
    }

    return Uri(
      scheme: 'https',
      host: appHost,
      path: '/session/$sessionId',
      queryParameters: params,
    ).toString();
  }

  /// Handle route sharing with rich previews
  static Future<void> shareRoute(
    String routeId, {
    String? routeName,
    String? description,
    Map<String, dynamic>? metadata,
  }) async {
    final link = generateRouteShareLink(routeId,
        routeName: routeName, metadata: metadata);

    final shareText = _buildRouteShareText(
      routeName: routeName,
      description: description,
      metadata: metadata,
      link: link,
    );

    await SharingService.shareWithPreview(
      text: shareText,
      link: link,
      previewData: _buildRoutePreviewData(routeName, metadata),
    );

    AnalyticsService.trackShare('route', routeId);
  }

  /// Handle planned ruck sharing
  static Future<void> sharePlannedRuck(
    String ruckId, {
    String? ruckName,
    DateTime? plannedDate,
    String? routeName,
  }) async {
    final link = generatePlannedRuckShareLink(
      ruckId,
      ruckName: ruckName,
      plannedDate: plannedDate,
    );

    final shareText = _buildPlannedRuckShareText(
      ruckName: ruckName,
      plannedDate: plannedDate,
      routeName: routeName,
      link: link,
    );

    await SharingService.shareWithPreview(
      text: shareText,
      link: link,
      previewData: _buildPlannedRuckPreviewData(ruckName, plannedDate),
    );

    AnalyticsService.trackShare('planned_ruck', ruckId);
  }

  /// Handle session invites
  static Future<void> inviteToSession(
    String sessionId, {
    String? sessionName,
    String? inviterName,
    List<String>? contactIds,
  }) async {
    final link = generateSessionInviteLink(
      sessionId,
      sessionName: sessionName,
      inviterName: inviterName,
    );

    final shareText = _buildSessionInviteText(
      sessionName: sessionName,
      inviterName: inviterName,
      link: link,
    );

    if (contactIds?.isNotEmpty == true) {
      // Send direct invites to specific contacts
      await SharingService.sendDirectInvites(
        contactIds: contactIds!,
        text: shareText,
        link: link,
      );
    } else {
      // Open general sharing interface
      await SharingService.shareWithPreview(
        text: shareText,
        link: link,
        previewData: _buildSessionInvitePreviewData(sessionName, inviterName),
      );
    }

    AnalyticsService.trackShare('session_invite', sessionId);
  }

  /// Private helper methods

  static void _setupDeepLinkListeners() {
    // This would set up platform-specific listeners
    // For now, this is a placeholder for the actual implementation
  }

  static bool _isRouteShareLink(Uri uri) {
    return uri.pathSegments.isNotEmpty &&
        uri.pathSegments[0] == 'route' &&
        uri.queryParameters['type'] == 'route';
  }

  static bool _isSessionLink(Uri uri) {
    return uri.pathSegments.isNotEmpty && uri.pathSegments[0] == 'session';
  }

  static bool _isAllTrailsLink(Uri uri) {
    return uri.host.contains('alltrails.com') ||
        uri.queryParameters['source'] == 'alltrails';
  }

  static bool _isGPXLink(Uri uri) {
    return uri.path.endsWith('.gpx') || uri.queryParameters['format'] == 'gpx';
  }

  static Future<void> _handleRouteShareLink(
      BuildContext context, Uri uri) async {
    final routeId = uri.pathSegments.isNotEmpty ? uri.pathSegments[1] : null;

    if (routeId != null) {
      // Show loading indicator
      _showLoadingDialog(context, 'Loading route...');

      try {
        // Navigate to route preview
        AllTrailsRouter.navigateToRoutePreview(context, routeId);

        // Hide loading dialog
        Navigator.of(context).pop();
      } catch (e) {
        Navigator.of(context).pop();
        _showErrorDialog(context, 'Failed to load route');
      }
    }
  }

  static Future<void> _handleSessionLink(BuildContext context, Uri uri) async {
    final sessionId = uri.pathSegments.isNotEmpty ? uri.pathSegments[1] : null;

    if (sessionId != null) {
      // Check if this is an invite or active session
      final isInvite = uri.queryParameters['type'] == 'session_invite';

      if (isInvite) {
        await _handleSessionInvite(context, sessionId, uri.queryParameters);
      } else {
        AllTrailsRouter.navigateToActiveSession(context, sessionId);
      }
    }
  }

  static Future<void> _handleAllTrailsLink(
      BuildContext context, Uri uri) async {
    // Extract AllTrails route information
    AllTrailsRouter.handleRouteShareLink(context, uri.toString());
  }

  static Future<void> _handleGPXLink(BuildContext context, Uri uri) async {
    // Handle GPX file import
    AllTrailsRouter.navigateToRouteImport(
      context,
      initialUrl: uri.toString(),
    );
  }

  static Future<void> _handleGenericLink(BuildContext context, Uri uri) async {
    // Try to extract useful information and navigate appropriately
    if (uri.queryParameters.containsKey('route')) {
      final routeData = uri.queryParameters['route'];
      AllTrailsRouter.navigateToRouteImport(context, initialUrl: routeData);
    } else {
      // Navigate to home and show info dialog
      BottomNavigationConfig.navigateToTab(
          context, BottomNavigationConfig.homeIndex);
      _showInfoDialog(context, 'Link opened successfully!');
    }
  }

  static Future<void> _handleSessionInvite(
    BuildContext context,
    String sessionId,
    Map<String, String> params,
  ) async {
    final sessionName = params['name'];
    final inviterName = params['inviter'];

    // Show invite acceptance dialog
    final accepted = await _showInviteDialog(
      context,
      sessionName: sessionName,
      inviterName: inviterName,
    );

    if (accepted) {
      // Join the session
      AllTrailsRouter.navigateToActiveSession(context, sessionId);
      AnalyticsService.trackEvent(
          'session_invite_accepted', {'session_id': sessionId});
    } else {
      AnalyticsService.trackEvent(
          'session_invite_declined', {'session_id': sessionId});
    }
  }

  static String _buildRouteShareText({
    String? routeName,
    String? description,
    Map<String, dynamic>? metadata,
    required String link,
  }) {
    final buffer = StringBuffer();

    if (routeName != null) {
      buffer.writeln('Check out this route: $routeName');
    } else {
      buffer.writeln('Check out this awesome route!');
    }

    if (metadata != null) {
      if (metadata['distance'] != null) {
        buffer.writeln('Distance: ${metadata['distance']} miles');
      }
      if (metadata['difficulty'] != null) {
        buffer.writeln('Difficulty: ${metadata['difficulty']}');
      }
    }

    if (description != null && description.isNotEmpty) {
      buffer.writeln('\n$description');
    }

    buffer.writeln('\nOpen with Go Ruck Yourself: $link');

    return buffer.toString();
  }

  static String _buildPlannedRuckShareText({
    String? ruckName,
    DateTime? plannedDate,
    String? routeName,
    required String link,
  }) {
    final buffer = StringBuffer();

    if (ruckName != null) {
      buffer.writeln('Join my planned ruck: $ruckName');
    } else {
      buffer.writeln('Join my planned ruck!');
    }

    if (routeName != null) {
      buffer.writeln('Route: $routeName');
    }

    if (plannedDate != null) {
      buffer.writeln('Date: ${_formatDate(plannedDate)}');
    }

    buffer.writeln('\nView details: $link');

    return buffer.toString();
  }

  static String _buildSessionInviteText({
    String? sessionName,
    String? inviterName,
    required String link,
  }) {
    final buffer = StringBuffer();

    if (inviterName != null) {
      buffer.writeln('$inviterName invited you to join a ruck session!');
    } else {
      buffer.writeln('You\'re invited to join a ruck session!');
    }

    if (sessionName != null) {
      buffer.writeln('Session: $sessionName');
    }

    buffer.writeln('\nJoin now: $link');

    return buffer.toString();
  }

  static Map<String, dynamic> _buildRoutePreviewData(
    String? routeName,
    Map<String, dynamic>? metadata,
  ) {
    return {
      'title': routeName ?? 'Ruck Route',
      'description': metadata != null
          ? 'Distance: ${metadata['distance']} miles'
          : 'Check out this ruck route!',
      'image': 'route_preview_image_url', // This would be actual route image
    };
  }

  static Map<String, dynamic> _buildPlannedRuckPreviewData(
    String? ruckName,
    DateTime? plannedDate,
  ) {
    return {
      'title': ruckName ?? 'Planned Ruck',
      'description': plannedDate != null
          ? 'Planned for ${_formatDate(plannedDate)}'
          : 'Join this planned ruck!',
      'image': 'planned_ruck_preview_image_url',
    };
  }

  static Map<String, dynamic> _buildSessionInvitePreviewData(
    String? sessionName,
    String? inviterName,
  ) {
    return {
      'title': sessionName ?? 'Ruck Session Invite',
      'description': inviterName != null
          ? 'Invitation from $inviterName'
          : 'You\'re invited to join!',
      'image': 'session_invite_preview_image_url',
    };
  }

  static String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year} at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  // UI Helper methods

  static void _showLoadingDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  static void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  static void _showInfoDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Info'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  static Future<bool> _showInviteDialog(
    BuildContext context, {
    String? sessionName,
    String? inviterName,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Session Invite'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (inviterName != null)
                  Text('$inviterName invited you to join:'),
                if (sessionName != null)
                  Text(
                    sessionName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                const SizedBox(height: 8),
                const Text('Would you like to join this ruck session?'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Decline'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Join'),
              ),
            ],
          ),
        ) ??
        false;
  }
}
