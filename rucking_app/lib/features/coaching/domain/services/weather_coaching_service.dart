import 'dart:async';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/coaching/domain/models/coaching_notification_preferences.dart';

/// Weather conditions for ruck planning
class WeatherCondition {
  final String condition; // 'sunny', 'rainy', 'cloudy', 'stormy', 'snow'
  final double temperature; // Celsius
  final double precipitationChance; // 0-100
  final double windSpeed; // km/h
  final double humidity; // 0-100
  final double uvIndex; // 0-11+
  final String description;

  const WeatherCondition({
    required this.condition,
    required this.temperature,
    required this.precipitationChance,
    required this.windSpeed,
    required this.humidity,
    required this.uvIndex,
    required this.description,
  });

  factory WeatherCondition.fromJson(Map<String, dynamic> json) {
    return WeatherCondition(
      condition: json['condition'] ?? 'unknown',
      temperature: (json['temperature'] ?? 20.0).toDouble(),
      precipitationChance: (json['precipitation_chance'] ?? 0.0).toDouble(),
      windSpeed: (json['wind_speed'] ?? 0.0).toDouble(),
      humidity: (json['humidity'] ?? 50.0).toDouble(),
      uvIndex: (json['uv_index'] ?? 5.0).toDouble(),
      description: json['description'] ?? 'Weather data unavailable',
    );
  }

  /// Check if weather is suitable for rucking
  bool get isRuckFriendly {
    // Avoid extreme conditions
    if (temperature < -10 || temperature > 40) return false; // Too cold/hot
    if (precipitationChance > 80) return false; // Too much rain
    if (windSpeed > 50) return false; // Too windy
    
    return true;
  }

  /// Get weather severity level
  WeatherSeverity get severity {
    if (!isRuckFriendly) return WeatherSeverity.extreme;
    
    // High: challenging but manageable
    if (temperature < 0 || temperature > 35 || 
        precipitationChance > 60 || 
        windSpeed > 30 ||
        uvIndex > 8) {
      return WeatherSeverity.challenging;
    }
    
    // Ideal: perfect conditions
    if (temperature >= 15 && temperature <= 25 && 
        precipitationChance < 20 && 
        windSpeed < 15 &&
        uvIndex < 6) {
      return WeatherSeverity.ideal;
    }
    
    // Moderate: good enough
    return WeatherSeverity.moderate;
  }
}

enum WeatherSeverity { ideal, moderate, challenging, extreme }

/// Ruck suggestion based on weather
class WeatherRuckSuggestion {
  final String suggestion;
  final String reason;
  final List<String> tips;
  final bool isRecommended;
  final WeatherSeverity severity;

  const WeatherRuckSuggestion({
    required this.suggestion,
    required this.reason,
    required this.tips,
    required this.isRecommended,
    required this.severity,
  });
}

/// Service for weather-based ruck coaching suggestions
class WeatherCoachingService {
  final ApiClient _apiClient;

  WeatherCoachingService(this._apiClient);

  /// Get current weather condition for user's location
  Future<WeatherCondition?> getCurrentWeather({
    double? latitude,
    double? longitude,
  }) async {
    try {
      final response = await _apiClient.get('/weather/current', queryParams: {
        if (latitude != null) 'lat': latitude,
        if (longitude != null) 'lon': longitude,
      });
      
      return WeatherCondition.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      AppLogger.error('Error fetching weather data: $e');
      return null;
    }
  }

  /// Get weather forecast for the next 7 days
  Future<List<WeatherCondition>> getWeatherForecast({
    double? latitude,
    double? longitude,
    int days = 7,
  }) async {
    try {
      final response = await _apiClient.get('/weather/forecast', queryParams: {
        if (latitude != null) 'lat': latitude,
        if (longitude != null) 'lon': longitude,
        'days': days,
      });
      
      final forecastData = response.data['forecast'] as List<dynamic>? ?? [];
      return forecastData
          .map((data) => WeatherCondition.fromJson(data as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppLogger.error('Error fetching weather forecast: $e');
      return [];
    }
  }

  /// Generate weather-based ruck suggestion
  WeatherRuckSuggestion generateRuckSuggestion(
    WeatherCondition weather,
    CoachingTone tone,
  ) {
    switch (weather.severity) {
      case WeatherSeverity.ideal:
        return _generateIdealWeatherSuggestion(weather, tone);
      case WeatherSeverity.moderate:
        return _generateModerateWeatherSuggestion(weather, tone);
      case WeatherSeverity.challenging:
        return _generateChallengingWeatherSuggestion(weather, tone);
      case WeatherSeverity.extreme:
        return _generateExtremeWeatherSuggestion(weather, tone);
    }
  }

  /// Generate suggestion for ideal weather
  WeatherRuckSuggestion _generateIdealWeatherSuggestion(
    WeatherCondition weather,
    CoachingTone tone,
  ) {
    final suggestions = _getIdealWeatherSuggestions(tone);
    final tips = [
      'Perfect conditions for extending your route',
      'Great time to work on pace',
      'Consider adding extra weight if feeling strong',
    ];

    return WeatherRuckSuggestion(
      suggestion: suggestions[0],
      reason: 'Perfect weather conditions detected',
      tips: tips,
      isRecommended: true,
      severity: WeatherSeverity.ideal,
    );
  }

  /// Generate suggestion for moderate weather
  WeatherRuckSuggestion _generateModerateWeatherSuggestion(
    WeatherCondition weather,
    CoachingTone tone,
  ) {
    final suggestions = _getModerateWeatherSuggestions(tone);
    final tips = <String>[];
    
    if (weather.temperature > 25) {
      tips.addAll(['Bring extra water', 'Start early to avoid heat', 'Take shade breaks']);
    }
    if (weather.precipitationChance > 30) {
      tips.addAll(['Light rain gear recommended', 'Watch footing on wet surfaces']);
    }
    if (weather.windSpeed > 20) {
      tips.add('Expect headwind resistance');
    }
    
    if (tips.isEmpty) {
      tips.add('Standard session recommended');
    }

    return WeatherRuckSuggestion(
      suggestion: suggestions[0],
      reason: _buildModerateWeatherReason(weather),
      tips: tips,
      isRecommended: true,
      severity: WeatherSeverity.moderate,
    );
  }

  /// Generate suggestion for challenging weather
  WeatherRuckSuggestion _generateChallengingWeatherSuggestion(
    WeatherCondition weather,
    CoachingTone tone,
  ) {
    final suggestions = _getChallengingWeatherSuggestions(tone);
    final tips = <String>[];
    
    if (weather.temperature < 5) {
      tips.addAll([
        'Layer clothing appropriately',
        'Warm up thoroughly indoors',
        'Protect extremities from cold',
      ]);
    } else if (weather.temperature > 30) {
      tips.addAll([
        'Start very early or late evening',
        'Bring plenty of water',
        'Take frequent cooling breaks',
        'Consider shorter distance',
      ]);
    }
    
    if (weather.precipitationChance > 50) {
      tips.addAll([
        'Waterproof gear essential',
        'Stick to familiar routes',
        'Extra caution on slippery surfaces',
      ]);
    }
    
    if (weather.uvIndex > 8) {
      tips.addAll([
        'Strong sunscreen required',
        'Wear protective clothing',
        'Seek shade when possible',
      ]);
    }

    return WeatherRuckSuggestion(
      suggestion: suggestions[0],
      reason: _buildChallengingWeatherReason(weather),
      tips: tips,
      isRecommended: true,
      severity: WeatherSeverity.challenging,
    );
  }

  /// Generate suggestion for extreme weather
  WeatherRuckSuggestion _generateExtremeWeatherSuggestion(
    WeatherCondition weather,
    CoachingTone tone,
  ) {
    final suggestions = _getExtremeWeatherSuggestions(tone);
    final tips = [
      'Indoor alternative recommended',
      'Safety should be top priority',
      'Wait for conditions to improve',
    ];

    return WeatherRuckSuggestion(
      suggestion: suggestions[0],
      reason: _buildExtremeWeatherReason(weather),
      tips: tips,
      isRecommended: false,
      severity: WeatherSeverity.extreme,
    );
  }

  /// Get ideal weather suggestions by tone
  List<String> _getIdealWeatherSuggestions(CoachingTone tone) {
    switch (tone) {
      case CoachingTone.drillSergeant:
        return [
          'Perfect conditions - no excuses! Time for an epic ruck!',
          'Weather is on your side - push those limits today!',
        ];
      case CoachingTone.supportiveFriend:
        return [
          'What a beautiful day for a ruck! Perfect conditions await.',
          'Mother Nature is smiling on your training today!',
        ];
      case CoachingTone.dataNerd:
        return [
          'Weather parameters optimal for maximum performance output.',
          'All environmental factors align for ideal training session.',
        ];
      case CoachingTone.minimalist:
        return [
          'Perfect conditions.',
          'Weather ideal.',
        ];
    }
  }

  /// Get moderate weather suggestions by tone
  List<String> _getModerateWeatherSuggestions(CoachingTone tone) {
    switch (tone) {
      case CoachingTone.drillSergeant:
        return [
          'Good enough conditions - soldier on!',
          'Weather won\'t stop a true warrior!',
        ];
      case CoachingTone.supportiveFriend:
        return [
          'Decent conditions for your ruck today!',
          'Weather looks manageable - you\'ve got this!',
        ];
      case CoachingTone.dataNerd:
        return [
          'Weather conditions within acceptable parameters.',
          'Environmental factors favorable for session execution.',
        ];
      case CoachingTone.minimalist:
        return [
          'Good conditions.',
          'Weather acceptable.',
        ];
    }
  }

  /// Get challenging weather suggestions by tone
  List<String> _getChallengingWeatherSuggestions(CoachingTone tone) {
    switch (tone) {
      case CoachingTone.drillSergeant:
        return [
          'Tough conditions build tough soldiers! Embrace the challenge!',
          'This weather will forge your character - attack it!',
        ];
      case CoachingTone.supportiveFriend:
        return [
          'Challenging conditions, but I know you can handle it safely.',
          'Weather is tough today - take extra care out there.',
        ];
      case CoachingTone.dataNerd:
        return [
          'Suboptimal conditions detected. Additional precautions recommended.',
          'Environmental factors challenging. Adjust parameters accordingly.',
        ];
      case CoachingTone.minimalist:
        return [
          'Tough conditions.',
          'Weather challenging.',
        ];
    }
  }

  /// Get extreme weather suggestions by tone
  List<String> _getExtremeWeatherSuggestions(CoachingTone tone) {
    switch (tone) {
      case CoachingTone.drillSergeant:
        return [
          'Even warriors know when to tactical retreat. Stay safe inside.',
          'Strategic delay - live to fight another day!',
        ];
      case CoachingTone.supportiveFriend:
        return [
          'Weather is too extreme today. Your safety comes first!',
          'Let\'s wait for safer conditions. No session is worth getting hurt.',
        ];
      case CoachingTone.dataNerd:
        return [
          'Extreme weather parameters detected. Indoor alternative advised.',
          'Environmental factors exceed safe training thresholds.',
        ];
      case CoachingTone.minimalist:
        return [
          'Too extreme.',
          'Stay inside.',
        ];
    }
  }

  /// Build reason for moderate weather
  String _buildModerateWeatherReason(WeatherCondition weather) {
    final reasons = <String>[];
    
    if (weather.temperature > 25 && weather.temperature <= 30) {
      reasons.add('warm temperature');
    } else if (weather.temperature < 10 && weather.temperature >= 0) {
      reasons.add('cool temperature');
    }
    
    if (weather.precipitationChance > 30 && weather.precipitationChance <= 50) {
      reasons.add('possible light rain');
    }
    
    if (weather.windSpeed > 15 && weather.windSpeed <= 25) {
      reasons.add('moderate winds');
    }
    
    if (reasons.isEmpty) {
      return 'Generally favorable conditions';
    }
    
    return 'Manageable conditions with ${reasons.join(" and ")}';
  }

  /// Build reason for challenging weather
  String _buildChallengingWeatherReason(WeatherCondition weather) {
    final reasons = <String>[];
    
    if (weather.temperature <= 0) {
      reasons.add('freezing temperature');
    } else if (weather.temperature > 30) {
      reasons.add('high temperature');
    }
    
    if (weather.precipitationChance > 50) {
      reasons.add('likely precipitation');
    }
    
    if (weather.windSpeed > 25) {
      reasons.add('strong winds');
    }
    
    if (weather.uvIndex > 8) {
      reasons.add('high UV levels');
    }
    
    return 'Challenging conditions due to ${reasons.join(" and ")}';
  }

  /// Build reason for extreme weather
  String _buildExtremeWeatherReason(WeatherCondition weather) {
    final reasons = <String>[];
    
    if (weather.temperature < -10) {
      reasons.add('dangerously cold');
    } else if (weather.temperature > 40) {
      reasons.add('dangerously hot');
    }
    
    if (weather.precipitationChance > 80) {
      reasons.add('heavy precipitation');
    }
    
    if (weather.windSpeed > 50) {
      reasons.add('extreme winds');
    }
    
    return 'Unsafe conditions: ${reasons.join(" and ")}';
  }

  /// Check if weather notification should be sent
  bool shouldSendWeatherNotification(
    WeatherCondition weather,
    CoachingNotificationPreferences preferences,
  ) {
    if (!preferences.enableWeatherSuggestions) return false;
    
    // Send notification for ideal conditions or challenging/extreme conditions
    // Skip moderate conditions to avoid spam
    return weather.severity == WeatherSeverity.ideal || 
           weather.severity == WeatherSeverity.challenging ||
           weather.severity == WeatherSeverity.extreme;
  }
}