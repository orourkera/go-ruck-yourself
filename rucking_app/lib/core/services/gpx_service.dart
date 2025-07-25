import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'package:rucking_app/core/models/route.dart';
import 'package:rucking_app/core/models/route_elevation_point.dart';
import 'package:rucking_app/core/models/route_point_of_interest.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_session.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/config/app_config.dart';

/// Service for parsing and generating GPX files
/// Handles AllTrails GPX import, route export, and session export
class GpxService {
  final http.Client _httpClient;
  
  GpxService({http.Client? httpClient}) 
      : _httpClient = httpClient ?? http.Client();

  /// Parse GPX file and extract route data
  /// 
  /// Parameters:
  /// - [gpxContent]: GPX file content as string
  /// 
  /// Returns parsed route data or throws exception on error
  Future<ParsedGpxData> parseGpxContent(String gpxContent) async {
    try {
      final document = XmlDocument.parse(gpxContent);
      final gpxElement = document.rootElement;
      
      if (gpxElement.name.local != 'gpx') {
        throw FormatException('Invalid GPX file: Root element is not <gpx>');
      }

      // Extract metadata
      final metadata = _extractMetadata(gpxElement);
      
      // Extract tracks (main route data)
      final tracks = _extractTracks(gpxElement);
      
      // Extract waypoints (POIs)
      final waypoints = _extractWaypoints(gpxElement);
      
      // Extract routes (if any)
      final routes = _extractRoutes(gpxElement);
      
      if (tracks.isEmpty && routes.isEmpty) {
        throw FormatException('GPX file contains no track or route data');
      }

      // Use track data if available, otherwise use route data
      final trackData = tracks.isNotEmpty ? tracks.first : routes.first;
      
      final parsedData = ParsedGpxData(
        name: metadata['name'] ?? 'Imported Route',
        description: metadata['description'],
        source: 'gpx_import',
        externalUrl: metadata['link'],
        trackPoints: trackData.points,
        waypoints: waypoints,
        metadata: metadata,
      );

      AppLogger.info('Parsed GPX file: ${parsedData.name} with ${parsedData.trackPoints.length} points');
      return parsedData;
    } catch (e) {
      AppLogger.error('Error parsing GPX content: $e');
      throw Exception('Error parsing GPX file: $e');
    }
  }

  /// Import GPX file to backend and create route
  /// 
  /// Parameters:
  /// - [gpxFile]: GPX file to import
  /// - [makePublic]: Whether to make the imported route public (default: false)
  /// 
  /// Returns created route or throws exception on error
  Future<Route> importGpxFile(File gpxFile, {bool makePublic = false}) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${AppConfig.apiBaseUrl}/gpx/import'),
      );

      request.headers.addAll(await _getHeaders());
      request.fields['make_public'] = makePublic.toString();
      request.files.add(await http.MultipartFile.fromPath('file', gpxFile.path));

      final streamedResponse = await _httpClient.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        final route = Route.fromJson(data['route'] as Map<String, dynamic>);
        
        AppLogger.info('Successfully imported GPX file: ${route.name}');
        return route;
      } else {
        AppLogger.error('Failed to import GPX file: ${response.statusCode} - ${response.body}');
        throw Exception('Failed to import GPX file: ${response.statusCode}');
      }
    } catch (e) {
      AppLogger.error('Error importing GPX file: $e');
      throw Exception('Error importing GPX file: $e');
    }
  }

  /// Validate GPX file without importing
  /// 
  /// Parameters:
  /// - [gpxFile]: GPX file to validate
  /// 
  /// Returns validation result with basic route info
  Future<GpxValidationResult> validateGpxFile(File gpxFile) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${AppConfig.apiBaseUrl}/gpx/validate'),
      );

      request.headers.addAll(await _getHeaders());
      request.files.add(await http.MultipartFile.fromPath('file', gpxFile.path));

      final streamedResponse = await _httpClient.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final result = GpxValidationResult.fromJson(data as Map<String, dynamic>);
        
        AppLogger.info('GPX validation successful: ${result.name}');
        return result;
      } else {
        AppLogger.error('GPX validation failed: ${response.statusCode} - ${response.body}');
        throw Exception('GPX validation failed: ${response.statusCode}');
      }
    } catch (e) {
      AppLogger.error('Error validating GPX file: $e');
      throw Exception('Error validating GPX file: $e');
    }
  }

  /// Export route as GPX file
  /// 
  /// Parameters:
  /// - [routeId]: ID of the route to export
  /// - [includeElevation]: Include elevation data (default: true)
  /// - [includePois]: Include points of interest (default: true)
  /// 
  /// Returns GPX file content as string
  Future<String> exportRouteAsGpx(
    String routeId, {
    bool includeElevation = true,
    bool includePois = true,
  }) async {
    try {
      final queryParams = <String, String>{
        'include_elevation': includeElevation.toString(),
        'include_pois': includePois.toString(),
      };

      final uri = Uri.parse('${AppConfig.apiBaseUrl}/routes/$routeId')
          .replace(queryParameters: queryParams);

      final response = await _httpClient.get(
        uri,
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        AppLogger.info('Successfully exported route $routeId as GPX');
        return response.body;
      } else {
        AppLogger.error('Failed to export route as GPX: ${response.statusCode} - ${response.body}');
        throw Exception('Failed to export route as GPX: ${response.statusCode}');
      }
    } catch (e) {
      AppLogger.error('Error exporting route $routeId as GPX: $e');
      throw Exception('Error exporting route as GPX: $e');
    }
  }

  /// Export ruck session as GPX file
  /// 
  /// Parameters:
  /// - [sessionId]: ID of the ruck session to export
  /// - [includeHeartRate]: Include heart rate data (default: true)
  /// 
  /// Returns GPX file content as string
  Future<String> exportSessionAsGpx(
    String sessionId, {
    bool includeHeartRate = true,
  }) async {
    try {
      final queryParams = <String, String>{
        'include_heart_rate': includeHeartRate.toString(),
      };

      final uri = Uri.parse('${AppConfig.apiBaseUrl}/ruck-sessions/$sessionId/gpx')
          .replace(queryParameters: queryParams);

      final response = await _httpClient.get(
        uri,
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        AppLogger.info('Successfully exported session $sessionId as GPX');
        return response.body;
      } else {
        AppLogger.error('Failed to export session as GPX: ${response.statusCode} - ${response.body}');
        throw Exception('Failed to export session as GPX: ${response.statusCode}');
      }
    } catch (e) {
      AppLogger.error('Error exporting session $sessionId as GPX: $e');
      throw Exception('Error exporting session as GPX: $e');
    }
  }

  /// Generate GPX content locally from route data
  /// 
  /// Parameters:
  /// - [route]: Route to generate GPX for
  /// - [elevationPoints]: Optional elevation points
  /// - [pois]: Optional points of interest
  /// 
  /// Returns GPX file content as string
  String generateGpxFromRoute(
    Route route, {
    List<RouteElevationPoint>? elevationPoints,
    List<RoutePointOfInterest>? pois,
  }) {
    try {
      final builder = XmlBuilder();
      
      builder.processing('xml', 'version="1.0" encoding="UTF-8"');
      builder.element('gpx', nest: () {
        builder.attribute('version', '1.1');
        builder.attribute('creator', 'RuckTracker App');
        builder.attribute('xmlns', 'http://www.topografix.com/GPX/1/1');
        builder.attribute('xmlns:xsi', 'http://www.w3.org/2001/XMLSchema-instance');
        builder.attribute('xsi:schemaLocation', 'http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd');

        // Metadata
        builder.element('metadata', nest: () {
          builder.element('name', nest: route.name);
          if (route.description?.isNotEmpty == true) {
            builder.element('desc', nest: route.description);
          }
          builder.element('time', nest: DateTime.now().toUtc().toIso8601String());
        });

        // Waypoints (POIs)
        if (pois?.isNotEmpty == true) {
          for (final poi in pois!) {
            builder.element('wpt', nest: () {
              builder.attribute('lat', poi.latitude.toString());
              builder.attribute('lon', poi.longitude.toString());
              builder.element('name', nest: poi.name);
              if (poi.description?.isNotEmpty == true) {
                builder.element('desc', nest: poi.description);
              }
              builder.element('type', nest: poi.poiType);
            });
          }
        }

        // Track
        builder.element('trk', nest: () {
          builder.element('name', nest: route.name);
          if (route.description?.isNotEmpty == true) {
            builder.element('desc', nest: route.description);
          }
          
          builder.element('trkseg', nest: () {
            // If we have elevation points, use them
            if (elevationPoints?.isNotEmpty == true) {
              for (final point in elevationPoints!) {
                if (point.hasCoordinates) {
                  builder.element('trkpt', nest: () {
                    builder.attribute('lat', point.latitude.toString());
                    builder.attribute('lon', point.longitude.toString());
                    builder.element('ele', nest: point.elevationM.toString());
                  });
                }
              }
            } else {
              // Use start/end points as basic track
              builder.element('trkpt', nest: () {
                builder.attribute('lat', route.startLatitude.toString());
                builder.attribute('lon', route.startLongitude.toString());
                if (route.elevationGainM != null) {
                  builder.element('ele', nest: '0'); // Placeholder
                }
              });
              
              if (route.endLatitude != null && route.endLongitude != null) {
                builder.element('trkpt', nest: () {
                  builder.attribute('lat', route.endLatitude.toString());
                  builder.attribute('lon', route.endLongitude.toString());
                  if (route.elevationGainM != null) {
                    builder.element('ele', nest: route.elevationGainM.toString());
                  }
                });
              }
            }
          });
        });
      });

      final document = builder.buildDocument();
      final gpxContent = document.toXmlString(pretty: true, indent: '  ');
      
      AppLogger.info('Generated GPX content for route: ${route.name}');
      return gpxContent;
    } catch (e) {
      AppLogger.error('Error generating GPX from route: $e');
      throw Exception('Error generating GPX from route: $e');
    }
  }

  /// Generate GPX content locally from ruck session
  /// 
  /// Parameters:
  /// - [session]: Ruck session to generate GPX for
  /// - [includeHeartRate]: Include heart rate data (default: true)
  /// 
  /// Returns GPX file content as string
  String generateGpxFromSession(
    RuckSession session, {
    bool includeHeartRate = true,
  }) {
    try {
      final builder = XmlBuilder();
      
      builder.processing('xml', 'version="1.0" encoding="UTF-8"');
      builder.element('gpx', nest: () {
        builder.attribute('version', '1.1');
        builder.attribute('creator', 'RuckTracker App');
        builder.attribute('xmlns', 'http://www.topografix.com/GPX/1/1');
        builder.attribute('xmlns:gpxtpx', 'http://www.garmin.com/xmlschemas/TrackPointExtension/v1');

        // Metadata
        builder.element('metadata', nest: () {
          builder.element('name', nest: 'Ruck Session ${session.id}');
          builder.element('desc', nest: 'Ruck session from ${session.startTime}');
          builder.element('time', nest: session.startTime.toUtc().toIso8601String());
        });

        // Track
        builder.element('trk', nest: () {
          builder.element('name', nest: 'Ruck Session ${session.id}');
          
          builder.element('trkseg', nest: () {
            if (session.locationPoints?.isNotEmpty == true) {
              for (final locationPoint in session.locationPoints!) {
                final point = locationPoint as Map<String, dynamic>;
                builder.element('trkpt', nest: () {
                  builder.attribute('lat', point['latitude'].toString());
                  builder.attribute('lon', point['longitude'].toString());
                  
                  if (point['elevation'] != null) {
                    builder.element('ele', nest: point['elevation'].toString());
                  }
                  
                  if (point['timestamp'] != null) {
                    builder.element('time', nest: DateTime.parse(point['timestamp']).toUtc().toIso8601String());
                  }
                  
                  // Heart rate extensions
                  if (includeHeartRate && point['heart_rate'] != null) {
                    builder.element('extensions', nest: () {
                      builder.element('gpxtpx:TrackPointExtension', nest: () {
                        builder.element('gpxtpx:hr', nest: point['heart_rate'].toString());
                      });
                    });
                  }
                });
              }
            }
          });
        });
      });

      final document = builder.buildDocument();
      final gpxContent = document.toXmlString(pretty: true, indent: '  ');
      
      AppLogger.info('Generated GPX content for session: ${session.id}');
      return gpxContent;
    } catch (e) {
      AppLogger.error('Error generating GPX from session: $e');
      throw Exception('Error generating GPX from session: $e');
    }
  }

  /// Save GPX content to file
  /// 
  /// Parameters:
  /// - [gpxContent]: GPX content to save
  /// - [fileName]: Name of the file (without extension)
  /// - [directory]: Directory to save file in
  /// 
  /// Returns the created file
  Future<File> saveGpxToFile(
    String gpxContent,
    String fileName,
    Directory directory,
  ) async {
    try {
      final file = File('${directory.path}/$fileName.gpx');
      await file.writeAsString(gpxContent);
      
      AppLogger.info('Saved GPX file: ${file.path}');
      return file;
    } catch (e) {
      AppLogger.error('Error saving GPX file: $e');
      throw Exception('Error saving GPX file: $e');
    }
  }

  // Private helper methods

  /// Extract metadata from GPX element
  Map<String, String> _extractMetadata(XmlElement gpxElement) {
    final metadata = <String, String>{};
    
    // Try to get metadata from metadata element
    final metadataElement = gpxElement.findElements('metadata').firstOrNull;
    if (metadataElement != null) {
      final nameElement = metadataElement.findElements('name').firstOrNull;
      if (nameElement != null) {
        metadata['name'] = nameElement.innerText;
      }
      
      final descElement = metadataElement.findElements('desc').firstOrNull;
      if (descElement != null) {
        metadata['description'] = descElement.innerText;
      }
      
      final linkElement = metadataElement.findElements('link').firstOrNull;
      if (linkElement != null) {
        metadata['link'] = linkElement.getAttribute('href') ?? '';
      }
    }
    
    // Fallback to GPX element attributes
    if (metadata['name'] == null) {
      final creator = gpxElement.getAttribute('creator');
      if (creator != null) {
        metadata['creator'] = creator;
      }
    }
    
    return metadata;
  }

  /// Extract tracks from GPX element
  List<GpxTrack> _extractTracks(XmlElement gpxElement) {
    final tracks = <GpxTrack>[];
    
    for (final trkElement in gpxElement.findElements('trk')) {
      final name = trkElement.findElements('name').firstOrNull?.innerText ?? 'Track';
      final description = trkElement.findElements('desc').firstOrNull?.innerText;
      final points = <GpxTrackPoint>[];
      
      for (final trksegElement in trkElement.findElements('trkseg')) {
        for (final trkptElement in trksegElement.findElements('trkpt')) {
          final lat = double.tryParse(trkptElement.getAttribute('lat') ?? '');
          final lon = double.tryParse(trkptElement.getAttribute('lon') ?? '');
          
          if (lat != null && lon != null) {
            final elevation = double.tryParse(
              trkptElement.findElements('ele').firstOrNull?.innerText ?? ''
            );
            
            final timeString = trkptElement.findElements('time').firstOrNull?.innerText;
            final time = timeString != null ? DateTime.tryParse(timeString) : null;
            
            points.add(GpxTrackPoint(
              latitude: lat,
              longitude: lon,
              elevation: elevation,
              time: time,
            ));
          }
        }
      }
      
      tracks.add(GpxTrack(
        name: name,
        description: description,
        points: points,
      ));
    }
    
    return tracks;
  }

  /// Extract waypoints from GPX element
  List<GpxWaypoint> _extractWaypoints(XmlElement gpxElement) {
    final waypoints = <GpxWaypoint>[];
    
    for (final wptElement in gpxElement.findElements('wpt')) {
      final lat = double.tryParse(wptElement.getAttribute('lat') ?? '');
      final lon = double.tryParse(wptElement.getAttribute('lon') ?? '');
      
      if (lat != null && lon != null) {
        final name = wptElement.findElements('name').firstOrNull?.innerText ?? 'Waypoint';
        final description = wptElement.findElements('desc').firstOrNull?.innerText;
        final type = wptElement.findElements('type').firstOrNull?.innerText ?? 'waypoint';
        final elevation = double.tryParse(
          wptElement.findElements('ele').firstOrNull?.innerText ?? ''
        );
        
        waypoints.add(GpxWaypoint(
          name: name,
          description: description,
          latitude: lat,
          longitude: lon,
          elevation: elevation,
          type: type,
        ));
      }
    }
    
    return waypoints;
  }

  /// Extract routes from GPX element (alternative to tracks)
  List<GpxTrack> _extractRoutes(XmlElement gpxElement) {
    final routes = <GpxTrack>[];
    
    for (final rteElement in gpxElement.findElements('rte')) {
      final name = rteElement.findElements('name').firstOrNull?.innerText ?? 'Route';
      final description = rteElement.findElements('desc').firstOrNull?.innerText;
      final points = <GpxTrackPoint>[];
      
      for (final rteptElement in rteElement.findElements('rtept')) {
        final lat = double.tryParse(rteptElement.getAttribute('lat') ?? '');
        final lon = double.tryParse(rteptElement.getAttribute('lon') ?? '');
        
        if (lat != null && lon != null) {
          final elevation = double.tryParse(
            rteptElement.findElements('ele').firstOrNull?.innerText ?? ''
          );
          
          points.add(GpxTrackPoint(
            latitude: lat,
            longitude: lon,
            elevation: elevation,
            time: null,
          ));
        }
      }
      
      routes.add(GpxTrack(
        name: name,
        description: description,
        points: points,
      ));
    }
    
    return routes;
  }

  /// Get common HTTP headers for API requests
  Future<Map<String, String>> _getHeaders() async {
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

// Data classes for GPX parsing

/// Parsed GPX data container
class ParsedGpxData {
  final String name;
  final String? description;
  final String source;
  final String? externalUrl;
  final List<GpxTrackPoint> trackPoints;
  final List<GpxWaypoint> waypoints;
  final Map<String, String> metadata;

  const ParsedGpxData({
    required this.name,
    this.description,
    required this.source,
    this.externalUrl,
    required this.trackPoints,
    required this.waypoints,
    required this.metadata,
  });

  /// Calculate total distance from track points
  double get totalDistanceKm {
    if (trackPoints.length < 2) return 0.0;
    
    double totalDistance = 0.0;
    for (int i = 1; i < trackPoints.length; i++) {
      totalDistance += trackPoints[i - 1].distanceTo(trackPoints[i]);
    }
    
    return totalDistance / 1000; // Convert to kilometers
  }

  /// Calculate elevation gain from track points
  double get elevationGainM {
    if (trackPoints.length < 2) return 0.0;
    
    double gain = 0.0;
    for (int i = 1; i < trackPoints.length; i++) {
      final prevElevation = trackPoints[i - 1].elevation;
      final currElevation = trackPoints[i].elevation;
      
      if (prevElevation != null && currElevation != null) {
        final change = currElevation - prevElevation;
        if (change > 0) {
          gain += change;
        }
      }
    }
    
    return gain;
  }

  /// Calculate elevation loss from track points
  double get elevationLossM {
    if (trackPoints.length < 2) return 0.0;
    
    double loss = 0.0;
    for (int i = 1; i < trackPoints.length; i++) {
      final prevElevation = trackPoints[i - 1].elevation;
      final currElevation = trackPoints[i].elevation;
      
      if (prevElevation != null && currElevation != null) {
        final change = currElevation - prevElevation;
        if (change < 0) {
          loss += change.abs();
        }
      }
    }
    
    return loss;
  }
}

/// GPX track container
class GpxTrack {
  final String name;
  final String? description;
  final List<GpxTrackPoint> points;

  const GpxTrack({
    required this.name,
    this.description,
    required this.points,
  });
}

/// GPX track point
class GpxTrackPoint {
  final double latitude;
  final double longitude;
  final double? elevation;
  final DateTime? time;

  const GpxTrackPoint({
    required this.latitude,
    required this.longitude,
    this.elevation,
    this.time,
  });

  /// Calculate distance to another point using Haversine formula
  double distanceTo(GpxTrackPoint other) {
    const double earthRadius = 6371000; // Earth's radius in meters
    
    final double dLat = _toRadians(other.latitude - latitude);
    final double dLon = _toRadians(other.longitude - longitude);
    
    final double a = 
        (dLat / 2).sin() * (dLat / 2).sin() +
        latitude.toRadians().cos() * other.latitude.toRadians().cos() *
        (dLon / 2).sin() * (dLon / 2).sin();
    
    final double c = 2 * (a.sqrt()).asin();
    
    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * (3.14159265359 / 180);
}

/// GPX waypoint
class GpxWaypoint {
  final String name;
  final String? description;
  final double latitude;
  final double longitude;
  final double? elevation;
  final String type;

  const GpxWaypoint({
    required this.name,
    this.description,
    required this.latitude,
    required this.longitude,
    this.elevation,
    required this.type,
  });
}

/// GPX validation result
class GpxValidationResult {
  final bool isValid;
  final String name;
  final String? description;
  final double distanceKm;
  final double? elevationGainM;
  final double? elevationLossM;
  final int trackPointCount;
  final int waypointCount;
  final List<String> errors;
  final List<String> warnings;

  const GpxValidationResult({
    required this.isValid,
    required this.name,
    this.description,
    required this.distanceKm,
    this.elevationGainM,
    this.elevationLossM,
    required this.trackPointCount,
    required this.waypointCount,
    required this.errors,
    required this.warnings,
  });

  factory GpxValidationResult.fromJson(Map<String, dynamic> json) {
    return GpxValidationResult(
      isValid: json['is_valid'] as bool,
      name: json['name'] as String,
      description: json['description'] as String?,
      distanceKm: (json['distance_km'] as num).toDouble(),
      elevationGainM: json['elevation_gain_m'] != null 
          ? (json['elevation_gain_m'] as num).toDouble() 
          : null,
      elevationLossM: json['elevation_loss_m'] != null 
          ? (json['elevation_loss_m'] as num).toDouble() 
          : null,
      trackPointCount: json['track_point_count'] as int,
      waypointCount: json['waypoint_count'] as int,
      errors: (json['errors'] as List<dynamic>).map((e) => e.toString()).toList(),
      warnings: (json['warnings'] as List<dynamic>).map((e) => e.toString()).toList(),
    );
  }
}

// Extension for easier radian conversion and math operations
extension on double {
  double toRadians() => this * (3.14159265359 / 180);
  double sin() => math.sin(this);
  double cos() => math.cos(this);
  double asin() => math.asin(this);
  double sqrt() => math.sqrt(this);
}
