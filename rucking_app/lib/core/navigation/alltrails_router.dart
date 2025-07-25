import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/core/models/planned_ruck.dart';
import 'package:rucking_app/core/models/route.dart';
import 'package:rucking_app/features/planned_rucks/presentation/screens/my_rucks_screen.dart';
import 'package:rucking_app/features/planned_rucks/presentation/screens/route_import_screen.dart';
import 'package:rucking_app/features/planned_rucks/presentation/screens/planned_ruck_detail_screen.dart';
import 'package:rucking_app/features/planned_rucks/presentation/screens/active_session_screen.dart';
import 'package:rucking_app/features/planned_rucks/presentation/bloc/planned_ruck_bloc.dart';
import 'package:rucking_app/features/planned_rucks/presentation/bloc/route_import_bloc.dart';
import 'package:rucking_app/core/di/injection_container.dart';

/// Navigation configuration for AllTrails integration routes
class AllTrailsRouter {
  static const String myRucks = '/my-rucks';
  static const String routeImport = '/route-import';
  static const String plannedRuckDetail = '/planned-ruck';
  static const String activeSession = '/active-session';
  static const String routePreview = '/route-preview';
  static const String routeSearch = '/route-search';

  /// Creates router configuration for AllTrails features
  static List<RouteBase> get routes => [
    // My Rucks Screen - Main hub for planned rucks
    GoRoute(
      path: myRucks,
      name: 'my-rucks',
      pageBuilder: (context, state) => CustomTransitionPage<void>(
        key: state.pageKey,
        child: BlocProvider(
          create: (context) => getIt<PlannedRuckBloc>()..add(LoadPlannedRucks()),
          child: const MyRucksScreen(),
        ),
        transitionsBuilder: _slideFromBottomTransition,
      ),
      routes: [
        // Route Import Screen
        GoRoute(
          path: '/import',
          name: 'route-import',
          pageBuilder: (context, state) => CustomTransitionPage<void>(
            key: state.pageKey,
            child: MultiBlocProvider(
              providers: [
                BlocProvider(
                  create: (context) => getIt<RouteImportBloc>(),
                ),
                BlocProvider.value(
                  value: context.read<PlannedRuckBloc>(),
                ),
              ],
              child: const RouteImportScreen(),
            ),
            transitionsBuilder: _slideFromRightTransition,
          ),
        ),
        
        // Planned Ruck Detail Screen
        GoRoute(
          path: '/detail/:ruckId',
          name: 'planned-ruck-detail',
          pageBuilder: (context, state) {
            final ruckId = state.pathParameters['ruckId']!;
            final extra = state.extra as PlannedRuck?;
            
            return CustomTransitionPage<void>(
              key: state.pageKey,
              child: BlocProvider.value(
                value: context.read<PlannedRuckBloc>(),
                child: PlannedRuckDetailScreen(
                  plannedRuck: extra ?? _getPlannedRuckById(context, ruckId),
                ),
              ),
              transitionsBuilder: _slideFromRightTransition,
            );
          },
        ),
        
        // Active Session Screen
        GoRoute(
          path: '/session/:sessionId',
          name: 'active-session',
          pageBuilder: (context, state) {
            final sessionId = state.pathParameters['sessionId']!;
            final extra = state.extra as Map<String, dynamic>?;
            
            return CustomTransitionPage<void>(
              key: state.pageKey,
              child: MultiBlocProvider(
                providers: [
                  BlocProvider.value(
                    value: context.read<PlannedRuckBloc>(),
                  ),
                  // Add session BLoC here when available
                ],
                child: ActiveSessionScreen(
                  sessionId: sessionId,
                  plannedRuck: extra?['plannedRuck'] as PlannedRuck?,
                ),
              ),
              transitionsBuilder: _fadeTransition,
            );
          },
        ),
      ],
    ),
    
    // Standalone Route Import (from deep link or sharing)
    GoRoute(
      path: routeImport,
      name: 'standalone-route-import',
      pageBuilder: (context, state) {
        final queryParams = state.uri.queryParameters;
        final routeUrl = queryParams['url'];
        final routeId = queryParams['routeId'];
        
        return CustomTransitionPage<void>(
          key: state.pageKey,
          child: MultiBlocProvider(
            providers: [
              BlocProvider(
                create: (context) => getIt<RouteImportBloc>()
                  ..add(_getInitialImportEvent(routeUrl, routeId)),
              ),
              BlocProvider(
                create: (context) => getIt<PlannedRuckBloc>(),
              ),
            ],
            child: const RouteImportScreen(),
          ),
          transitionsBuilder: _slideFromBottomTransition,
        );
      },
    ),
    
    // Route Preview (from sharing or deep link)
    GoRoute(
      path: '$routePreview/:routeId',
      name: 'route-preview',
      pageBuilder: (context, state) {
        final routeId = state.pathParameters['routeId']!;
        final route = state.extra as Route?;
        
        return CustomTransitionPage<void>(
          key: state.pageKey,
          child: MultiBlocProvider(
            providers: [
              BlocProvider(
                create: (context) => getIt<RouteImportBloc>()
                  ..add(PreviewRoute(routeId: routeId, route: route)),
              ),
              BlocProvider(
                create: (context) => getIt<PlannedRuckBloc>(),
              ),
            ],
            child: RoutePreviewScreen(
              routeId: routeId,
              route: route,
            ),
          ),
          transitionsBuilder: _scaleTransition,
        );
      },
    ),
    
    // Route Search (for browsing imported routes)
    GoRoute(
      path: routeSearch,
      name: 'route-search',
      pageBuilder: (context, state) {
        final queryParams = state.uri.queryParameters;
        final searchQuery = queryParams['q'] ?? '';
        final filters = _parseSearchFilters(queryParams);
        
        return CustomTransitionPage<void>(
          key: state.pageKey,
          child: MultiBlocProvider(
            providers: [
              BlocProvider(
                create: (context) => getIt<RouteImportBloc>()
                  ..add(SearchRoutes(
                    query: searchQuery,
                    filters: filters,
                  )),
              ),
              BlocProvider(
                create: (context) => getIt<PlannedRuckBloc>(),
              ),
            ],
            child: RouteSearchScreen(
              initialQuery: searchQuery,
              initialFilters: filters,
            ),
          ),
          transitionsBuilder: _slideFromRightTransition,
        );
      },
    ),
  ];

  /// Navigation helper methods
  static void navigateToMyRucks(BuildContext context) {
    context.go(myRucks);
  }

  static void navigateToRouteImport(BuildContext context, {
    String? initialUrl,
    String? routeId,
  }) {
    final params = <String, String>{};
    if (initialUrl != null) params['url'] = initialUrl;
    if (routeId != null) params['routeId'] = routeId;
    
    final uri = Uri(path: routeImport, queryParameters: params.isEmpty ? null : params);
    context.go(uri.toString());
  }

  static void navigateToPlannedRuckDetail(
    BuildContext context,
    PlannedRuck plannedRuck,
  ) {
    context.goNamed(
      'planned-ruck-detail',
      pathParameters: {'ruckId': plannedRuck.id!},
      extra: plannedRuck,
    );
  }

  static void navigateToActiveSession(
    BuildContext context,
    String sessionId, {
    PlannedRuck? plannedRuck,
  }) {
    context.goNamed(
      'active-session',
      pathParameters: {'sessionId': sessionId},
      extra: {
        'plannedRuck': plannedRuck,
      },
    );
  }

  static void navigateToRoutePreview(
    BuildContext context,
    String routeId, {
    Route? route,
  }) {
    context.goNamed(
      'route-preview',
      pathParameters: {'routeId': routeId},
      extra: route,
    );
  }

  static void navigateToRouteSearch(
    BuildContext context, {
    String? query,
    Map<String, dynamic>? filters,
  }) {
    final params = <String, String>{};
    if (query?.isNotEmpty == true) params['q'] = query!;
    if (filters != null) {
      params.addAll(_serializeSearchFilters(filters));
    }
    
    final uri = Uri(path: routeSearch, queryParameters: params.isEmpty ? null : params);
    context.go(uri.toString());
  }

  /// Deep link handlers
  static void handleRouteShareLink(BuildContext context, String url) {
    // Parse AllTrails URL or GPX URL
    if (url.contains('alltrails.com')) {
      final routeId = _extractAllTrailsRouteId(url);
      if (routeId != null) {
        navigateToRouteImport(context, routeId: routeId);
      }
    } else if (url.endsWith('.gpx')) {
      navigateToRouteImport(context, initialUrl: url);
    } else {
      // Generic route preview
      navigateToRouteImport(context, initialUrl: url);
    }
  }

  static void handlePlannedRuckShare(BuildContext context, String ruckId) {
    // This would typically fetch the ruck details first
    context.goNamed(
      'planned-ruck-detail',
      pathParameters: {'ruckId': ruckId},
    );
  }

  /// Custom transition builders
  static Widget _slideFromRightTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return SlideTransition(
      position: animation.drive(
        Tween(begin: const Offset(1.0, 0.0), end: Offset.zero)
            .chain(CurveTween(curve: Curves.easeInOut)),
      ),
      child: child,
    );
  }

  static Widget _slideFromBottomTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return SlideTransition(
      position: animation.drive(
        Tween(begin: const Offset(0.0, 1.0), end: Offset.zero)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
      ),
      child: child,
    );
  }

  static Widget _fadeTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: animation.drive(
        CurveTween(curve: Curves.easeIn),
      ),
      child: child,
    );
  }

  static Widget _scaleTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return ScaleTransition(
      scale: animation.drive(
        Tween(begin: 0.8, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutBack)),
      ),
      child: FadeTransition(
        opacity: animation,
        child: child,
      ),
    );
  }

  /// Helper methods
  static PlannedRuck _getPlannedRuckById(BuildContext context, String ruckId) {
    // This would typically get from BLoC state
    // For now, return a placeholder
    throw UnimplementedError('PlannedRuck lookup not implemented');
  }

  static RouteImportEvent _getInitialImportEvent(String? routeUrl, String? routeId) {
    if (routeId != null) {
      return ImportFromAllTrails(routeId: routeId);
    } else if (routeUrl != null) {
      return ImportFromUrl(url: routeUrl);
    }
    return const ResetImport();
  }

  static String? _extractAllTrailsRouteId(String url) {
    // Extract route ID from AllTrails URL
    // Example: https://www.alltrails.com/trail/us/california/mount-tamalpais-loop
    final uri = Uri.tryParse(url);
    if (uri?.host.contains('alltrails.com') == true) {
      final segments = uri!.pathSegments;
      if (segments.length >= 4 && segments[0] == 'trail') {
        return segments.last; // Return the trail name/ID
      }
    }
    return null;
  }

  static Map<String, dynamic> _parseSearchFilters(Map<String, String> queryParams) {
    final filters = <String, dynamic>{};
    
    // Parse difficulty filter
    if (queryParams.containsKey('difficulty')) {
      filters['difficulty'] = queryParams['difficulty'];
    }
    
    // Parse distance range
    if (queryParams.containsKey('minDistance')) {
      filters['minDistance'] = double.tryParse(queryParams['minDistance']!);
    }
    if (queryParams.containsKey('maxDistance')) {
      filters['maxDistance'] = double.tryParse(queryParams['maxDistance']!);
    }
    
    // Parse route type
    if (queryParams.containsKey('routeType')) {
      filters['routeType'] = queryParams['routeType'];
    }
    
    // Parse location
    if (queryParams.containsKey('location')) {
      filters['location'] = queryParams['location'];
    }
    
    return filters;
  }

  static Map<String, String> _serializeSearchFilters(Map<String, dynamic> filters) {
    final params = <String, String>{};
    
    filters.forEach((key, value) {
      if (value != null) {
        params[key] = value.toString();
      }
    });
    
    return params;
  }
}

/// Route Preview Screen for shared routes
class RoutePreviewScreen extends StatelessWidget {
  final String routeId;
  final Route? route;

  const RoutePreviewScreen({
    super.key,
    required this.routeId,
    this.route,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Route Preview'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            onPressed: () {
              // Navigate to import screen with this route
              AllTrailsRouter.navigateToRouteImport(
                context,
                routeId: routeId,
              );
            },
          ),
        ],
      ),
      body: BlocBuilder<RouteImportBloc, RouteImportState>(
        builder: (context, state) {
          if (state is RoutePreviewLoaded) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Route preview card would go here
                  // This would use RoutePreviewCard widget we created earlier
                  const Text('Route preview coming soon!'),
                  
                  const SizedBox(height: 20),
                  
                  // Import button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        AllTrailsRouter.navigateToRouteImport(
                          context,
                          routeId: routeId,
                        );
                      },
                      child: const Text('Import This Route'),
                    ),
                  ),
                ],
              ),
            );
          }
          
          return const Center(
            child: CircularProgressIndicator(),
          );
        },
      ),
    );
  }
}

/// Route Search Screen for browsing imported routes
class RouteSearchScreen extends StatelessWidget {
  final String initialQuery;
  final Map<String, dynamic> initialFilters;

  const RouteSearchScreen({
    super.key,
    required this.initialQuery,
    required this.initialFilters,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Routes'),
      ),
      body: BlocBuilder<RouteImportBloc, RouteImportState>(
        builder: (context, state) {
          // This would use the RouteSearchWidget we created
          return const Center(
            child: Text('Route search interface coming soon!'),
          );
        },
      ),
    );
  }
}

/// Active Session Screen for live tracking
class ActiveSessionScreen extends StatelessWidget {
  final String sessionId;
  final PlannedRuck? plannedRuck;

  const ActiveSessionScreen({
    super.key,
    required this.sessionId,
    this.plannedRuck,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // This would integrate all our active session widgets:
          // - ActiveSessionMapOverlay
          // - ETADisplayWidget  
          // - SessionProgressIndicator
          // - SessionControlsWidget
          // - SessionStatsOverlay
          
          const Center(
            child: Text('Active session interface will integrate all widgets here!'),
          ),
        ],
      ),
    );
  }
}
