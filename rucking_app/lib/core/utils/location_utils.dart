import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'dart:async';

/// Utility class for handling location-related operations
class LocationUtils {
  static final Map<String, String> _locationCache = {};

  /// Get a readable location name from coordinates
  /// Returns the location in format of "[Park/Monument] [City], [State]"
  /// If unable to determine location, returns "Unknown Location"
  static Future<String> getLocationName(List<dynamic>? locationPoints) async {
    if (locationPoints == null || locationPoints.isEmpty) {
      return "Unknown Location";
    }
    
    try {
      // Use the midpoint of the route as the reference point
      final midIndex = locationPoints.length ~/ 2;
      final midPoint = locationPoints[midIndex];
      
      double? lat;
      double? lng;
      
      // Extract coordinates based on data format
      if (midPoint is Map) {
        lat = _parseCoord(midPoint['latitude'] ?? midPoint['lat']);
        lng = _parseCoord(midPoint['longitude'] ?? midPoint['lng'] ?? midPoint['lon']);
      } else if (midPoint is List && midPoint.length >= 2) {
        lat = _parseCoord(midPoint[0]);
        lng = _parseCoord(midPoint[1]);
      }
      
      if (lat == null || lng == null) {
        return "Unknown Location";
      }
      
      return await getLocationNameFromLatLng(LatLng(lat, lng));
    } catch (e) {
      print('Error getting location name: $e');
      return "Unknown Location";
    }
  }
  
  /// Get a readable location name from a LatLng point
  static Future<String> getLocationNameFromLatLng(LatLng point) async {
    final cacheKey = '${point.latitude.toStringAsFixed(4)},${point.longitude.toStringAsFixed(4)}';
    
    // Check cache first to avoid unnecessary API calls
    if (_locationCache.containsKey(cacheKey)) {
      return _locationCache[cacheKey]!;
    }
    
    try {
      // OpenStreetMap Nominatim API for reverse geocoding
      final response = await http.get(
        Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=${point.latitude}&lon=${point.longitude}&zoom=18&addressdetails=1'),
        headers: {'User-Agent': 'RuckingApp/1.0'},
      ).timeout(const Duration(seconds: 3));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        String locationName = _formatLocationFromResponse(data);
        
        // Cache the result
        _locationCache[cacheKey] = locationName;
        return locationName;
      }
    } catch (e) {
      print('Error in reverse geocoding: $e');
    }
    
    return "Unknown Location";
  }
  
  /// Helper to format location data prioritizing parks/monuments, then city, state
  static String _formatLocationFromResponse(Map<String, dynamic> data) {
    try {
      final address = data['address'];
      if (address == null) return "Unknown Location";
      
      // Try to find the most relevant location components
      String? park = address['park'] ?? 
                     address['national_park'] ?? 
                     address['protected_area'] ?? 
                     address['monument'];
                     
      String? tourism = address['tourism'];
      String? attraction = address['attraction'];
      String? city = address['city'] ?? 
                     address['town'] ?? 
                     address['village'] ?? 
                     address['hamlet'];
                     
      String? county = address['county'];
      String? state = address['state'];
      String? country = address['country_code']?.toUpperCase();
      
      // Build the location string prioritizing landmarks, then city, state
      List<String> locationParts = [];
      
      // First priority: Parks, monuments, tourist attractions
      if (park != null) {
        locationParts.add(park);
      } else if (tourism != null) {
        locationParts.add(tourism);
      } else if (attraction != null) {
        locationParts.add(attraction);
      }
      
      // Second priority: City/State (or international equivalent)
      List<String> civilianParts = [];
      if (city != null) civilianParts.add(city);
      if (state != null) civilianParts.add(state);
      if (civilianParts.isEmpty && county != null) civilianParts.add(county);
      
      if (civilianParts.isNotEmpty) {
        locationParts.add(civilianParts.join(", "));
      }
      
      // Fallback: Use country code if nothing else is available
      if (locationParts.isEmpty && country != null) {
        return country;
      }
      
      return locationParts.isEmpty ? "Unknown Location" : locationParts.join(" • ");
    } catch (e) {
      print('Error formatting location: $e');
      return "Unknown Location";
    }
  }

  /// Helper to parse coordinates from various formats
  static double? _parseCoord(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}
