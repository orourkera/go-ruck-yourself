import 'package:rucking_app/core/models/route.dart';
import 'package:rucking_app/core/models/route_elevation_point.dart';
import 'package:rucking_app/core/models/route_point_of_interest.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:get_it/get_it.dart';

/// Repository for managing route data and AllTrails integration
/// Provides methods to search, retrieve, create, and manage routes
class RoutesRepository {
  final ApiClient _apiClient;
  
  RoutesRepository({ApiClient? apiClient}) 
      : _apiClient = apiClient ?? GetIt.instance<ApiClient>();

  /// Get all routes with optional filtering
  /// 
  /// Parameters:
  /// - [limit]: Maximum number of routes to return (default: 20)
  /// - [offset]: Number of routes to skip for pagination (default: 0)
  /// - [search]: Search term to filter routes by name/description
  /// - [source]: Filter by route source ('alltrails', 'custom', etc.)
  /// - [difficulty]: Filter by difficulty level ('easy', 'moderate', 'hard', 'extreme')
  /// - [minDistance]: Minimum distance in km
  /// - [maxDistance]: Maximum distance in km
  /// - [nearLatitude]: Latitude for proximity search
  /// - [nearLongitude]: Longitude for proximity search
  /// - [radiusKm]: Search radius in km (requires nearLatitude/nearLongitude)
  /// - [isPublic]: Filter by public/private routes
  /// - [isVerified]: Filter by verified routes only
  Future<List<Route>> getRoutes({
    int limit = 20,
    int offset = 0,
    String? search,
    String? source,
    String? difficulty,
    double? minDistance,
    double? maxDistance,
    double? nearLatitude,
    double? nearLongitude,
    double? radiusKm,
    bool? isPublic,
    bool? isVerified,
  }) async {
    try {
      final queryParams = <String, String>{
        'limit': limit.toString(),
        'offset': offset.toString(),
      };
      
      if (search?.isNotEmpty == true) queryParams['search'] = search!;
      if (source?.isNotEmpty == true) queryParams['source'] = source!;
      if (difficulty?.isNotEmpty == true) queryParams['difficulty'] = difficulty!;
      if (minDistance != null) queryParams['min_distance'] = minDistance.toString();
      if (maxDistance != null) queryParams['max_distance'] = maxDistance.toString();
      if (nearLatitude != null) queryParams['near_lat'] = nearLatitude.toString();
      if (nearLongitude != null) queryParams['near_lng'] = nearLongitude.toString();
      if (radiusKm != null) queryParams['radius_km'] = radiusKm.toString();
      if (isPublic != null) queryParams['is_public'] = isPublic.toString();
      if (isVerified != null) queryParams['is_verified'] = isVerified.toString();

      final data = await _apiClient.get('/routes', queryParams: queryParams);
      final routes = (data['routes'] as List)
          .map((routeJson) => Route.fromJson(routeJson as Map<String, dynamic>))
          .toList();
      
      AppLogger.info('Retrieved ${routes.length} routes');
      return routes;
    } catch (e) {
      AppLogger.error('Error getting routes: $e');
      throw Exception('Error getting routes: $e');
    }
  }

  /// Get a specific route by ID with optional detailed data
  /// 
  /// Parameters:
  /// - [routeId]: ID of the route to retrieve
  /// - [includeElevation]: Include elevation profile points (default: false)
  /// - [includePois]: Include points of interest (default: false)
  Future<Route?> getRoute(
    String routeId, {
    bool includeElevation = false,
    bool includePois = false,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (includeElevation) queryParams['include_elevation'] = 'true';
      if (includePois) queryParams['include_pois'] = 'true';

      final data = await _apiClient.get('/routes/$routeId', queryParams: queryParams.isNotEmpty ? queryParams : null);
      final route = Route.fromJson(data as Map<String, dynamic>);
      AppLogger.info('Retrieved route: ${route.name}');
      return route;
    } catch (e) {
      AppLogger.error('Error getting route $routeId: $e');
      throw Exception('Error getting route: $e');
    }
  }

  /// Create a new route
  /// 
  /// Parameters:
  /// - [route]: Route data to create
  Future<Route> createRoute(Route route) async {
    try {
      final data = await _apiClient.post('/routes', route.toJson());
      final createdRoute = Route.fromJson(data as Map<String, dynamic>);
      AppLogger.info('Created route: ${createdRoute.name}');
      return createdRoute;
    } catch (e) {
      AppLogger.error('Error creating route: $e');
      throw Exception('Error creating route: $e');
    }
  }

  /// Update an existing route
  /// 
  /// Parameters:
  /// - [routeId]: ID of the route to update
  /// - [route]: Updated route data
  Future<Route> updateRoute(String routeId, Route route) async {
    try {
      final data = await _apiClient.put('/routes/$routeId', route.toJson());
      final updatedRoute = Route.fromJson(data as Map<String, dynamic>);
      AppLogger.info('Updated route: ${updatedRoute.name}');
      return updatedRoute;
    } catch (e) {
      AppLogger.error('Error updating route $routeId: $e');
      throw Exception('Error updating route: $e');
    }
  }

  /// Delete a route
  /// 
  /// Parameters:
  /// - [routeId]: ID of the route to delete
  Future<bool> deleteRoute(String routeId) async {
    try {
      await _apiClient.delete('/routes/$routeId');
      AppLogger.info('Deleted route: $routeId');
      return true;
    } catch (e) {
      AppLogger.error('Error deleting route $routeId: $e');
      return false;
    }
  }

  /// Get elevation profile for a route
  /// 
  /// Parameters:
  /// - [routeId]: ID of the route
  Future<List<RouteElevationPoint>> getRouteElevation(String routeId) async {
    try {
      final data = await _apiClient.get('/routes/$routeId/elevation');
      final elevationPoints = (data['elevation_points'] as List)
          .map((pointJson) => RouteElevationPoint.fromJson(pointJson as Map<String, dynamic>))
          .toList();
      
      AppLogger.info('Retrieved ${elevationPoints.length} elevation points for route $routeId');
      return elevationPoints;
    } catch (e) {
      AppLogger.error('Error getting route elevation $routeId: $e');
      throw Exception('Error getting route elevation: $e');
    }
  }

  /// Get points of interest for a route
  /// 
  /// Parameters:
  /// - [routeId]: ID of the route
  Future<List<RoutePointOfInterest>> getRoutePois(String routeId) async {
    try {
      final data = await _apiClient.get('/routes/$routeId/pois');
      final pois = (data['pois'] as List)
          .map((poiJson) => RoutePointOfInterest.fromJson(poiJson as Map<String, dynamic>))
          .toList();
      
      AppLogger.info('Retrieved ${pois.length} POIs for route $routeId');
      return pois;
    } catch (e) {
      AppLogger.error('Error getting route POIs $routeId: $e');
      throw Exception('Error getting route POIs: $e');
    }
  }

  /// Search for trending/popular routes
  /// 
  /// Parameters:
  /// - [limit]: Maximum number of routes to return (default: 10)
  /// - [timeframe]: Timeframe for trending ('day', 'week', 'month')
  Future<List<Route>> getTrendingRoutes({
    int limit = 10,
    String timeframe = 'week',
  }) async {
    try {
      final queryParams = <String, String>{
        'limit': limit.toString(),
        'timeframe': timeframe,
      };

      final data = await _apiClient.get('/routes/trending', queryParams: queryParams);
      final routes = (data['trending_routes'] as List)
          .map((routeJson) => Route.fromJson(routeJson as Map<String, dynamic>))
          .toList();
      
      AppLogger.info('Retrieved ${routes.length} trending routes');
      return routes;
    } catch (e) {
      AppLogger.error('Error getting trending routes: $e');
      throw Exception('Error getting trending routes: $e');
    }
  }

  /// Get routes created by current user
  /// 
  /// Parameters:
  /// - [limit]: Maximum number of routes to return (default: 20)
  /// - [offset]: Number of routes to skip for pagination (default: 0)
  Future<List<Route>> getMyRoutes({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final queryParams = <String, String>{
        'limit': limit.toString(),
        'offset': offset.toString(),
        'created_by_me': 'true',
      };

      final response = await _apiClient.get('/routes', queryParams: queryParams);
    
    // Debug: Print raw API response
    AppLogger.info('=== API Response Debug ===');
    AppLogger.info('Response keys: ${response.keys.toList()}');
    
    final data = response['data'] ?? response; // Handle both nested and flat structures
    AppLogger.info('Data keys: ${data.keys.toList()}');
    
    final routesList = data['routes'] as List? ?? [];
    AppLogger.info('Routes list length: ${routesList.length}');
    
    if (routesList.isNotEmpty) {
      final firstRoute = routesList.first as Map<String, dynamic>;
      AppLogger.info('First route keys: ${firstRoute.keys.toList()}');
      AppLogger.info('First route polyline: "${firstRoute['route_polyline']}"');
      AppLogger.info('First route polyline type: ${firstRoute['route_polyline'].runtimeType}');
    }
    
    final routes = routesList
        .map((routeJson) => Route.fromJson(routeJson as Map<String, dynamic>))
        .toList();
      
      AppLogger.info('Retrieved ${routes.length} user routes');
      return routes;
    } catch (e) {
      AppLogger.error('Error getting user routes: $e');
      throw Exception('Error getting user routes: $e');
    }
  }

  /// Rate a route
  /// 
  /// Parameters:
  /// - [routeId]: ID of the route to rate
  /// - [rating]: Rating value (1-5 stars)
  /// - [comment]: Optional comment about the route
  Future<bool> rateRoute(String routeId, int rating, {String? comment}) async {
    try {
      final requestBody = {
        'rating': rating,
        if (comment?.isNotEmpty == true) 'comment': comment,
      };

      await _apiClient.post('/routes/$routeId/rate', requestBody);
      AppLogger.info('Rated route $routeId: $rating stars');
      return true;
    } catch (e) {
      AppLogger.error('Error rating route $routeId: $e');
      return false;
    }
  }

  /// Dispose of resources
  void dispose() {
    // ApiClient is managed by GetIt, no need to dispose
  }
}
