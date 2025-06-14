import 'package:geocoding/geocoding.dart';
import 'dart:async';

class LocationSearchResult {
  final String displayName;
  final String address;
  final double latitude;
  final double longitude;
  final String? city;
  final String? state;
  final String? country;

  LocationSearchResult({
    required this.displayName,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.city,
    this.state,
    this.country,
  });

  @override
  String toString() => displayName;
}

class LocationSearchService {
  // Debounce timer to avoid too many API calls
  Timer? _debounceTimer;
  
  /// Search for locations based on query string
  Future<List<LocationSearchResult>> searchLocations(String query) async {
    if (query.trim().isEmpty) return [];
    
    try {
      print('LocationSearchService: Searching for "$query"');
      
      // Use geocoding package to search for locations
      List<Location> locations = await locationFromAddress(query);
      print('LocationSearchService: Found ${locations.length} locations');
      
      if (locations.isEmpty) return [];
      
      // Get detailed placemark information for the first few results
      List<LocationSearchResult> results = [];
      
      for (int i = 0; i < locations.length && i < 5; i++) {
        final location = locations[i];
        print('LocationSearchService: Processing location ${i + 1}: ${location.latitude}, ${location.longitude}');
        
        // Validate coordinates before processing
        if (!_isValidCoordinate(location.latitude) || !_isValidCoordinate(location.longitude)) {
          print('LocationSearchService: Invalid coordinates, skipping');
          continue; // Skip invalid coordinates
        }
        
        try {
          // Get placemark details for this location
          List<Placemark> placemarks = await placemarkFromCoordinates(
            location.latitude,
            location.longitude,
          );
          
          if (placemarks.isNotEmpty) {
            final placemark = placemarks.first;
            
            // Build display name
            String displayName = _buildDisplayName(placemark);
            String address = _buildAddress(placemark);
            
            print('LocationSearchService: Created result: $displayName');
            
            results.add(LocationSearchResult(
              displayName: displayName,
              address: address,
              latitude: location.latitude,
              longitude: location.longitude,
              city: placemark.locality,
              state: placemark.administrativeArea,
              country: placemark.country,
            ));
          }
        } catch (e) {
          print('LocationSearchService: Error getting placemark: $e');
          // If reverse geocoding fails, still add basic location with validated coordinates
          results.add(LocationSearchResult(
            displayName: query,
            address: query,
            latitude: location.latitude,
            longitude: location.longitude,
          ));
        }
      }
      
      print('LocationSearchService: Returning ${results.length} results');
      return results;
    } catch (e) {
      print('LocationSearchService: Search failed: $e');
      // If geocoding fails, return empty list
      return [];
    }
  }
  
  /// Search with debouncing to avoid too many API calls
  Future<List<LocationSearchResult>> searchWithDebounce(
    String query,
    Duration delay,
  ) async {
    final completer = Completer<List<LocationSearchResult>>();
    
    _debounceTimer?.cancel();
    _debounceTimer = Timer(delay, () async {
      try {
        final results = await searchLocations(query);
        if (!completer.isCompleted) {
          completer.complete(results);
        }
      } catch (e) {
        if (!completer.isCompleted) {
          completer.complete([]);
        }
      }
    });
    
    return completer.future;
  }
  
  bool _isValidCoordinate(double coordinate) {
    return coordinate.isFinite && coordinate >= -180 && coordinate <= 180;
  }
  
  String _buildDisplayName(Placemark placemark) {
    List<String> parts = [];
    
    // Add landmark/name if available
    if (placemark.name != null && placemark.name!.isNotEmpty) {
      parts.add(placemark.name!);
    }
    
    // Add locality (city)
    if (placemark.locality != null && placemark.locality!.isNotEmpty) {
      parts.add(placemark.locality!);
    }
    
    // Add administrative area (state/province)
    if (placemark.administrativeArea != null && 
        placemark.administrativeArea!.isNotEmpty) {
      parts.add(placemark.administrativeArea!);
    }
    
    // Add country if no other info
    if (parts.isEmpty && placemark.country != null) {
      parts.add(placemark.country!);
    }
    
    return parts.join(', ');
  }
  
  String _buildAddress(Placemark placemark) {
    List<String> parts = [];
    
    // Add street info
    if (placemark.street != null && placemark.street!.isNotEmpty) {
      parts.add(placemark.street!);
    }
    
    // Add locality
    if (placemark.locality != null && placemark.locality!.isNotEmpty) {
      parts.add(placemark.locality!);
    }
    
    // Add administrative area
    if (placemark.administrativeArea != null && 
        placemark.administrativeArea!.isNotEmpty) {
      parts.add(placemark.administrativeArea!);
    }
    
    // Add postal code
    if (placemark.postalCode != null && placemark.postalCode!.isNotEmpty) {
      parts.add(placemark.postalCode!);
    }
    
    // Add country
    if (placemark.country != null && placemark.country!.isNotEmpty) {
      parts.add(placemark.country!);
    }
    
    return parts.join(', ');
  }
  
  void dispose() {
    _debounceTimer?.cancel();
  }
}
