import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/services/weather_service.dart';
import 'package:rucking_app/core/models/weather.dart';
import 'dart:math' as math;

/// Service for getting location context to enhance AI messages
class LocationContextService {
  static const String _nominatimUrl = 'https://nominatim.openstreetmap.org/reverse';
  static const Duration _timeout = Duration(seconds: 5);
  
  // Cache to avoid repeated API calls for similar locations
  static final Map<String, LocationContext> _cache = {};
  static const double _cacheDistanceMeters = 500; // Cache hits within 500m
  
  final WeatherService _weatherService;
  
  LocationContextService({WeatherService? weatherService}) 
      : _weatherService = weatherService ?? WeatherService();

  /// Gets location context including city, landmarks, terrain
  Future<LocationContext?> getLocationContext(double latitude, double longitude) async {
    try {
      AppLogger.warning('[LOCATION_DEBUG] === Starting getLocationContext ===');
      AppLogger.warning('[LOCATION_DEBUG] Coords: $latitude, $longitude');
      
      // Check cache first
      final cached = _getCachedContext(latitude, longitude);
      if (cached != null) {
        AppLogger.info('[LOCATION] Using cached context for ${cached.city}');
        return cached;
      }

      final cacheKey = _getCacheKey(latitude, longitude);
      AppLogger.warning('[LOCATION_DEBUG] Cache key: $cacheKey');
      AppLogger.info('[LOCATION] Fetching context for $latitude, $longitude');

      final url = Uri.parse(_nominatimUrl).replace(queryParameters: {
        'format': 'json',
        'lat': latitude.toString(),
        'lon': longitude.toString(),
        'addressdetails': '1',
        'extratags': '1',
        'namedetails': '1',
      });
      
      AppLogger.warning('[LOCATION_DEBUG] Request URL: $url');

      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'RuckingApp/1.0 (Fitness App)',
        },
      ).timeout(_timeout);

      AppLogger.warning('[LOCATION_DEBUG] Response status: ${response.statusCode}');
      AppLogger.warning('[LOCATION_DEBUG] Response body length: ${response.body.length}');

      if (response.statusCode == 200) {
        AppLogger.warning('[LOCATION_DEBUG] About to parse JSON...');
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        AppLogger.warning('[LOCATION_DEBUG] JSON parsed successfully, calling _parseLocationData...');
        final context = _parseLocationData(data, latitude, longitude);
        AppLogger.warning('[LOCATION_DEBUG] _parseLocationData completed successfully');
        
        // Try to fetch weather data
        try {
          AppLogger.info('[LOCATION] Fetching weather data for $latitude, $longitude');
          final weather = await _weatherService.getWeatherForecast(
            latitude: latitude,
            longitude: longitude,
          );
          context._weather = weather;
          AppLogger.info('[LOCATION] Weather data added to context');
        } catch (e) {
          AppLogger.warning('[LOCATION] Failed to fetch weather data: $e');
          // Continue without weather data
        }
        
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
    try {
      AppLogger.info('[LOCATION_DEBUG] Raw data structure: ${data.runtimeType}');
      AppLogger.info('[LOCATION_DEBUG] Raw data keys: ${data.keys.toList()}');
      
      final address = data['address'] as Map<String, dynamic>? ?? {};
      final extratags = data['extratags'] as Map<String, dynamic>? ?? {};
      final category = data['category'] as String?;
      final type = data['type'] as String?;

      AppLogger.info('[LOCATION_DEBUG] Address structure: ${address.runtimeType}');
      AppLogger.info('[LOCATION_DEBUG] Address keys: ${address.keys.toList()}');

      // Extract location components with error handling
      final city = _extractCity(address);
      final state = _extractState(address);
      final country = _extractCountry(address);
      final terrain = _determineTerrain(category, type, extratags);
      final landmark = _extractLandmark(data);

      AppLogger.info('[LOCATION_DEBUG] Extracted values - city: $city, state: $state, country: $country, terrain: $terrain, landmark: $landmark');

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
    } catch (e) {
      AppLogger.error('[LOCATION_DEBUG] Error parsing location data: $e');
      AppLogger.error('[LOCATION_DEBUG] Raw data that caused error: $data');
      rethrow;
    }
  }

  String _extractCity(Map<String, dynamic> address) {
    // Try multiple possible city fields with defensive type checking
    try {
      final cityFields = ['city', 'town', 'village', 'hamlet', 'suburb'];
      for (final field in cityFields) {
        final value = address[field];
        if (value != null && value is String && value.isNotEmpty) {
          return value;
        }
      }
      return 'Unknown Location';
    } catch (e) {
      AppLogger.error('[LOCATION] Error extracting city: $e');
      return 'Unknown Location';
    }
  }

  String? _extractState(Map<String, dynamic> address) {
    try {
      final stateFields = ['state', 'province', 'region'];
      for (final field in stateFields) {
        final value = address[field];
        if (value != null && value is String && value.isNotEmpty) {
          return value;
        }
      }
      return null;
    } catch (e) {
      AppLogger.error('[LOCATION] Error extracting state: $e');
      return null;
    }
  }

  String _extractCountry(Map<String, dynamic> address) {
    try {
      final value = address['country'];
      if (value != null && value is String && value.isNotEmpty) {
        return value;
      }
      return 'Unknown';
    } catch (e) {
      AppLogger.error('[LOCATION] Error extracting country: $e');
      return 'Unknown';
    }
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
  Weather? _weather; // Weather data for the location

  LocationContext({
    required this.latitude,
    required this.longitude,
    required this.city,
    this.state,
    required this.country,
    required this.terrain,
    this.landmark,
    required this.rawData,
    Weather? weather,
  }) : _weather = weather;

  /// Gets weather data if available
  Weather? get weather => _weather;

  /// Gets a human-readable description for AI context
  String get description {
    final parts = <String>[city];
    if (state != null) parts.add(state!);
    if (landmark != null) parts.add('near $landmark');
    parts.add('($terrain terrain)');
    
    // Add weather info if available
    if (_weather?.currentWeather != null) {
      final current = _weather!.currentWeather!;
      final temp = current.temperature?.round();
      final condition = current.conditionCode?.description;
      
      if (temp != null && condition != null) {
        parts.add('${temp}°F, $condition');
      } else if (temp != null) {
        parts.add('${temp}°F');
      } else if (condition != null) {
        parts.add(condition);
      }
    }
    
    return parts.join(', ');
  }

  /// Gets weather condition for AI context
  String? get weatherCondition {
    return _weather?.currentWeather?.conditionCode?.description;
  }

  /// Gets temperature for AI context  
  int? get temperature {
    return _weather?.currentWeather?.temperature?.round();
  }

  @override
  String toString() => description;
}
