import 'package:geolocator/geolocator.dart';

/// Utility class for validating location data
class LocationValidator {
  /// Check if a position is valid
  static bool isValidPosition(Position position) {
    return isWithinBounds(position.latitude, position.longitude) &&
        position.accuracy > 0 &&
        position.accuracy < 100; // Reasonable accuracy threshold
  }

  /// Check if coordinates are within valid bounds
  static bool isWithinBounds(double latitude, double longitude) {
    return latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180;
  }

  /// Check if location is reasonable (not at null island, etc)
  static bool isReasonableLocation(double latitude, double longitude) {
    // Check if not at null island (0,0)
    if (latitude == 0.0 && longitude == 0.0) {
      return false;
    }
    
    // Check if within valid bounds
    return isWithinBounds(latitude, longitude);
  }
}
