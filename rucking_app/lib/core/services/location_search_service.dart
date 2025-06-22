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
      
      // Try multiple search strategies for better business name support
      List<Location> locations = [];
      
      // Strategy 1: Direct search for the query
      try {
        locations = await locationFromAddress(query);
        print('LocationSearchService: Direct search found ${locations.length} locations');
      } catch (e) {
        print('LocationSearchService: Direct search failed: $e');
      }
      
      // Strategy 2: If no results and query doesn't contain city/state, 
      // try searching with common location suffixes for businesses
      if (locations.isEmpty && !query.contains(',') && !query.contains(' ')) {
        final businessSearchTerms = [
          '$query restaurant',
          '$query store',
          '$query shop',
          '$query cafe',
          '$query gym',
          '$query park',
        ];
        
        for (String searchTerm in businessSearchTerms) {
          try {
            final results = await locationFromAddress(searchTerm);
            if (results.isNotEmpty) {
              locations.addAll(results);
              print('LocationSearchService: Business search "$searchTerm" found ${results.length} locations');
              break; // Use first successful business search
            }
          } catch (e) {
            // Continue to next search term
          }
        }
      }
      
      if (locations.isEmpty) return [];
      
      // Get detailed placemark information for the first few results
      List<LocationSearchResult> results = [];
      
      final Set<String> _addedSignatures = {}; // prevent duplicates

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

            // Helper to add a result if not already present
            void addResult(String disp, String addr) {
              final signature = '$disp|${location.latitude}|${location.longitude}';
              if (_addedSignatures.contains(signature)) return;
              _addedSignatures.add(signature);
              results.add(LocationSearchResult(
                displayName: disp,
                address: addr,
                latitude: location.latitude,
                longitude: location.longitude,
                city: placemark.locality,
                state: placemark.administrativeArea,
                country: placemark.country,
              ));
            }
            
            // 1. Full address / landmark
            final fullDisplay = _buildDisplayName(placemark, query);
            final fullAddress = _buildAddress(placemark);
            addResult(fullDisplay, fullAddress);

            // 2. City / locality level
            if (placemark.locality != null && placemark.locality!.isNotEmpty) {
              addResult(placemark.locality!, placemark.administrativeArea ?? placemark.country ?? '');
            }

            // 3. Administrative area (state/province) level
            if (placemark.administrativeArea != null && placemark.administrativeArea!.isNotEmpty) {
              addResult(placemark.administrativeArea!, placemark.country ?? '');
            }

            // 4. Country level (only include if query length > 3 to avoid huge list)
            if (placemark.country != null && placemark.country!.isNotEmpty && query.length > 3) {
              addResult(placemark.country!, placemark.country!);
            }
            
            print('LocationSearchService: Added multi-precision results for ${placemark.locality ?? placemark.name}');
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
  
  String _buildDisplayName(Placemark placemark, [String? originalQuery]) {
    List<String> parts = [];
    
    // If this looks like a business search, prioritize the business name
    if (originalQuery != null && placemark.name != null && placemark.name!.isNotEmpty) {
      // Check if the placemark name seems to match the business search intent
      final name = placemark.name!.toLowerCase();
      final query = originalQuery.toLowerCase();
      
      // If the name contains business-related terms or matches the query, use it prominently
      if (name.contains(query) || 
          name.contains('restaurant') || 
          name.contains('store') || 
          name.contains('shop') || 
          name.contains('cafe') || 
          name.contains('coffee') ||
          name.contains('gym') || 
          name.contains('fitness') ||
          name.contains('park') ||
          name.contains('hotel') ||
          name.contains('mall') ||
          name.contains('center')) {
        return placemark.name!;
      }
    }
    
    // Default display name building logic
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
