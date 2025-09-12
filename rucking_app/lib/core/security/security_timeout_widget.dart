import 'dart:async';
import 'package:flutter/material.dart';
import 'package:rucking_app/core/services/auth_service.dart';
import 'package:rucking_app/core/services/service_locator.dart';

/// A widget that logs the user out after a specified period of inactivity
/// Use this for wrapping screens that display sensitive information
class SecurityTimeoutWidget extends StatefulWidget {
  final Widget child;
  final Duration timeout;
  final VoidCallback? onTimeout;
  final bool enabled;

  /// Creates a security timeout widget
  /// [child] The child widget to display
  /// [timeout] The time of inactivity before logout (default: 5 minutes)
  /// [onTimeout] Optional callback to execute on timeout
  /// [enabled] Whether the timeout is enabled (default: true)
  const SecurityTimeoutWidget({
    Key? key,
    required this.child,
    this.timeout = const Duration(minutes: 5),
    this.onTimeout,
    this.enabled = true,
  }) : super(key: key);

  @override
  State<SecurityTimeoutWidget> createState() => _SecurityTimeoutWidgetState();
}

class _SecurityTimeoutWidgetState extends State<SecurityTimeoutWidget> {
  Timer? _inactivityTimer;
  final AuthService _authService = getIt<AuthService>();

  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      _startInactivityTimer();
    }
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    super.dispose();
  }

  void _startInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(widget.timeout, _handleInactivityTimeout);
  }

  void _handleInactivityTimeout() async {
    // Only log out if the widget is still enabled
    if (widget.enabled) {
      // Log the user out
      await _authService.logout();

      // Execute custom timeout callback if provided
      widget.onTimeout?.call();

      // Navigate to login screen
      if (mounted && context.mounted) {
        Navigator.of(context)
            .pushNamedAndRemoveUntil('/login', (route) => false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _startInactivityTimer,
      onPanDown: (_) => _startInactivityTimer(),
      onScaleStart: (_) => _startInactivityTimer(),
      child: widget.child,
    );
  }
}
