import 'package:flutter/material.dart';

/// Global navigation service for accessing navigator context from anywhere
class NavigationService {
  static final NavigationService _instance = NavigationService._internal();
  factory NavigationService() => _instance;
  NavigationService._internal();

  static NavigationService get instance => _instance;

  GlobalKey<NavigatorState>? _navigatorKey;

  /// Set the navigator key (called from main app)
  void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  /// Get the current navigator key
  GlobalKey<NavigatorState>? get navigatorKey => _navigatorKey;

  /// Get the current navigator context
  BuildContext? get context => _navigatorKey?.currentContext;

  /// Get the current navigator state
  NavigatorState? get navigator => _navigatorKey?.currentState;

  /// Check if navigation is available
  bool get isNavigationReady => _navigatorKey?.currentState != null;

  /// Navigate to a named route
  Future<T?>? pushNamed<T extends Object?>(String routeName, {Object? arguments}) {
    if (!isNavigationReady) return null;
    return navigator?.pushNamed<T>(routeName, arguments: arguments);
  }

  /// Navigate to a named route and remove all previous routes
  Future<T?>? pushNamedAndRemoveUntil<T extends Object?>(
    String routeName, {
    Object? arguments,
    bool Function(Route<dynamic>)? predicate,
  }) {
    if (!isNavigationReady) return null;
    return navigator?.pushNamedAndRemoveUntil<T>(
      routeName,
      predicate ?? (route) => false,
      arguments: arguments,
    );
  }

  /// Pop the current route
  void pop<T extends Object?>([T? result]) {
    if (!isNavigationReady) return;
    navigator?.pop<T>(result);
  }

  /// Check if we can pop (i.e., there's a route to go back to)
  bool canPop() {
    if (!isNavigationReady) return false;
    return navigator?.canPop() ?? false;
  }
}
