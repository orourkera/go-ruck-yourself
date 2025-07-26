import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:rucking_app/core/models/route.dart';
import 'package:rucking_app/core/models/route_elevation_point.dart';
import 'package:rucking_app/core/models/route_point_of_interest.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/config/app_config.dart';

/// Repository for managing route data and AllTrails integration
/// Provides methods to search, retrieve, create, and manage routes
class RoutesRepository {
  final http.Client _httpClient;
  
  RoutesRepository({http.Client? httpClient}) 
      : _httpClient = httpClient ?? http.Client();

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

      final uri = Uri.parse('${AppConfig.apiBaseUrl}/routes').replace(queryParameters: queryParams);

      final response = await _httpClient.get(
        uri,
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final routes = (data['routes'] as List)
            .map((routeJson) => Route.fromJson(routeJson as Map<String, dynamic>))
            .toList();
        
        AppLogger.info('Retrieved ${routes.length} routes');
        return routes;
      } else {
        AppLogger.error('Failed to get routes: ${response.statusCode} - ${response.body}');
        throw Exception('Failed to get routes: ${response.statusCode}');
      }
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

      final uri = Uri.parse('${AppConfig.apiBaseUrl}/routes/$routeId')
          .replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

      final response = await _httpClient.get(
        uri,
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final route = Route.fromJson(data as Map<String, dynamic>);
        AppLogger.info('Retrieved route: ${route.name}');
        return route;
      } else if (response.statusCode == 404) {
        AppLogger.warning('Route not found: $routeId');
        return null;
      } else {
        AppLogger.error('Failed to get route: ${response.statusCode} - ${response.body}');
        throw Exception('Failed to get route: ${response.statusCode}');
      }
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
      final response = await _httpClient.post(
        Uri.parse('${AppConfig.apiBaseUrl}/routes'),
        headers: await _getHeaders(),
        body: json.encode(route.toJson()),
      );

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        final createdRoute = Route.fromJson(data as Map<String, dynamic>);
        AppLogger.info('Created route: ${createdRoute.name}');
        return createdRoute;
      } else {
        AppLogger.error('Failed to create route: ${response.statusCode} - ${response.body}');
        throw Exception('Failed to create route: ${response.statusCode}');
      }
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
      final response = await _httpClient.put(
        Uri.parse('${AppConfig.apiBaseUrl}/routes/$routeId'),
        headers: await _getHeaders(),
        body: json.encode(route.toJson()),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final updatedRoute = Route.fromJson(data as Map<String, dynamic>);
        AppLogger.info('Updated route: ${updatedRoute.name}');
        return updatedRoute;
      } else {
        AppLogger.error('Failed to update route: ${response.statusCode} - ${response.body}');
        throw Exception('Failed to update route: ${response.statusCode}');
      }
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
      final response = await _httpClient.delete(
        Uri.parse('${AppConfig.apiBaseUrl}/routes/$routeId'),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        AppLogger.info('Deleted route: $routeId');
        return true;
      } else {
        AppLogger.error('Failed to delete route: ${response.statusCode} - ${response.body}');
        return false;
      }
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
      final response = await _httpClient.get(
        Uri.parse('${AppConfig.apiBaseUrl}/routes/$routeId/elevation'),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final elevationPoints = (data['elevation_points'] as List)
            .map((pointJson) => RouteElevationPoint.fromJson(pointJson as Map<String, dynamic>))
            .toList();
        
        AppLogger.info('Retrieved ${elevationPoints.length} elevation points for route $routeId');
        return elevationPoints;
      } else {
        AppLogger.error('Failed to get route elevation: ${response.statusCode} - ${response.body}');
        throw Exception('Failed to get route elevation: ${response.statusCode}');
      }
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
      final response = await _httpClient.get(
        Uri.parse('${AppConfig.apiBaseUrl}/routes/$routeId/pois'),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final pois = (data['points_of_interest'] as List)
            .map((poiJson) => RoutePointOfInterest.fromJson(poiJson as Map<String, dynamic>))
            .toList();
        
        AppLogger.info('Retrieved ${pois.length} POIs for route $routeId');
        return pois;
      } else {
        AppLogger.error('Failed to get route POIs: ${response.statusCode} - ${response.body}');
        throw Exception('Failed to get route POIs: ${response.statusCode}');
      }
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

      final uri = Uri.parse('${AppConfig.apiBaseUrl}/routes/trending')
          .replace(queryParameters: queryParams);

      final response = await _httpClient.get(
        uri,
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final routes = (data['trending_routes'] as List)
            .map((routeJson) => Route.fromJson(routeJson as Map<String, dynamic>))
            .toList();
        
        AppLogger.info('Retrieved ${routes.length} trending routes');
        return routes;
      } else {
        AppLogger.error('Failed to get trending routes: ${response.statusCode} - ${response.body}');
        throw Exception('Failed to get trending routes: ${response.statusCode}');
      }
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

      final uri = Uri.parse('${AppConfig.apiBaseUrl}/routes')
          .replace(queryParameters: queryParams);

      final response = await _httpClient.get(
        uri,
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final routes = (data['routes'] as List)
            .map((routeJson) => Route.fromJson(routeJson as Map<String, dynamic>))
            .toList();
        
        AppLogger.info('Retrieved ${routes.length} user routes');
        return routes;
      } else {
        AppLogger.error('Failed to get user routes: ${response.statusCode} - ${response.body}');
        throw Exception('Failed to get user routes: ${response.statusCode}');
      }
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

      final response = await _httpClient.post(
        Uri.parse('${AppConfig.apiBaseUrl}/routes/$routeId/rate'),
        headers: await _getHeaders(),
        body: json.encode(requestBody),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        AppLogger.info('Rated route $routeId: $rating stars');
        return true;
      } else {
        AppLogger.error('Failed to rate route: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      AppLogger.error('Error rating route $routeId: $e');
      return false;
    }
  }

  /// Get common HTTP headers for API requests
  Future<Map<String, String>> _getHeaders() async {
    // This would typically include authentication headers
    // For now, using basic headers - will be updated when auth is integrated
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      // TODO: Add authorization header when available
      // 'Authorization': 'Bearer $token',
    };
  }

  /// Dispose of resources
  void dispose() {
    _httpClient.close();
  }
}
