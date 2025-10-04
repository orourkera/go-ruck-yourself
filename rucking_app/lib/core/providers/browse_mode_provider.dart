import 'package:flutter/material.dart';

/// Provider to track if user is in browse-only mode (not authenticated)
class BrowseModeProvider extends InheritedWidget {
  final bool isBrowseMode;

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
    return of(context)?.isBrowseMode ?? false;
  }

  @override
  bool updateShouldNotify(BrowseModeProvider oldWidget) {
    return isBrowseMode != oldWidget.isBrowseMode;
  }
}
