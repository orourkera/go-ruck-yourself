class GooglePlacesConfig {
  // TODO: Add your Google Places API key here
  // Get one from: https://console.cloud.google.com/apis/library/places-backend.googleapis.com
  static const String apiKey = 'YOUR_GOOGLE_PLACES_API_KEY';
  
  // Validate that API key is configured
  static bool get isConfigured => apiKey != 'YOUR_GOOGLE_PLACES_API_KEY' && apiKey.isNotEmpty;
}
