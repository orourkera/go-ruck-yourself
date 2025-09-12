import '../models/weather.dart';
import '../utils/app_logger.dart';
import 'api_client.dart';
import 'service_locator.dart';

/// Service for fetching weather data from backend/WeatherKit
class WeatherService {
  final ApiClient _apiClient;

  WeatherService({ApiClient? apiClient})
      : _apiClient = apiClient ?? getIt<ApiClient>();

  /// Get weather forecast for a location on a specific date
  ///
  /// [latitude] and [longitude] specify the location
  /// [date] is the date for the forecast (defaults to now)
  /// [datasets] specifies which weather data to include
  Future<Weather?> getWeatherForecast({
    required double latitude,
    required double longitude,
    DateTime? date,
    List<String> datasets = const [
      'currentWeather',
      'hourlyForecast',
      'dailyForecast'
    ],
  }) async {
    try {
      final targetDate = date ?? DateTime.now();

      // Create query parameters
      final queryParams = {
        'latitude': latitude.toString(),
        'longitude': longitude.toString(),
        'date': targetDate.toIso8601String(),
        'datasets': datasets.join(','),
      };

      AppLogger.info(
        'Fetching weather for location: $latitude, $longitude on ${targetDate.toIso8601String()}',
      );

      final responseData =
          await _apiClient.get('/weather', queryParams: queryParams);

      final weatherData =
          Weather.fromJson(responseData as Map<String, dynamic>);
      AppLogger.info('Successfully fetched weather data');
      return weatherData;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Error fetching weather data',
        exception: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Get current weather conditions for a location
  Future<CurrentWeather?> getCurrentWeather({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final weather = await getWeatherForecast(
        latitude: latitude,
        longitude: longitude,
        datasets: ['currentWeather'],
      );

      return weather?.currentWeather;
    } catch (e) {
      AppLogger.error('Error fetching current weather: $e');
      return null;
    }
  }

  /// Get weather forecast for a planned ruck
  /// Uses the route's start coordinates and planned date
  Future<Weather?> getWeatherForPlannedRuck({
    required double startLatitude,
    required double startLongitude,
    required DateTime plannedDate,
  }) async {
    try {
      // Get weather for the planned date
      final weather = await getWeatherForecast(
        latitude: startLatitude,
        longitude: startLongitude,
        date: plannedDate,
      );

      if (weather != null) {
        AppLogger.info('Successfully fetched weather for planned ruck');
      } else {
        AppLogger.warning('No weather data available for planned ruck');
      }

      return weather;
    } catch (e) {
      AppLogger.error('Error fetching weather for planned ruck: $e');
      return null;
    }
  }

  /// Check if weather conditions are suitable for outdoor activities
  /// Returns a fitness score from 0.0 (terrible) to 1.0 (perfect)
  double getActivityFitnessScore(CurrentWeather weather) {
    double score = 1.0;

    // Temperature factor (optimal range: 15-25°C / 59-77°F)
    if (weather.temperature != null) {
      final temp = weather.temperature!;
      if (temp < 0 || temp > 35) {
        score *= 0.3; // Very poor conditions
      } else if (temp < 5 || temp > 30) {
        score *= 0.6; // Poor conditions
      } else if (temp < 10 || temp > 25) {
        score *= 0.8; // Fair conditions
      }
      // Optimal range (15-25°C) keeps score at 1.0
    }

    // Precipitation factor based on condition code
    final conditionCode = weather.conditionCode ?? 800;
    if (_isStormyWeather(conditionCode)) {
      score *=
          0.2; // Very poor for outdoor activity (thunderstorms, heavy rain)
    } else if (_isRainyWeather(conditionCode)) {
      score *= 0.5; // Poor but manageable (light rain, drizzle)
    } else if (_isSnowyWeather(conditionCode)) {
      score *= 0.4; // Challenging conditions
    }

    // Wind factor
    if (weather.windSpeed != null) {
      final windSpeed = weather.windSpeed!;
      if (windSpeed > 50) {
        score *= 0.3; // Very windy
      } else if (windSpeed > 30) {
        score *= 0.7; // Windy
      }
    }

    // UV Index factor (for daytime activities)
    if (weather.uvIndex != null) {
      final uvIndex = weather.uvIndex!;
      if (uvIndex > 8) {
        score *= 0.8; // High UV - need protection
      }
    }

    // Visibility factor
    if (weather.visibility != null) {
      final visibility = weather.visibility!;
      if (visibility < 1.0) {
        // visibility is now in km, so < 1km is poor
        score *= 0.5; // Poor visibility
      } else if (visibility < 5.0) {
        // < 5km is reduced visibility
        score *= 0.8; // Reduced visibility
      }
    }

    return score.clamp(0.0, 1.0);
  }

  /// Get activity recommendation based on weather conditions
  String getActivityRecommendation(CurrentWeather weather) {
    final score = getActivityFitnessScore(weather);

    if (score >= 0.8) {
      return 'Perfect conditions for outdoor activity!';
    } else if (score >= 0.6) {
      return 'Good conditions with minor considerations.';
    } else if (score >= 0.4) {
      return 'Fair conditions - check weather details.';
    } else if (score >= 0.2) {
      return 'Challenging conditions - consider rescheduling.';
    } else {
      return 'Poor conditions - indoor alternative recommended.';
    }
  }

  /// Check if condition code represents stormy weather (thunderstorms, heavy rain)
  bool _isStormyWeather(int conditionCode) {
    return (conditionCode >= 200 && conditionCode <= 232) || // Thunderstorms
        (conditionCode >= 520 && conditionCode <= 531); // Heavy rain/showers
  }

  /// Check if condition code represents rainy weather (light rain, drizzle)
  bool _isRainyWeather(int conditionCode) {
    return (conditionCode >= 300 && conditionCode <= 321) || // Drizzle
        (conditionCode >= 500 &&
            conditionCode <= 519); // Light to moderate rain
  }

  /// Check if condition code represents snowy weather
  bool _isSnowyWeather(int conditionCode) {
    return (conditionCode >= 600 && conditionCode <= 622); // Snow and sleet
  }
}
