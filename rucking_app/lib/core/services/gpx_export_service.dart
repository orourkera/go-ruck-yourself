import 'dart:io';
import 'dart:math' as math;
import 'package:xml/xml.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:rucking_app/core/models/route.dart';
import 'package:rucking_app/core/models/planned_ruck.dart';

/// 🗂️ **GPX Export Service**
///
/// Professional GPX file generation from routes and planned rucks
/// with support for waypoints, elevation, and metadata.
class GPXExportService {
  static const String _gpxNamespace = 'http://www.topografix.com/GPX/1/1';

  /// 🚀 **Export Route to GPX File**
  ///
  /// Creates a GPX file from a Route model with full metadata
  Future<File> exportRouteToGPX(Route route, {String? customFileName}) async {
    final gpxContent = _generateRouteGPX(route);
    return await _writeGPXFile(
        gpxContent, customFileName ?? '${route.name}.gpx');
  }

  /// 📅 **Export Planned Ruck to GPX File**
  ///
  /// Creates a GPX file from a PlannedRuck with route data
  Future<File> exportPlannedRuckToGPX(PlannedRuck plannedRuck,
      {String? customFileName}) async {
    if (plannedRuck.route == null) {
      throw ArgumentError('Planned ruck must have a route to export');
    }

    final gpxContent = _generatePlannedRuckGPX(plannedRuck);
    final fileName = customFileName ??
        '${plannedRuck.route?.name ?? 'Planned Ruck'}_${plannedRuck.plannedDate.toLocal().toString().split(' ')[0]}.gpx';
    return await _writeGPXFile(gpxContent, fileName);
  }

  /// **Export Multiple Routes as GPX Collection**
  ///
  /// Creates a single GPX file with multiple tracks
  Future<File> exportMultipleRoutesToGPX(
    List<Route> routes,
    String fileName,
  ) async {
    final gpxContent = _generateMultipleRoutesGPX(routes);
    return await _writeGPXFile(gpxContent, fileName);
  }

  /// **Generate Route GPX Content**
  String _generateRouteGPX(Route route) {
    final builder = XmlBuilder();

    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element('gpx', nest: () {
      builder.attribute('version', '1.1');
      builder.attribute('creator', 'Ruck! - Go Ruck Yourself');
      builder.attribute('xmlns', _gpxNamespace);
      builder.attribute(
          'xmlns:xsi', 'http://www.w3.org/2001/XMLSchema-instance');
      builder.attribute('xsi:schemaLocation',
          '$_gpxNamespace http://www.topografix.com/GPX/1/1/gpx.xsd');

      // Metadata
      builder.element('metadata', nest: () {
        builder.element('name', nest: route.name);
        builder.element('desc',
            nest: route.description ?? 'Exported from Ruck!');
        builder.element('author', nest: () {
          builder.element('name', nest: 'Ruck! - Go Ruck Yourself');
        });
        builder.element('time', nest: DateTime.now().toUtc().toIso8601String());

        // Note: In a real implementation, you'd decode routePolyline to get coordinates
        // For now, using elevation points as coordinate source
        if (route.elevationPoints.isNotEmpty) {
          final coordinates = route.elevationPoints
              .where((p) => p.latitude != null && p.longitude != null)
              .map((p) => {'lat': p.latitude!, 'lon': p.longitude!})
              .toList();
          if (coordinates.isNotEmpty) {
            final bounds = _calculateBounds(coordinates);
            builder.element('bounds', nest: () {
              builder.attribute('minlat', bounds['minLat'].toString());
              builder.attribute('minlon', bounds['minLon'].toString());
              builder.attribute('maxlat', bounds['maxLat'].toString());
              builder.attribute('maxlon', bounds['maxLon'].toString());
            });
          }
        }
      });

      // Waypoints (POIs)
      if (route.pointsOfInterest.isNotEmpty) {
        for (final poi in route.pointsOfInterest) {
          builder.element('wpt', nest: () {
            builder.attribute('lat', poi.latitude.toString());
            builder.attribute('lon', poi.longitude.toString());
            builder.element('name', nest: poi.name);
            if (poi.description?.isNotEmpty == true) {
              builder.element('desc', nest: poi.description);
            }
            builder.element('type', nest: poi.type);
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
          for (int i = 0; i < route.elevationPoints.length; i++) {
            final point = route.elevationPoints[i];
            if (point.latitude == null || point.longitude == null) continue;
            builder.element('trkpt', nest: () {
              builder.attribute('lat', point.latitude.toString());
              builder.attribute('lon', point.longitude.toString());

              // Add elevation if available
              builder.element('ele', nest: point.elevationM.toString());

              // Add timestamp if this is part of a session
              builder.element('time',
                  nest: DateTime.now()
                      .add(Duration(minutes: i))
                      .toUtc()
                      .toIso8601String());
            });
          }
        });
      });
    });

    return builder.buildDocument().toXmlString(pretty: true);
  }

  /// **Generate Planned Ruck GPX Content**
  String _generatePlannedRuckGPX(PlannedRuck plannedRuck) {
    final route = plannedRuck.route!;
    final builder = XmlBuilder();

    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element('gpx', nest: () {
      builder.attribute('version', '1.1');
      builder.attribute('creator', 'Ruck! - Go Ruck Yourself');
      builder.attribute('xmlns', _gpxNamespace);

      // Enhanced metadata for planned ruck
      builder.element('metadata', nest: () {
        builder.element('name',
            nest: plannedRuck.route?.name ?? 'Planned Ruck');
        builder.element('desc',
            nest: plannedRuck.notes ?? 'Planned ruck session');
        builder.element('time',
            nest: plannedRuck.plannedDate.toUtc().toIso8601String());

        // Custom extensions for ruck data
        builder.element('extensions', nest: () {
          builder.element('ruck_data', nest: () {
            builder.element('planned_date',
                nest: plannedRuck.plannedDate.toIso8601String());
            builder.element('duration',
                nest: plannedRuck.projectedDurationMinutes?.toString() ?? '0');
            builder.element('difficulty',
                nest: plannedRuck.route?.trailDifficulty ?? 'moderate');
            if (plannedRuck.targetWeight != null) {
              builder.element('target_weight',
                  nest: plannedRuck.targetWeight.toString());
            }
          });
        });
      });

      // Use the same track generation as route
      final routeContent = _generateRouteGPX(route);
      final routeDoc = XmlDocument.parse(routeContent);
      final trackElement = routeDoc.findAllElements('trk').first;
      builder.element('trk', nest: () {
        builder.element('name',
            nest: plannedRuck.route?.name ?? 'Planned Ruck');
        builder.element('desc',
            nest:
                plannedRuck.notes ?? route.description ?? 'Planned ruck route');

        // Copy track segments
        for (final trkSeg in trackElement.findElements('trkseg')) {
          builder.element('trkseg', nest: () {
            for (final trkPt in trkSeg.findElements('trkpt')) {
              builder.element('trkpt', nest: () {
                builder.attribute('lat', trkPt.getAttribute('lat')!);
                builder.attribute('lon', trkPt.getAttribute('lon')!);

                for (final child in trkPt.children.whereType<XmlElement>()) {
                  builder.element(child.name.local, nest: child.innerText);
                }
              });
            }
          });
        }
      });
    });

    return builder.buildDocument().toXmlString(pretty: true);
  }

  /// 📊 **Generate Multiple Routes GPX Content**
  String _generateMultipleRoutesGPX(List<Route> routes) {
    final builder = XmlBuilder();

    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element('gpx', nest: () {
      builder.attribute('version', '1.1');
      builder.attribute('creator', 'Ruck! - Go Ruck Yourself');
      builder.attribute('xmlns', _gpxNamespace);

      // Metadata
      builder.element('metadata', nest: () {
        builder.element('name', nest: 'Route Collection');
        builder.element('desc', nest: 'Multiple routes exported from Ruck!');
        builder.element('time', nest: DateTime.now().toUtc().toIso8601String());
      });

      // Add each route as a separate track
      for (final route in routes) {
        final routeContent = _generateRouteGPX(route);
        final routeDoc = XmlDocument.parse(routeContent);

        // Copy waypoints
        for (final wpt in routeDoc.findAllElements('wpt')) {
          builder.element('wpt', nest: () {
            builder.attribute('lat', wpt.getAttribute('lat')!);
            builder.attribute('lon', wpt.getAttribute('lon')!);

            for (final child in wpt.children.whereType<XmlElement>()) {
              builder.element(child.name.local, nest: child.innerText);
            }
          });
        }

        // Copy track
        for (final trk in routeDoc.findAllElements('trk')) {
          builder.element('trk', nest: () {
            for (final child in trk.children.whereType<XmlElement>()) {
              if (child.name.local == 'trkseg') {
                builder.element('trkseg', nest: () {
                  for (final trkPt in child.findElements('trkpt')) {
                    builder.element('trkpt', nest: () {
                      builder.attribute('lat', trkPt.getAttribute('lat')!);
                      builder.attribute('lon', trkPt.getAttribute('lon')!);

                      for (final ptChild
                          in trkPt.children.whereType<XmlElement>()) {
                        builder.element(ptChild.name.local,
                            nest: ptChild.innerText);
                      }
                    });
                  }
                });
              } else {
                builder.element(child.name.local, nest: child.innerText);
              }
            }
          });
        }
      }
    });

    return builder.buildDocument().toXmlString(pretty: true);
  }

  /// 💾 **Write GPX Content to File**
  Future<File> _writeGPXFile(String gpxContent, String fileName) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsString(gpxContent);
    return file;
  }

  /// 📐 **Calculate Route Bounds**
  Map<String, double> _calculateBounds(List<Map<String, double>> coordinates) {
    if (coordinates.isEmpty) {
      return {'minLat': 0.0, 'maxLat': 0.0, 'minLon': 0.0, 'maxLon': 0.0};
    }

    double minLat = coordinates.first['lat']!;
    double maxLat = coordinates.first['lat']!;
    double minLon = coordinates.first['lon']!;
    double maxLon = coordinates.first['lon']!;

    for (final coord in coordinates) {
      minLat = math.min(minLat, coord['lat']!);
      maxLat = math.max(maxLat, coord['lat']!);
      minLon = math.min(minLon, coord['lon']!);
      maxLon = math.max(maxLon, coord['lon']!);
    }

    return {
      'minLat': minLat,
      'maxLat': maxLat,
      'minLon': minLon,
      'maxLon': maxLon,
    };
  }

  /// 🎯 **Quick Export to Share**
  ///
  /// Export and get file for immediate sharing
  Future<String> exportForSharing(Route route) async {
    final file = await exportRouteToGPX(route);
    return file.path;
  }

  /// 📱 **Export to App Documents**
  ///
  /// Save to user-accessible documents folder
  Future<String> exportToDocuments(Route route, {String? customName}) async {
    final directory = await getApplicationDocumentsDirectory();
    final fileName = customName ??
        '${route.name}_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.gpx';
    final file = File('${directory.path}/$fileName');

    final gpxContent = _generateRouteGPX(route);
    await file.writeAsString(gpxContent);

    return file.path;
  }
}
