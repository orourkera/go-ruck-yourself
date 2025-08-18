import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'dart:math' as math;

/// Service for getting location context to enhance AI messages
class LocationContextService {
  static const String _nominatimUrl = 'https://nominatim.openstreetmap.org/reverse';
  static const Duration _timeout = Duration(seconds: 5);
  
  // Cache to avoid repeated API calls for similar locations
  static final Map<String, LocationContext> _cache = {};
  static const double _cacheDistanceMeters = 500; // Cache hits within 500m

  /// Gets location context including city, landmarks, terrain
  Future<LocationContext?> getLocationContext(double latitude, double longitude) async {
    try {
      // Check cache first
      final cacheKey = _getCacheKey(latitude, longitude);
      final cached = _getCachedContext(latitude, longitude);
      if (cached != null) {
        AppLogger.info('[LOCATION] Using cached context for $cacheKey');
        return cached;
      }

      AppLogger.info('[LOCATION] Fetching context for ($latitude, $longitude)');

      final url = Uri.parse(_nominatimUrl).replace(queryParameters: {
        'format': 'json',
        'lat': latitude.toString(),
        'lon': longitude.toString(),
        'addressdetails': '1',
        'extratags': '1',
        'namedetails': '1',
      });

      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'RuckingApp/1.0 (Fitness App)',
        },
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final context = _parseLocationData(data, latitude, longitude);
        
        // Cache the result
        _cache[cacheKey] = context;
        
        AppLogger.info('[LOCATION] Context: ${context.city}, ${context.terrain}');
        return context;
      } else {
        AppLogger.warning('[LOCATION] API error: ${response.statusCode}');
        return null;
      }

    } on SocketException {
      AppLogger.warning('[LOCATION] No internet connection for location context');
      return null;
    } on TimeoutException {
      AppLogger.warning('[LOCATION] Request timed out');
      return null;
    } catch (e) {
      AppLogger.error('[LOCATION] Failed to get location context: $e');
      return null;
    }
  }

  LocationContext _parseLocationData(Map<String, dynamic> data, double lat, double lon) {
    final address = data['address'] as Map<String, dynamic>? ?? {};
    final extratags = data['extratags'] as Map<String, dynamic>? ?? {};
    final category = data['category'] as String?;
    final type = data['type'] as String?;

    // Extract location components
    final city = _extractCity(address);
    final state = _extractState(address);
    final country = address['country'] as String? ?? 'Unknown';
    final terrain = _determineTerrain(category, type, extratags);
    final landmark = _extractLandmark(data);

    return LocationContext(
      latitude: lat,
      longitude: lon,
      city: city,
      state: state,
      country: country,
      terrain: terrain,
      landmark: landmark,
      rawData: data,
    );
  }

  String _extractCity(Map<String, dynamic> address) {
    // Try multiple possible city fields
    return address['city'] as String? ??
           address['town'] as String? ??
           address['village'] as String? ??
           address['hamlet'] as String? ??
           address['suburb'] as String? ??
           'Unknown Location';
  }

  String? _extractState(Map<String, dynamic> address) {
    return address['state'] as String? ??
           address['province'] as String? ??
           address['region'] as String?;
  }

  String _determineTerrain(String? category, String? type, Map<String, dynamic> extratags) {
    // Determine terrain type from OSM data
    if (category == 'natural') {
      switch (type) {
        case 'peak':
        case 'mountain':
          return 'mountain';
        case 'forest':
        case 'wood':
          return 'forest';
        case 'beach':
          return 'beach';
        case 'water':
          return 'waterside';
        default:
          return 'natural';
      }
    }
    
    if (category == 'landuse') {
      switch (type) {
        case 'forest':
          return 'forest';
        case 'farmland':
        case 'agricultural':
          return 'rural';
        case 'residential':
          return 'urban';
        default:
          return 'mixed';
      }
    }

    // Check elevation tags for hills/mountains
    final elevation = extratags['ele'];
    if (elevation != null) {
      final meters = double.tryParse(elevation.toString());
      if (meters != null && meters > 500) {
        return 'hills';
      }
    }

    return 'urban'; // Default assumption
  }

  String? _extractLandmark(Map<String, dynamic> data) {
    final displayName = data['display_name'] as String?;
    if (displayName != null) {
      // Extract notable features from display name
      final parts = displayName.split(', ');
      for (final part in parts) {
        if (_isLandmark(part)) {
          return part;
        }
      }
    }
    return null;
  }

  bool _isLandmark(String name) {
    final landmarkKeywords = [
      'park', 'trail', 'mountain', 'hill', 'river', 'lake', 'beach',
      'forest', 'reserve', 'national', 'state park', 'creek', 'bridge'
    ];
    
    final lowerName = name.toLowerCase();
    return landmarkKeywords.any((keyword) => lowerName.contains(keyword));
  }

  String _getCacheKey(double lat, double lon) {
    // Round to reduce cache key variations
    final roundedLat = (lat * 1000).round() / 1000;
    final roundedLon = (lon * 1000).round() / 1000;
    return '${roundedLat},${roundedLon}';
  }

  LocationContext? _getCachedContext(double lat, double lon) {
    for (final entry in _cache.entries) {
      final cached = entry.value;
      final distance = _calculateDistance(lat, lon, cached.latitude, cached.longitude);
      if (distance < _cacheDistanceMeters) {
        return cached;
      }
    }
    return null;
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    // Simple distance calculation (good enough for caching)
    const double earthRadius = 6371000; // meters
    final dLat = (lat2 - lat1) * (3.14159 / 180);
    final dLon = (lon2 - lon1) * (3.14159 / 180);
    final a = (dLat / 2) * (dLat / 2) + (dLon / 2) * (dLon / 2);
    return earthRadius * 2 * math.sqrt((a).abs());
  }

  /// Clears location cache
  void clearCache() {
    _cache.clear();
    AppLogger.info('[LOCATION] Context cache cleared');
  }
}

class LocationContext {
  final double latitude;
  final double longitude;
  final String city;
  final String? state;
  final String country;
  final String terrain; // urban, forest, mountain, beach, rural, etc.
  final String? landmark; // nearby notable feature
  final Map<String, dynamic> rawData;

  LocationContext({
    required this.latitude,
    required this.longitude,
    required this.city,
    this.state,
    required this.country,
    required this.terrain,
    this.landmark,
    required this.rawData,
  });

  /// Gets a human-readable description for AI context
  String get description {
    final parts = <String>[city];
    if (state != null) parts.add(state!);
    if (landmark != null) parts.add('near $landmark');
    parts.add('($terrain terrain)');
    return parts.join(', ');
  }

  @override
  String toString() => description;
}
