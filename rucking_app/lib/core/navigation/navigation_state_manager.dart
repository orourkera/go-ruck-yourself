import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:rucking_app/core/navigation/alltrails_router.dart';
import 'package:rucking_app/core/navigation/bottom_navigation_config.dart';
import 'package:rucking_app/core/navigation/deep_link_handler.dart';
import 'package:rucking_app/features/planned_rucks/presentation/bloc/planned_ruck_bloc.dart';
import 'package:rucking_app/core/services/analytics_service.dart';

/// Manages global navigation state and coordinates between different navigation systems
class NavigationStateManager extends ChangeNotifier {
  static final NavigationStateManager _instance =
      NavigationStateManager._internal();
  factory NavigationStateManager() => _instance;
  NavigationStateManager._internal();

  // Navigation state
  int _currentBottomTabIndex = 0;
  String _currentRoute = '/home';
  final List<String> _navigationHistory = [];
  bool _isNavigating = false;
  String? _pendingDeepLink;

  // Tab state persistence
  final Map<int, String> _tabRouteHistory = {};
  final Map<int, GlobalKey<NavigatorState>> _tabNavigatorKeys = {};

  // Getters
  int get currentBottomTabIndex => _currentBottomTabIndex;
  String get currentRoute => _currentRoute;
  List<String> get navigationHistory => List.unmodifiable(_navigationHistory);
  bool get isNavigating => _isNavigating;
  String? get pendingDeepLink => _pendingDeepLink;

  /// Initialize navigation system
  void initialize() {
    // Initialize tab navigator keys
    for (int i = 0; i < 4; i++) {
      _tabNavigatorKeys[i] = GlobalKey<NavigatorState>();
    }

    // Set up deep link handling
    DeepLinkHandler.initialize();

    // Load saved navigation state
    _loadNavigationState();
  }

  /// Handle bottom tab changes with proper state management
  void onBottomTabChanged(int index, BuildContext context) {
    if (index == _currentBottomTabIndex) {
      // If tapping the same tab, scroll to top or go to root
      _handleSameTabTap(index, context);
      return;
    }

    final previousIndex = _currentBottomTabIndex;

    // Save current tab's route
    _tabRouteHistory[previousIndex] = _currentRoute;

    // Update current tab
    _currentBottomTabIndex = index;

    // Restore or navigate to tab's route
    final savedRoute = _tabRouteHistory[index];
    if (savedRoute != null) {
      _navigateToRoute(savedRoute, context);
    } else {
      // Navigate to default route for this tab
      BottomNavigationConfig.navigateToTab(context, index);
    }

    // Analytics
    AnalyticsService.trackTabSwitch(previousIndex, index);

    // Save state
    _saveNavigationState();

    notifyListeners();
  }

  /// Handle route changes from GoRouter
  void onRouteChanged(String route, BuildContext context) {
    if (_isNavigating) return; // Prevent recursive calls

    _currentRoute = route;
    _navigationHistory.add(route);

    // Limit history size
    if (_navigationHistory.length > 50) {
      _navigationHistory.removeAt(0);
    }

    // Update bottom tab index based on route
    final newTabIndex = BottomNavigationConfig.getTabIndexForRoute(route);
    if (newTabIndex != _currentBottomTabIndex) {
      _currentBottomTabIndex = newTabIndex;
    }

    // Analytics
    AnalyticsService.trackNavigation(route);

    // Save state
    _saveNavigationState();

    notifyListeners();
  }

  /// Handle deep links with proper state coordination
  Future<void> handleDeepLink(String link, BuildContext context) async {
    _pendingDeepLink = link;
    notifyListeners();

    try {
      await DeepLinkHandler.handleDeepLink(context, link);
      _pendingDeepLink = null;
    } catch (e) {
      _pendingDeepLink = null;
      // Handle error
      debugPrint('Failed to handle deep link: $e');
    }

    notifyListeners();
  }

  /// Navigate with proper state management
  Future<void> navigateTo(
    String route,
    BuildContext context, {
    Object? extra,
    bool replace = false,
  }) async {
    if (_isNavigating) return;

    _isNavigating = true;
    notifyListeners();

    try {
      if (replace) {
        context.pushReplacement(route, extra: extra);
      } else {
        context.push(route, extra: extra);
      }
    } finally {
      _isNavigating = false;
      notifyListeners();
    }
  }

  /// Pop with proper state management
  bool pop(BuildContext context) {
    if (_navigationHistory.length > 1) {
      _navigationHistory.removeLast();
      final previousRoute = _navigationHistory.last;
      _currentRoute = previousRoute;

      context.pop();
      notifyListeners();
      return true;
    }

    return false;
  }

  /// Clear navigation history (for logout, etc.)
  void clearHistory() {
    _navigationHistory.clear();
    _tabRouteHistory.clear();
    _currentBottomTabIndex = 0;
    _currentRoute = '/home';

    notifyListeners();
  }

  /// Handle app state changes (foreground/background)
  void onAppStateChanged(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        _saveNavigationState();
        break;
      case AppLifecycleState.resumed:
        _loadNavigationState();
        break;
      default:
        break;
    }
  }

  /// Handle notification navigation
  void handleNotificationNavigation(
    BuildContext context,
    String notificationType,
    Map<String, dynamic> data,
  ) {
    BottomNavigationConfig.handleNotificationNavigation(
      context,
      notificationType,
      data,
    );
  }

  /// Check if we can navigate back
  bool canPop() {
    return _navigationHistory.length > 1;
  }

  /// Get the appropriate navigator key for the current tab
  GlobalKey<NavigatorState>? getCurrentTabNavigatorKey() {
    return _tabNavigatorKeys[_currentBottomTabIndex];
  }

  /// Handle same tab tap (scroll to top or go to root)
  void _handleSameTabTap(int index, BuildContext context) {
    final navigatorKey = _tabNavigatorKeys[index];
    final navigator = navigatorKey?.currentState;

    if (navigator != null && navigator.canPop()) {
      // Pop to root if there are screens on the stack
      navigator.popUntil((route) => route.isFirst);
    } else {
      // If already at root, trigger scroll to top or refresh
      _triggerTabRefresh(index, context);
    }
  }

  void _triggerTabRefresh(int index, BuildContext context) {
    switch (index) {
      case BottomNavigationConfig.myRucksIndex:
        // Trigger refresh of planned rucks
        try {
          final plannedRuckBloc = context.read<PlannedRuckBloc>();
          plannedRuckBloc.add(RefreshPlannedRucks());
        } catch (e) {
          // BLoC not available
        }
        break;
      default:
        // Handle other tabs as needed
        break;
    }
  }

  void _navigateToRoute(String route, BuildContext context) {
    _isNavigating = true;
    context.go(route);
    _isNavigating = false;
  }

  void _saveNavigationState() {
    // This would typically save to SharedPreferences or secure storage
    // Implementation depends on your preferences service
    BottomNavigationConfig.saveLastActiveTab(_currentBottomTabIndex);
  }

  void _loadNavigationState() {
    // This would typically load from SharedPreferences
    _currentBottomTabIndex = BottomNavigationConfig.getLastActiveTab();
  }
}

/// BLoC for managing navigation state
class NavigationBloc extends Cubit<NavigationState> {
  final NavigationStateManager _navigationManager;

  NavigationBloc(this._navigationManager) : super(NavigationInitial()) {
    _navigationManager.addListener(_onNavigationStateChanged);
  }

  void _onNavigationStateChanged() {
    emit(NavigationChanged(
      currentTab: _navigationManager.currentBottomTabIndex,
      currentRoute: _navigationManager.currentRoute,
      isNavigating: _navigationManager.isNavigating,
      canPop: _navigationManager.canPop(),
    ));
  }

  void changeTab(int index, BuildContext context) {
    _navigationManager.onBottomTabChanged(index, context);
  }

  void handleDeepLink(String link, BuildContext context) {
    _navigationManager.handleDeepLink(link, context);
  }

  void navigateTo(String route, BuildContext context, {Object? extra}) {
    _navigationManager.navigateTo(route, context, extra: extra);
  }

  bool pop(BuildContext context) {
    return _navigationManager.pop(context);
  }

  @override
  Future<void> close() {
    _navigationManager.removeListener(_onNavigationStateChanged);
    return super.close();
  }
}

/// Navigation states
abstract class NavigationState {}

class NavigationInitial extends NavigationState {}

class NavigationChanged extends NavigationState {
  final int currentTab;
  final String currentRoute;
  final bool isNavigating;
  final bool canPop;

  NavigationChanged({
    required this.currentTab,
    required this.currentRoute,
    required this.isNavigating,
    required this.canPop,
  });
}

/// Widget that provides navigation state management
class NavigationProvider extends StatefulWidget {
  final Widget child;

  const NavigationProvider({
    super.key,
    required this.child,
  });

  @override
  State<NavigationProvider> createState() => _NavigationProviderState();
}

class _NavigationProviderState extends State<NavigationProvider>
    with WidgetsBindingObserver {
  late NavigationStateManager _navigationManager;
  late NavigationBloc _navigationBloc;

  @override
  void initState() {
    super.initState();

    _navigationManager = NavigationStateManager();
    _navigationBloc = NavigationBloc(_navigationManager);

    _navigationManager.initialize();

    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _navigationBloc.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _navigationManager.onAppStateChanged(state);
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<NavigationStateManager>.value(
          value: _navigationManager,
        ),
        BlocProvider<NavigationBloc>.value(
          value: _navigationBloc,
        ),
      ],
      child: widget.child,
    );
  }
}

/// Helper extensions for easy navigation
extension NavigationExtensions on BuildContext {
  NavigationStateManager get navigationManager =>
      read<NavigationStateManager>();
  NavigationBloc get navigationBloc => read<NavigationBloc>();

  void switchTab(int index) {
    navigationBloc.changeTab(index, this);
  }

  void handleDeepLink(String link) {
    navigationBloc.handleDeepLink(link, this);
  }

  void navigateToRoute(String route, {Object? extra}) {
    navigationBloc.navigateTo(route, this, extra: extra);
  }

  bool popRoute() {
    return navigationBloc.pop(this);
  }
}

/// Custom route information parser for AllTrails routes
class AllTrailsRouteInformationParser extends RouteInformationParser<Object> {
  @override
  Future<Object> parseRouteInformation(
      RouteInformation routeInformation) async {
    final uri = routeInformation.uri;

    // Handle AllTrails specific routes
    if (uri.pathSegments.isNotEmpty && uri.pathSegments[0] == 'route') {
      return AllTrailsRouteMatch(
        routeId: uri.pathSegments.length > 1 ? uri.pathSegments[1] : null,
        queryParameters: uri.queryParameters,
      );
    }

    // Handle other routes
    return uri;
  }

  @override
  RouteInformation? restoreRouteInformation(Object configuration) {
    if (configuration is AllTrailsRouteMatch) {
      return RouteInformation(
        uri: Uri(
          path: '/route/${configuration.routeId}',
          queryParameters: configuration.queryParameters,
        ),
      );
    }

    if (configuration is Uri) {
      return RouteInformation(uri: configuration);
    }

    return null;
  }
}

/// Custom route match for AllTrails routes
class AllTrailsRouteMatch {
  final String? routeId;
  final Map<String, String> queryParameters;

  AllTrailsRouteMatch({
    this.routeId,
    this.queryParameters = const {},
  });
}

/// Multi-provider wrapper (placeholder - you'd use your actual provider)
class MultiProvider extends StatelessWidget {
  final List<dynamic> providers;
  final Widget child;

  const MultiProvider({
    super.key,
    required this.providers,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // This would be implemented with your actual provider package
    return child;
  }
}

class ChangeNotifierProvider<T extends ChangeNotifier> extends StatelessWidget {
  final T value;
  final Widget child;

  const ChangeNotifierProvider.value({
    super.key,
    required this.value,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // This would be implemented with your actual provider package
    return child;
  }
}
