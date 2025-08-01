import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'weather.g.dart';

/// Weather data model from WeatherKit API
@JsonSerializable()
class Weather extends Equatable {
  final CurrentWeather? currentWeather;
  final List<HourlyForecast>? hourlyForecast;
  final List<DailyForecast>? dailyForecast;

  const Weather({
    this.currentWeather,
    this.hourlyForecast,
    this.dailyForecast,
  });

  factory Weather.fromJson(Map<String, dynamic> json) =>
      _$WeatherFromJson(json);

  Map<String, dynamic> toJson() => _$WeatherToJson(this);

  @override
  List<Object?> get props => [currentWeather, hourlyForecast, dailyForecast];
}

/// Current weather conditions
@JsonSerializable()
class CurrentWeather extends Equatable {
  final String? name;
  final Metadata? metadata;
  final double? temperature;
  final double? temperatureApparent;
  final int? conditionCode;
  final double? humidity;
  final double? pressure;
  final double? visibility;
  final double? uvIndex;
  final double? windSpeed;
  final double? windDirection;
  final double? dewPoint;
  final double? cloudCover;
  final DateTime? asOf;
  final DateTime? daylight;

  const CurrentWeather({
    this.name,
    this.metadata,
    this.temperature,
    this.temperatureApparent,
    this.conditionCode,
    this.humidity,
    this.pressure,
    this.visibility,
    this.uvIndex,
    this.windSpeed,
    this.windDirection,
    this.dewPoint,
    this.cloudCover,
    this.asOf,
    this.daylight,
  });

  factory CurrentWeather.fromJson(Map<String, dynamic> json) =>
      _$CurrentWeatherFromJson(json);

  Map<String, dynamic> toJson() => _$CurrentWeatherToJson(this);

  @override
  List<Object?> get props => [
        name,
        metadata,
        temperature,
        temperatureApparent,
        conditionCode,
        humidity,
        pressure,
        visibility,
        uvIndex,
        windSpeed,
        windDirection,
        dewPoint,
        cloudCover,
        asOf,
        daylight,
      ];
}

/// Hourly weather forecast
@JsonSerializable()
class HourlyForecast extends Equatable {
  final DateTime? forecastStart;
  final double? temperature;
  final double? temperatureApparent;
  final int? conditionCode;
  final double? humidity;
  final double? precipitationChance;
  final double? precipitationAmount;
  final double? windSpeed;
  final double? windDirection;
  final double? uvIndex;
  final double? visibility;

  const HourlyForecast({
    this.forecastStart,
    this.temperature,
    this.temperatureApparent,
    this.conditionCode,
    this.humidity,
    this.precipitationChance,
    this.precipitationAmount,
    this.windSpeed,
    this.windDirection,
    this.uvIndex,
    this.visibility,
  });

  factory HourlyForecast.fromJson(Map<String, dynamic> json) =>
      _$HourlyForecastFromJson(json);

  Map<String, dynamic> toJson() => _$HourlyForecastToJson(this);

  @override
  List<Object?> get props => [
        forecastStart,
        temperature,
        temperatureApparent,
        conditionCode,
        humidity,
        precipitationChance,
        precipitationAmount,
        windSpeed,
        windDirection,
        uvIndex,
        visibility,
      ];
}

/// Daily weather forecast
@JsonSerializable()
class DailyForecast extends Equatable {
  final DateTime? forecastStart;
  final DateTime? forecastEnd;
  final int? conditionCode;
  final double? temperatureMax;
  final double? temperatureMin;
  final double? precipitationChance;
  final double? precipitationAmount;
  final double? windSpeed;
  final double? windDirection;
  final double? uvIndex;
  final DateTime? sunrise;
  final DateTime? sunset;

  const DailyForecast({
    this.forecastStart,
    this.forecastEnd,
    this.conditionCode,
    this.temperatureMax,
    this.temperatureMin,
    this.precipitationChance,
    this.precipitationAmount,
    this.windSpeed,
    this.windDirection,
    this.uvIndex,
    this.sunrise,
    this.sunset,
  });

  factory DailyForecast.fromJson(Map<String, dynamic> json) =>
      _$DailyForecastFromJson(json);

  Map<String, dynamic> toJson() => _$DailyForecastToJson(this);

  @override
  List<Object?> get props => [
        forecastStart,
        forecastEnd,
        conditionCode,
        temperatureMax,
        temperatureMin,
        precipitationChance,
        precipitationAmount,
        windSpeed,
        windDirection,
        uvIndex,
        sunrise,
        sunset,
      ];
}

/// Weather metadata
@JsonSerializable()
class Metadata extends Equatable {
  final String? attributionURL;
  final DateTime? expireTime;
  final double? latitude;
  final double? longitude;
  final DateTime? readTime;
  final DateTime? reportedTime;
  final String? units;
  final int? version;

  const Metadata({
    this.attributionURL,
    this.expireTime,
    this.latitude,
    this.longitude,
    this.readTime,
    this.reportedTime,
    this.units,
    this.version,
  });

  factory Metadata.fromJson(Map<String, dynamic> json) =>
      _$MetadataFromJson(json);

  Map<String, dynamic> toJson() => _$MetadataToJson(this);

  @override
  List<Object?> get props => [
        attributionURL,
        expireTime,
        latitude,
        longitude,
        readTime,
        reportedTime,
        units,
        version,
      ];
}

/// Wind information
@JsonSerializable()
class Wind extends Equatable {
  final double? speed;
  final double? direction;
  final double? gust;

  const Wind({
    this.speed,
    this.direction,
    this.gust,
  });

  factory Wind.fromJson(Map<String, dynamic> json) => _$WindFromJson(json);

  Map<String, dynamic> toJson() => _$WindToJson(this);

  @override
  List<Object?> get props => [speed, direction, gust];
}

/// Atmospheric pressure
@JsonSerializable()
class Pressure extends Equatable {
  final double? value;
  final String? unit;

  const Pressure({
    this.value,
    this.unit,
  });

  factory Pressure.fromJson(Map<String, dynamic> json) =>
      _$PressureFromJson(json);

  Map<String, dynamic> toJson() => _$PressureToJson(this);

  @override
  List<Object?> get props => [value, unit];
}

/// Visibility information
@JsonSerializable()
class Visibility extends Equatable {
  final double? value;
  final String? unit;

  const Visibility({
    this.value,
    this.unit,
  });

  factory Visibility.fromJson(Map<String, dynamic> json) =>
      _$VisibilityFromJson(json);

  Map<String, dynamic> toJson() => _$VisibilityToJson(this);

  @override
  List<Object?> get props => [value, unit];
}

/// Extension to get weather icon based on integer condition code
extension WeatherConditionIcon on int {
  /// Get appropriate weather icon for condition code
  String get weatherIcon {
    if (this >= 200 && this <= 232) {
      return '⛈️'; // Thunderstorms
    } else if (this >= 300 && this <= 321) {
      return '🌧️'; // Drizzle
    } else if (this >= 500 && this <= 504) {
      return '🌧️'; // Light to moderate rain
    } else if (this >= 511 && this <= 531) {
      return '🌦️'; // Heavy rain/showers
    } else if (this >= 600 && this <= 622) {
      return '❄️'; // Snow
    } else if (this >= 701 && this <= 781) {
      return '🌫️'; // Fog, mist, haze
    } else if (this == 800) {
      return '☀️'; // Clear sky
    } else if (this >= 801 && this <= 804) {
      if (this == 801) return '⛅'; // Few clouds
      else if (this == 802) return '⛅'; // Scattered clouds
      else return '☁️'; // Broken/overcast clouds
    } else {
      return '🌤️'; // Default
    }
  }

  /// Get human-readable description for condition code
  String get description {
    if (this >= 200 && this <= 232) {
      return 'Thunderstorms';
    } else if (this >= 300 && this <= 321) {
      return 'Drizzle';
    } else if (this >= 500 && this <= 504) {
      return 'Rain';
    } else if (this >= 511 && this <= 531) {
      return 'Heavy Rain';
    } else if (this >= 600 && this <= 622) {
      return 'Snow';
    } else if (this >= 701 && this <= 781) {
      return 'Fog';
    } else if (this == 800) {
      return 'Clear Sky';
    } else if (this >= 801 && this <= 804) {
      if (this == 801) return 'Few Clouds';
      else if (this == 802) return 'Scattered Clouds';
      else if (this == 803) return 'Broken Clouds';
      else return 'Overcast';
    } else {
      return 'Unknown';
    }
  }
}
