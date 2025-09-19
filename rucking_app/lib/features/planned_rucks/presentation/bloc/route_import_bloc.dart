import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:rucking_app/core/models/route.dart';
import 'package:rucking_app/core/models/route_elevation_point.dart';
import 'package:rucking_app/core/models/planned_ruck.dart';
import 'package:rucking_app/core/repositories/routes_repository.dart';
import 'package:rucking_app/core/repositories/planned_rucks_repository.dart';
import 'package:rucking_app/core/services/gpx_service.dart';
import 'package:rucking_app/core/services/auth_service_consolidated.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

// Events
abstract class RouteImportEvent extends Equatable {
  const RouteImportEvent();

  @override
  List<Object?> get props => [];
}

/// Event to start importing a GPX file
class ImportGpxFile extends RouteImportEvent {
  final File gpxFile;
  final bool createPlannedRuck;
  final DateTime? plannedDate;
  final String? notes;

  const ImportGpxFile({
    required this.gpxFile,
    this.createPlannedRuck = false,
    this.plannedDate,
    this.notes,
  });

  @override
  List<Object?> get props => [gpxFile, createPlannedRuck, plannedDate, notes];
}

/// Event to import from URL
class ImportGpxFromUrl extends RouteImportEvent {
  final String url;
  final bool createPlannedRuck;
  final DateTime? plannedDate;
  final String? notes;

  const ImportGpxFromUrl({
    required this.url,
    this.createPlannedRuck = false,
    this.plannedDate,
    this.notes,
  });

  @override
  List<Object?> get props => [url, createPlannedRuck, plannedDate, notes];
}

/// Event to validate a GPX file without importing
class ValidateGpxFile extends RouteImportEvent {
  final File gpxFile;

  const ValidateGpxFile({required this.gpxFile});

  @override
  List<Object?> get props => [gpxFile];
}

/// Event to search AllTrails routes
class SearchAllTrailsRoutes extends RouteImportEvent {
  final String query;
  final double? nearLatitude;
  final double? nearLongitude;
  final int? maxDistance;
  final RouteDifficulty? difficulty;
  final RouteType? routeType;

  const SearchAllTrailsRoutes({
    required this.query,
    this.nearLatitude,
    this.nearLongitude,
    this.maxDistance,
    this.difficulty,
    this.routeType,
  });

  @override
  List<Object?> get props => [
        query,
        nearLatitude,
        nearLongitude,
        maxDistance,
        difficulty,
        routeType,
      ];
}

/// Event to import a route from AllTrails by ID
class ImportAllTrailsRoute extends RouteImportEvent {
  final String routeId;
  final bool createPlannedRuck;
  final DateTime? plannedDate;
  final String? notes;

  const ImportAllTrailsRoute({
    required this.routeId,
    this.createPlannedRuck = false,
    this.plannedDate,
    this.notes,
  });

  @override
  List<Object?> get props => [routeId, createPlannedRuck, plannedDate, notes];
}

/// Event to preview a route before importing
class PreviewRoute extends RouteImportEvent {
  final Route route;

  const PreviewRoute({required this.route});

  @override
  List<Object?> get props => [route];
}

/// Event to confirm import after preview
class ConfirmImport extends RouteImportEvent {
  final Route route;
  final bool createPlannedRuck;
  final DateTime? plannedDate;
  final String? notes;

  const ConfirmImport({
    required this.route,
    this.createPlannedRuck = false,
    this.plannedDate,
    this.notes,
  });

  @override
  List<Object?> get props => [route, createPlannedRuck, plannedDate, notes];
}

/// Event to cancel import
class CancelImport extends RouteImportEvent {
  const CancelImport();
}

/// Event to clear import state
class ClearImportState extends RouteImportEvent {
  const ClearImportState();
}

// States
abstract class RouteImportState extends Equatable {
  const RouteImportState();

  @override
  List<Object?> get props => [];
}

/// Initial state
class RouteImportInitial extends RouteImportState {
  const RouteImportInitial();
}

/// State when validating GPX file
class RouteImportValidating extends RouteImportState {
  final String fileName;

  const RouteImportValidating({required this.fileName});

  @override
  List<Object?> get props => [fileName];
}

/// State when GPX validation is complete
class RouteImportValidated extends RouteImportState {
  final Route route;
  final List<String> warnings;
  final String fileName;

  const RouteImportValidated({
    required this.route,
    this.warnings = const [],
    required this.fileName,
  });

  @override
  List<Object?> get props => [route, warnings, fileName];
}

/// State when importing route
class RouteImportInProgress extends RouteImportState {
  final String message;
  final double? progress;

  const RouteImportInProgress({
    required this.message,
    this.progress,
  });

  @override
  List<Object?> get props => [message, progress];
}

/// State when route import is successful
class RouteImportSuccess extends RouteImportState {
  final Route importedRoute;
  final PlannedRuck? plannedRuck;
  final String message;

  const RouteImportSuccess({
    required this.importedRoute,
    this.plannedRuck,
    required this.message,
  });

  @override
  List<Object?> get props => [importedRoute, plannedRuck, message];
}

/// State when route import fails
class RouteImportError extends RouteImportState {
  final String message;
  final String? errorCode;
  final bool canRetry;

  const RouteImportError({
    required this.message,
    this.errorCode,
    this.canRetry = true,
  });

  @override
  List<Object?> get props => [message, errorCode, canRetry];

  /// Create a validation error
  factory RouteImportError.validation({required String message}) {
    return RouteImportError(
      message: message,
      errorCode: 'VALIDATION_ERROR',
      canRetry: false,
    );
  }

  /// Create a network error
  factory RouteImportError.network({String? message}) {
    return RouteImportError(
      message: message ?? 'Network connection failed',
      errorCode: 'NETWORK_ERROR',
      canRetry: true,
    );
  }

  /// Create a file error
  factory RouteImportError.file({required String message}) {
    return RouteImportError(
      message: message,
      errorCode: 'FILE_ERROR',
      canRetry: false,
    );
  }

  /// Create a server error
  factory RouteImportError.server({String? message, int? statusCode}) {
    return RouteImportError(
      message: message ?? 'Server error occurred',
      errorCode: 'SERVER_ERROR_$statusCode',
      canRetry: statusCode != 400,
    );
  }
}

/// State when searching AllTrails routes
class RouteImportSearching extends RouteImportState {
  final String query;

  const RouteImportSearching({required this.query});

  @override
  List<Object?> get props => [query];
}

/// State when AllTrails search results are available
class RouteImportSearchResults extends RouteImportState {
  final List<Route> routes;
  final String query;
  final bool hasMore;

  const RouteImportSearchResults({
    required this.routes,
    required this.query,
    this.hasMore = false,
  });

  @override
  List<Object?> get props => [routes, query, hasMore];
}

/// State when previewing a route
class RouteImportPreview extends RouteImportState {
  final Route route;
  final List<String> warnings;
  final String source; // 'file', 'url', 'alltrails'

  const RouteImportPreview({
    required this.route,
    this.warnings = const [],
    required this.source,
  });

  @override
  List<Object?> get props => [route, warnings, source];
}

// BLoC
class RouteImportBloc extends Bloc<RouteImportEvent, RouteImportState> {
  final RoutesRepository _routesRepository;
  final PlannedRucksRepository _plannedRucksRepository;
  final GpxService _gpxService;
  final AuthService _authService;

  File? _currentGpxFile; // Store GPX file for import

  RouteImportBloc({
    required RoutesRepository routesRepository,
    required PlannedRucksRepository plannedRucksRepository,
    required GpxService gpxService,
    required AuthService authService,
  })  : _routesRepository = routesRepository,
        _plannedRucksRepository = plannedRucksRepository,
        _gpxService = gpxService,
        _authService = authService,
        super(const RouteImportInitial()) {
    on<ImportGpxFile>(_onImportGpxFile);
    on<ImportGpxFromUrl>(_onImportGpxFromUrl);
    on<ValidateGpxFile>(_onValidateGpxFile);
    on<SearchAllTrailsRoutes>(_onSearchAllTrailsRoutes);
    on<ImportAllTrailsRoute>(_onImportAllTrailsRoute);
    on<PreviewRoute>(_onPreviewRoute);
    on<ConfirmImport>(_onConfirmImport);
    on<CancelImport>(_onCancelImport);
    on<ClearImportState>(_onClearImportState);
  }

  /// Import GPX file
  Future<void> _onImportGpxFile(
    ImportGpxFile event,
    Emitter<RouteImportState> emit,
  ) async {
    try {
      emit(RouteImportValidating(fileName: event.gpxFile.path.split('/').last));

      // First validate the file
      final validationResult = await _gpxService.validateGpxFile(event.gpxFile);

      if (!validationResult.isValid) {
        emit(RouteImportError.validation(
          message: validationResult.errors.isNotEmpty
              ? validationResult.errors.first
              : 'Invalid GPX file',
        ));
        return;
      }

      // Parse the route from GPX
      final gpxContent = await event.gpxFile.readAsString();
      final parsedData = await _gpxService.parseGpxContent(gpxContent);

      if (parsedData.trackPoints.isEmpty) {
        emit(RouteImportError.validation(
          message: 'Could not parse route from GPX file',
        ));
        return;
      }

      // Convert parsed data to Route object
      final route = Route(
        name: parsedData.name,
        description: parsedData.description,
        source: parsedData.source,
        externalUrl: parsedData.externalUrl,
        routePolyline: _encodePolyline(parsedData.trackPoints),
        startLatitude: parsedData.trackPoints.first.latitude,
        startLongitude: parsedData.trackPoints.first.longitude,
        endLatitude: parsedData.trackPoints.last.latitude,
        endLongitude: parsedData.trackPoints.last.longitude,
        distanceKm: parsedData.totalDistanceKm,
        elevationGainM: parsedData.elevationGainM,
        elevationLossM: parsedData.elevationLossM,
        trailDifficulty: _calculateDifficulty(
            parsedData.totalDistanceKm, parsedData.elevationGainM),
        elevationPoints: _createElevationPoints(
            parsedData.trackPoints, parsedData.totalDistanceKm),
      );

      // Show preview
      emit(RouteImportPreview(
        route: route,
        warnings: validationResult.warnings,
        source: 'file',
      ));

      AppLogger.info('GPX file validated successfully: ${event.gpxFile.path}');
    } catch (e) {
      AppLogger.error('Error importing GPX file: $e');
      emit(RouteImportError.file(message: 'Failed to read GPX file: $e'));
    }
  }

  /// Import GPX from URL
  Future<void> _onImportGpxFromUrl(
    ImportGpxFromUrl event,
    Emitter<RouteImportState> emit,
  ) async {
    try {
      emit(const RouteImportInProgress(message: 'Downloading GPX file...'));

      // Download GPX content from URL
      final response = await http.get(Uri.parse(event.url));
      if (response.statusCode != 200) {
        emit(RouteImportError.network());
        return;
      }

      // Parse GPX content
      final parsedData = await _gpxService.parseGpxContent(response.body);

      if (parsedData.trackPoints.isEmpty) {
        emit(RouteImportError.validation(
          message: 'Could not parse route from URL',
        ));
        return;
      }

      // Convert to Route object
      final route = Route(
        name: parsedData.name,
        description: parsedData.description,
        source: parsedData.source,
        externalUrl: event.url,
        routePolyline: _encodePolyline(parsedData.trackPoints),
        startLatitude: parsedData.trackPoints.first.latitude,
        startLongitude: parsedData.trackPoints.first.longitude,
        endLatitude: parsedData.trackPoints.last.latitude,
        endLongitude: parsedData.trackPoints.last.longitude,
        distanceKm: parsedData.totalDistanceKm,
        elevationGainM: parsedData.elevationGainM,
        elevationLossM: parsedData.elevationLossM,
        trailDifficulty: _calculateDifficulty(
            parsedData.totalDistanceKm, parsedData.elevationGainM),
        elevationPoints: _createElevationPoints(
            parsedData.trackPoints, parsedData.totalDistanceKm),
      );

      // Show preview
      emit(RouteImportPreview(
        route: route,
        source: 'url',
      ));

      AppLogger.info('GPX imported from URL successfully: ${event.url}');
    } catch (e) {
      AppLogger.error('Error importing GPX from URL: $e');
      if (e.toString().contains('network') ||
          e.toString().contains('connection')) {
        emit(RouteImportError.network());
      } else {
        emit(RouteImportError(message: 'Failed to import from URL: $e'));
      }
    }
  }

  /// Validate GPX file without importing
  Future<void> _onValidateGpxFile(
    ValidateGpxFile event,
    Emitter<RouteImportState> emit,
  ) async {
    try {
      emit(RouteImportValidating(fileName: event.gpxFile.path.split('/').last));

      final validationResult = await _gpxService.validateGpxFile(event.gpxFile);

      if (!validationResult.isValid) {
        emit(RouteImportError.validation(
          message: validationResult.errors.isNotEmpty
              ? validationResult.errors.first
              : 'Invalid GPX file',
        ));
        return;
      }

      // Parse the route for preview only - don't import yet
      final gpxContent = await event.gpxFile.readAsString();
      final parsedData = await _gpxService.parseGpxContent(gpxContent);

      if (parsedData.trackPoints.isNotEmpty) {
        // Convert parsed data to Route object for preview
        final route = Route(
          name: parsedData.name,
          description: parsedData.description,
          source: 'gpx_import',
          externalUrl: parsedData.externalUrl,
          routePolyline: _encodePolyline(
              parsedData.trackPoints), // Use the same polyline encoding
          startLatitude: parsedData.trackPoints.first.latitude,
          startLongitude: parsedData.trackPoints.first.longitude,
          endLatitude: parsedData.trackPoints.last.latitude,
          endLongitude: parsedData.trackPoints.last.longitude,
          distanceKm: parsedData.totalDistanceKm,
          elevationGainM: parsedData.elevationGainM,
          elevationLossM: parsedData.elevationLossM,
          trailDifficulty: _calculateDifficulty(
              parsedData.totalDistanceKm, parsedData.elevationGainM),
          elevationPoints: _createElevationPoints(
              parsedData.trackPoints, parsedData.totalDistanceKm),
        );

        // Store the GPX file path for later import
        _currentGpxFile = event.gpxFile;

        emit(RouteImportValidated(
          route: route,
          warnings: validationResult.warnings,
          fileName: event.gpxFile.path.split('/').last,
        ));
      } else {
        emit(RouteImportError.validation(
          message: 'Could not parse route from GPX file',
        ));
      }

      AppLogger.info('GPX file validated: ${event.gpxFile.path}');
    } catch (e) {
      AppLogger.error('Error validating GPX file: $e');
      emit(RouteImportError.file(message: 'Failed to validate GPX file: $e'));
    }
  }

  /// Search AllTrails routes
  Future<void> _onSearchAllTrailsRoutes(
    SearchAllTrailsRoutes event,
    Emitter<RouteImportState> emit,
  ) async {
    try {
      emit(RouteImportSearching(query: event.query));

      final routes = await _routesRepository.getRoutes(
        search: event.query,
        nearLatitude: event.nearLatitude,
        nearLongitude: event.nearLongitude,
        maxDistance: event.maxDistance?.toDouble(),
        difficulty: event.difficulty?.name,
        limit: 20,
      );

      emit(RouteImportSearchResults(
        routes: routes,
        query: event.query,
        hasMore: routes.length >= 20,
      ));

      AppLogger.info('Found ${routes.length} routes for query: ${event.query}');
    } catch (e) {
      AppLogger.error('Error searching AllTrails routes: $e');
      if (e.toString().contains('network') ||
          e.toString().contains('connection')) {
        emit(RouteImportError.network());
      } else {
        emit(RouteImportError(message: 'Failed to search routes: $e'));
      }
    }
  }

  /// Import AllTrails route
  Future<void> _onImportAllTrailsRoute(
    ImportAllTrailsRoute event,
    Emitter<RouteImportState> emit,
  ) async {
    try {
      emit(const RouteImportInProgress(message: 'Loading route details...'));

      final route = await _routesRepository.getRoute(
        event.routeId,
        includeElevation: true,
        includePois: true,
      );

      if (route == null) {
        emit(RouteImportError.validation(
          message: 'Route not found',
        ));
        return;
      }

      // Show preview
      emit(RouteImportPreview(
        route: route,
        source: 'alltrails',
      ));

      AppLogger.info('AllTrails route loaded: ${event.routeId}');
    } catch (e) {
      AppLogger.error('Error importing AllTrails route: $e');
      if (e.toString().contains('network') ||
          e.toString().contains('connection')) {
        emit(RouteImportError.network());
      } else {
        emit(RouteImportError(message: 'Failed to import route: $e'));
      }
    }
  }

  /// Preview route
  void _onPreviewRoute(
    PreviewRoute event,
    Emitter<RouteImportState> emit,
  ) {
    emit(RouteImportPreview(
      route: event.route,
      source: 'preview',
    ));
  }

  /// Confirm import after preview
  Future<void> _onConfirmImport(
    ConfirmImport event,
    Emitter<RouteImportState> emit,
  ) async {
    print('🔥 _onConfirmImport CALLED!');
    try {
      emit(const RouteImportInProgress(
        message: 'Importing route...',
        progress: 0.0,
      ));

      // Import the route
      Route importedRoute;

      print(
          '🔍 ConfirmImport: route.id=${event.route.id}, route.source=${event.route.source}, routePolyline.length=${event.route.routePolyline.length}');
      print('🔍 ConfirmImport: _currentGpxFile=${_currentGpxFile?.path}');

      if (event.route.id != null) {
        // Route already exists in backend, just reference it
        print('🔍 BRANCH 1: Using existing route with ID: ${event.route.id}');
        importedRoute = event.route;
      } else if (event.route.source == 'gpx_import' &&
          _currentGpxFile != null) {
        // This is a GPX import - import with the updated route data (including custom name)
        print(
            '🔍 BRANCH 2: Importing GPX file with custom name: ${event.route.name}');
        emit(const RouteImportInProgress(
          message: 'Importing GPX route...',
          progress: 0.3,
        ));

        importedRoute = await _gpxService.importGpxFileWithCustomData(
            _currentGpxFile!, event.route);
        print('🔍 GPX imported successfully with ID: ${importedRoute.id}');
      } else {
        // Create new route using the routes repository
        print('🔍 BRANCH 3: Creating new route via routes repository');
        emit(const RouteImportInProgress(
          message: 'Creating route...',
          progress: 0.3,
        ));

        importedRoute = await _routesRepository.createRoute(event.route);
        print('🔍 Route created successfully with ID: ${importedRoute.id}');
      }

      PlannedRuck? plannedRuck;

      // Create planned ruck if requested
      if (event.createPlannedRuck) {
        emit(const RouteImportInProgress(
          message: 'Creating planned ruck...',
          progress: 0.7,
        ));

        final currentUser = await _authService.getCurrentUser();
        if (currentUser == null) {
          emit(RouteImportError.validation(
            message: 'User not authenticated',
          ));
          return;
        }

        plannedRuck = await _plannedRucksRepository.createPlannedRuck(
          PlannedRuck(
            userId: currentUser.userId,
            routeId: importedRoute.id!,
            route: importedRoute,
            plannedDate: event.plannedDate ??
                DateTime.now().add(const Duration(days: 1)),
            status: PlannedRuckStatus.planned,
            notes: event.notes,
            createdAt: DateTime.now(),
          ),
        );
      }

      emit(const RouteImportInProgress(
        message: 'Finalizing...',
        progress: 1.0,
      ));

      emit(RouteImportSuccess(
        importedRoute: importedRoute,
        plannedRuck: plannedRuck,
        message: plannedRuck != null
            ? 'Route imported and planned ruck created'
            : 'Route imported successfully',
      ));

      AppLogger.info('Route import completed: ${importedRoute.id}');
    } catch (e) {
      AppLogger.error('Error confirming route import: $e');
      if (e.toString().contains('network') ||
          e.toString().contains('connection')) {
        emit(RouteImportError.network());
      } else {
        emit(RouteImportError(message: 'Failed to import route: $e'));
      }
    }
  }

  /// Cancel import
  void _onCancelImport(
    CancelImport event,
    Emitter<RouteImportState> emit,
  ) {
    emit(const RouteImportInitial());
  }

  /// Clear import state
  void _onClearImportState(
    ClearImportState event,
    Emitter<RouteImportState> emit,
  ) {
    emit(const RouteImportInitial());
  }

  @override
  Future<void> close() {
    _routesRepository.dispose();
    _plannedRucksRepository.dispose();
    return super.close();
  }

  /// Encode track points as a simple coordinate string polyline
  String _encodePolyline(List<GpxTrackPoint> trackPoints) {
    if (trackPoints.isEmpty) return '';

    // Create a simple coordinate string format: "lat1,lng1;lat2,lng2;..."
    return trackPoints
        .map((point) =>
            '${point.latitude.toStringAsFixed(6)},${point.longitude.toStringAsFixed(6)}')
        .join(';');
  }

  /// Calculate trail difficulty based on distance and elevation gain
  String _calculateDifficulty(double distanceKm, double? elevationGainM) {
    final elevation = elevationGainM ?? 0.0;

    // Filter out obviously bad elevation data (negative values or extremely high values)
    // Reasonable elevation gain should be between 0 and 3000m for most routes
    final cleanElevation =
        (elevation < 0 || elevation > 3000) ? 0.0 : elevation;

    // Calculate difficulty based on distance and elevation gain per km
    final elevationPerKm = distanceKm > 0 ? cleanElevation / distanceKm : 0.0;

    // More reasonable difficulty thresholds
    if (distanceKm < 2.0 && cleanElevation < 50) {
      return 'easy';
    } else if (distanceKm < 5.0 && elevationPerKm < 50) {
      return 'easy';
    } else if (distanceKm < 10.0 && elevationPerKm < 100) {
      return 'moderate';
    } else if (elevationPerKm < 150 ||
        (distanceKm > 15 && elevationPerKm < 200)) {
      return 'hard';
    } else {
      return 'extreme';
    }
  }

  /// Create elevation points from track points and total distance
  List<RouteElevationPoint> _createElevationPoints(
      List<GpxTrackPoint> trackPoints, double totalDistanceKm) {
    if (trackPoints.isEmpty) return [];

    final List<RouteElevationPoint> elevationPoints = [];
    double currentDistance = 0.0;

    for (int i = 0; i < trackPoints.length - 1; i++) {
      final point1 = trackPoints[i];
      final point2 = trackPoints[i + 1];

      final distanceBetweenPoints = _haversineDistance(
          point1.latitude, point1.longitude, point2.latitude, point2.longitude);
      currentDistance += distanceBetweenPoints;

      // Skip points with invalid elevation data
      if (point1.elevation == null ||
          point1.elevation! < -500 ||
          point1.elevation! > 9000) {
        continue;
      }

      elevationPoints.add(RouteElevationPoint(
        routeId: 'temp-route-id', // Temporary ID for preview
        distanceKm: currentDistance,
        elevationM: point1.elevation!,
        latitude: point1.latitude,
        longitude: point1.longitude,
      ));
    }

    // Add the last point if it has valid elevation
    final lastPoint = trackPoints.last;
    if (lastPoint.elevation != null &&
        lastPoint.elevation! >= -500 &&
        lastPoint.elevation! <= 9000) {
      elevationPoints.add(RouteElevationPoint(
        routeId: 'temp-route-id', // Temporary ID for preview
        distanceKm: totalDistanceKm,
        elevationM: lastPoint.elevation!,
        latitude: lastPoint.latitude,
        longitude: lastPoint.longitude,
      ));
    }

    return elevationPoints;
  }

  /// Calculate distance between two GPS coordinates using the Haversine formula
  double _haversineDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const double R = 6371.0; // Radius of Earth in km
    final dLat = (lat2 - lat1) * math.pi / 180.0;
    final dLon = (lon2 - lon1) * math.pi / 180.0;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180.0) *
            math.cos(lat2 * math.pi / 180.0) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    final distance = R * c; // Distance in km
    return distance;
  }
}
