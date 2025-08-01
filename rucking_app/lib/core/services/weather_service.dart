import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/weather.dart';
import '../utils/app_logger.dart';

/// Service for fetching weather data from backend/WeatherKit
class WeatherService {
  final Dio _dio;
  final String _baseUrl;

  WeatherService({Dio? dio})
      : _dio = dio ?? Dio(),
        _baseUrl = dotenv.env['API_BASE_URL'] ?? 'https://getrucky.com/api';

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

      final response = await _dio.get(
        '$_baseUrl/weather',
        queryParameters: queryParams,
        options: Options(
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      if (response.statusCode == 200) {
        final weatherData = Weather.fromJson(response.data as Map<String, dynamic>);
        AppLogger.info('Successfully fetched weather data');
        return weatherData;
      } else {
        AppLogger.warning('Weather API returned status: ${response.statusCode}');
        return null;
      }
    } on DioException catch (e) {
      AppLogger.error(
        'Network error fetching weather data',
        exception: e,
        stackTrace: e.stackTrace,
      );
      
      // Check for specific error types
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        AppLogger.warning('Weather request timed out');
      } else if (e.type == DioExceptionType.connectionError) {
        AppLogger.warning('Weather service connection failed');
      }
      
      return null;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Unexpected error fetching weather data',
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

    // Precipitation factor
    final condition = weather.conditionCode?.toLowerCase() ?? '';
    if (condition.contains('rain') || condition.contains('storm')) {
      if (condition.contains('heavy') || condition.contains('thunder')) {
        score *= 0.2; // Very poor for outdoor activity
      } else {
        score *= 0.5; // Poor but manageable
      }
    } else if (condition.contains('snow') || condition.contains('sleet')) {
      score *= 0.4; // Challenging conditions
    }

    // Wind factor
    if (weather.wind?.speed != null) {
      final windSpeed = weather.wind!.speed!;
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
    if (weather.visibility?.value != null) {
      final visibility = weather.visibility!.value!;
      if (visibility < 1000) {
        score *= 0.5; // Poor visibility
      } else if (visibility < 5000) {
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
}
