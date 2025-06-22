import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class GooglePlacesConfig {
  // Get API key from environment variables
  // Add your key to .env file as: GOOGLE_PLACES_API_KEY=your_actual_key_here
  static String get apiKey => dotenv.env['GOOGLE_PLACES_API_KEY'] ?? '';
  
  // Validate that API key is configured
  static bool get isConfigured => apiKey.isNotEmpty;
}

class LocationSearchResult {
  final String displayName;
  final String address;
  final double latitude;
  final double longitude;
  final String? city;
  final String? state;
  final String? country;
  final String? placeId;

  LocationSearchResult({
    required this.displayName,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.city,
    this.state,
    this.country,
    this.placeId,
  });

  @override
  String toString() => displayName;
}

class GooglePlacesService {
  static const String _baseUrl = 'https://maps.googleapis.com/maps/api/place';
  
  Timer? _debounceTimer;
  
  /// Search for places using Google Places Text Search API
  Future<List<LocationSearchResult>> searchLocations(String query) async {
    if (query.trim().isEmpty) return [];
    
    // Check if API key is configured
    if (!GooglePlacesConfig.isConfigured) {
      print('GooglePlacesService: API key not configured. Please add your Google Places API key.');
      return [];
    }
    
    try {
      print('GooglePlacesService: Searching for "$query"');
      
      // Use Google Places Text Search API for better business/landmark results
      final url = Uri.parse(
        '$_baseUrl/textsearch/json?query=${Uri.encodeComponent(query)}&key=${GooglePlacesConfig.apiKey}'
      );
      
      final response = await http.get(url);
      
      if (response.statusCode != 200) {
        print('GooglePlacesService: API error ${response.statusCode}: ${response.body}');
        return [];
      }
      
      final data = json.decode(response.body);
      
      if (data['status'] != 'OK' && data['status'] != 'ZERO_RESULTS') {
        print('GooglePlacesService: API status error: ${data['status']}');
        return [];
      }
      
      final List<dynamic> results = data['results'] ?? [];
      print('GooglePlacesService: Found ${results.length} results');
      
      List<LocationSearchResult> searchResults = [];
      
      for (var result in results.take(10)) { // Limit to 10 results
        try {
          final geometry = result['geometry'];
          final location = geometry['location'];
          final lat = location['lat']?.toDouble();
          final lng = location['lng']?.toDouble();
          
          if (lat == null || lng == null) continue;
          
          final name = result['name'] ?? '';
          final formattedAddress = result['formatted_address'] ?? '';
          final placeId = result['place_id'];
          
          // Extract city, state, country from address components
          String? city, state, country;
          final addressComponents = result['address_components'] as List<dynamic>?;
          
          if (addressComponents != null) {
            for (var component in addressComponents) {
              final types = List<String>.from(component['types'] ?? []);
              
              if (types.contains('locality')) {
                city = component['long_name'];
              } else if (types.contains('administrative_area_level_1')) {
                state = component['short_name'];
              } else if (types.contains('country')) {
                country = component['long_name'];
              }
            }
          }
          
          searchResults.add(LocationSearchResult(
            displayName: name.isNotEmpty ? name : formattedAddress,
            address: formattedAddress,
            latitude: lat,
            longitude: lng,
            city: city,
            state: state,
            country: country,
            placeId: placeId,
          ));
          
        } catch (e) {
          print('GooglePlacesService: Error processing result: $e');
          continue;
        }
      }
      
      print('GooglePlacesService: Returning ${searchResults.length} processed results');
      return searchResults;
      
    } catch (e) {
      print('GooglePlacesService: Search failed: $e');
      return [];
    }
  }
  
  /// Search with autocomplete using Google Places Autocomplete API
  Future<List<LocationSearchResult>> searchAutocomplete(String query) async {
    if (query.trim().isEmpty) return [];
    
    // Check if API key is configured
    if (!GooglePlacesConfig.isConfigured) {
      print('GooglePlacesService: API key not configured. Please add your Google Places API key.');
      return [];
    }
    
    try {
      print('GooglePlacesService: Autocomplete search for "$query"');
      
      final url = Uri.parse(
        '$_baseUrl/autocomplete/json?input=${Uri.encodeComponent(query)}&key=${GooglePlacesConfig.apiKey}'
      );
      
      final response = await http.get(url);
      
      if (response.statusCode != 200) {
        print('GooglePlacesService: Autocomplete API error ${response.statusCode}');
        return [];
      }
      
      final data = json.decode(response.body);
      
      if (data['status'] != 'OK' && data['status'] != 'ZERO_RESULTS') {
        print('GooglePlacesService: Autocomplete API status error: ${data['status']}');
        return [];
      }
      
      final List<dynamic> predictions = data['predictions'] ?? [];
      print('GooglePlacesService: Found ${predictions.length} autocomplete predictions');
      
      List<LocationSearchResult> results = [];
      
      // For autocomplete, we need to get place details for each prediction
      for (var prediction in predictions.take(5)) { // Limit to 5 for performance
        try {
          final placeId = prediction['place_id'];
          if (placeId == null) continue;
          
          final placeDetails = await _getPlaceDetails(placeId);
          if (placeDetails != null) {
            results.add(placeDetails);
          }
        } catch (e) {
          print('GooglePlacesService: Error getting place details: $e');
          continue;
        }
      }
      
      return results;
      
    } catch (e) {
      print('GooglePlacesService: Autocomplete search failed: $e');
      return [];
    }
  }
  
  /// Get detailed information about a place using Place Details API
  Future<LocationSearchResult?> _getPlaceDetails(String placeId) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/details/json?place_id=$placeId&fields=name,formatted_address,geometry,address_components&key=${GooglePlacesConfig.apiKey}'
      );
      
      final response = await http.get(url);
      
      if (response.statusCode != 200) {
        return null;
      }
      
      final data = json.decode(response.body);
      
      if (data['status'] != 'OK') {
        return null;
      }
      
      final result = data['result'];
      final geometry = result['geometry'];
      final location = geometry['location'];
      final lat = location['lat']?.toDouble();
      final lng = location['lng']?.toDouble();
      
      if (lat == null || lng == null) return null;
      
      final name = result['name'] ?? '';
      final formattedAddress = result['formatted_address'] ?? '';
      
      // Extract city, state, country from address components
      String? city, state, country;
      final addressComponents = result['address_components'] as List<dynamic>?;
      
      if (addressComponents != null) {
        for (var component in addressComponents) {
          final types = List<String>.from(component['types'] ?? []);
          
          if (types.contains('locality')) {
            city = component['long_name'];
          } else if (types.contains('administrative_area_level_1')) {
            state = component['short_name'];
          } else if (types.contains('country')) {
            country = component['long_name'];
          }
        }
      }
      
      return LocationSearchResult(
        displayName: name.isNotEmpty ? name : formattedAddress,
        address: formattedAddress,
        latitude: lat,
        longitude: lng,
        city: city,
        state: state,
        country: country,
        placeId: placeId,
      );
      
    } catch (e) {
      print('GooglePlacesService: Error getting place details: $e');
      return null;
    }
  }
  
  /// Search with debouncing to avoid too many API calls
  Future<List<LocationSearchResult>> searchWithDebounce(
    String query,
    Duration delay, {
    bool useAutocomplete = false,
  }) async {
    final completer = Completer<List<LocationSearchResult>>();
    
    _debounceTimer?.cancel();
    _debounceTimer = Timer(delay, () async {
      try {
        final results = useAutocomplete 
            ? await searchAutocomplete(query)
            : await searchLocations(query);
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
  
  void dispose() {
    _debounceTimer?.cancel();
  }
}
