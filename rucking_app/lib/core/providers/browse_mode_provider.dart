import 'package:flutter/material.dart';

/// Provider to track if user is in browse-only mode (not authenticated)
class BrowseModeProvider extends InheritedWidget {
  final bool isBrowseMode;
  static bool _globalIsBrowseMode = false;

  const BrowseModeProvider({
    Key? key,
    required this.isBrowseMode,
    required Widget child,
  }) : super(key: key, child: child);

  static BrowseModeProvider? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<BrowseModeProvider>();
  }

  /// Helper to check if in browse mode from any context
  static bool isBrowsing(BuildContext context) {
    return of(context)?.isBrowseMode ?? _globalIsBrowseMode;
  }

  /// Allows non-widget callers to toggle browse mode state.
  static void setBrowseMode(bool value) {
    _globalIsBrowseMode = value;
  }

  /// Returns the current global browse-mode state.
  static bool get isGlobalBrowseMode => _globalIsBrowseMode;

  @override
  bool updateShouldNotify(BrowseModeProvider oldWidget) {
    final shouldNotify = isBrowseMode != oldWidget.isBrowseMode;
    if (shouldNotify) {
      _globalIsBrowseMode = isBrowseMode;
    }
    return shouldNotify;
  }
}
