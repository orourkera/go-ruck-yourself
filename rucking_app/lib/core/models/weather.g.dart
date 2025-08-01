// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'weather.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Weather _$WeatherFromJson(Map<String, dynamic> json) => Weather(
      currentWeather: json['currentWeather'] == null
          ? null
          : CurrentWeather.fromJson(
              json['currentWeather'] as Map<String, dynamic>),
      hourlyForecast: (json['hourlyForecast'] as List<dynamic>?)
          ?.map((e) => HourlyForecast.fromJson(e as Map<String, dynamic>))
          .toList(),
      dailyForecast: (json['dailyForecast'] as List<dynamic>?)
          ?.map((e) => DailyForecast.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$WeatherToJson(Weather instance) => <String, dynamic>{
      'currentWeather': instance.currentWeather,
      'hourlyForecast': instance.hourlyForecast,
      'dailyForecast': instance.dailyForecast,
    };

CurrentWeather _$CurrentWeatherFromJson(Map<String, dynamic> json) =>
    CurrentWeather(
      name: json['name'] as String?,
      metadata: json['metadata'] == null
          ? null
          : Metadata.fromJson(json['metadata'] as Map<String, dynamic>),
      temperature: (json['temperature'] as num?)?.toDouble(),
      temperatureApparent: (json['temperatureApparent'] as num?)?.toDouble(),
      conditionCode: json['conditionCode'] as String?,
      humidity: (json['humidity'] as num?)?.toDouble(),
      pressure: json['pressure'] == null
          ? null
          : Pressure.fromJson(json['pressure'] as Map<String, dynamic>),
      visibility: json['visibility'] == null
          ? null
          : Visibility.fromJson(json['visibility'] as Map<String, dynamic>),
      uvIndex: (json['uvIndex'] as num?)?.toDouble(),
      wind: json['wind'] == null
          ? null
          : Wind.fromJson(json['wind'] as Map<String, dynamic>),
      dewPoint: (json['dewPoint'] as num?)?.toDouble(),
      cloudCover: (json['cloudCover'] as num?)?.toDouble(),
      asOf:
          json['asOf'] == null ? null : DateTime.parse(json['asOf'] as String),
      daylight: json['daylight'] == null
          ? null
          : DateTime.parse(json['daylight'] as String),
    );

Map<String, dynamic> _$CurrentWeatherToJson(CurrentWeather instance) =>
    <String, dynamic>{
      'name': instance.name,
      'metadata': instance.metadata,
      'temperature': instance.temperature,
      'temperatureApparent': instance.temperatureApparent,
      'conditionCode': instance.conditionCode,
      'humidity': instance.humidity,
      'pressure': instance.pressure,
      'visibility': instance.visibility,
      'uvIndex': instance.uvIndex,
      'wind': instance.wind,
      'dewPoint': instance.dewPoint,
      'cloudCover': instance.cloudCover,
      'asOf': instance.asOf?.toIso8601String(),
      'daylight': instance.daylight?.toIso8601String(),
    };

HourlyForecast _$HourlyForecastFromJson(Map<String, dynamic> json) =>
    HourlyForecast(
      forecastStart: json['forecastStart'] == null
          ? null
          : DateTime.parse(json['forecastStart'] as String),
      temperature: (json['temperature'] as num?)?.toDouble(),
      temperatureApparent: (json['temperatureApparent'] as num?)?.toDouble(),
      conditionCode: json['conditionCode'] as String?,
      humidity: (json['humidity'] as num?)?.toDouble(),
      precipitationChance: (json['precipitationChance'] as num?)?.toDouble(),
      precipitationAmount: (json['precipitationAmount'] as num?)?.toDouble(),
      wind: json['wind'] == null
          ? null
          : Wind.fromJson(json['wind'] as Map<String, dynamic>),
      uvIndex: (json['uvIndex'] as num?)?.toDouble(),
      visibility: json['visibility'] == null
          ? null
          : Visibility.fromJson(json['visibility'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$HourlyForecastToJson(HourlyForecast instance) =>
    <String, dynamic>{
      'forecastStart': instance.forecastStart?.toIso8601String(),
      'temperature': instance.temperature,
      'temperatureApparent': instance.temperatureApparent,
      'conditionCode': instance.conditionCode,
      'humidity': instance.humidity,
      'precipitationChance': instance.precipitationChance,
      'precipitationAmount': instance.precipitationAmount,
      'wind': instance.wind,
      'uvIndex': instance.uvIndex,
      'visibility': instance.visibility,
    };

DailyForecast _$DailyForecastFromJson(Map<String, dynamic> json) =>
    DailyForecast(
      forecastStart: json['forecastStart'] == null
          ? null
          : DateTime.parse(json['forecastStart'] as String),
      forecastEnd: json['forecastEnd'] == null
          ? null
          : DateTime.parse(json['forecastEnd'] as String),
      conditionCode: json['conditionCode'] as String?,
      temperatureMax: (json['temperatureMax'] as num?)?.toDouble(),
      temperatureMin: (json['temperatureMin'] as num?)?.toDouble(),
      precipitationChance: (json['precipitationChance'] as num?)?.toDouble(),
      precipitationAmount: (json['precipitationAmount'] as num?)?.toDouble(),
      wind: json['wind'] == null
          ? null
          : Wind.fromJson(json['wind'] as Map<String, dynamic>),
      uvIndex: (json['uvIndex'] as num?)?.toDouble(),
      sunrise: json['sunrise'] == null
          ? null
          : DateTime.parse(json['sunrise'] as String),
      sunset: json['sunset'] == null
          ? null
          : DateTime.parse(json['sunset'] as String),
    );

Map<String, dynamic> _$DailyForecastToJson(DailyForecast instance) =>
    <String, dynamic>{
      'forecastStart': instance.forecastStart?.toIso8601String(),
      'forecastEnd': instance.forecastEnd?.toIso8601String(),
      'conditionCode': instance.conditionCode,
      'temperatureMax': instance.temperatureMax,
      'temperatureMin': instance.temperatureMin,
      'precipitationChance': instance.precipitationChance,
      'precipitationAmount': instance.precipitationAmount,
      'wind': instance.wind,
      'uvIndex': instance.uvIndex,
      'sunrise': instance.sunrise?.toIso8601String(),
      'sunset': instance.sunset?.toIso8601String(),
    };

Metadata _$MetadataFromJson(Map<String, dynamic> json) => Metadata(
      attributionURL: json['attributionURL'] as String?,
      expireTime: json['expireTime'] == null
          ? null
          : DateTime.parse(json['expireTime'] as String),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      readTime: json['readTime'] == null
          ? null
          : DateTime.parse(json['readTime'] as String),
      reportedTime: json['reportedTime'] == null
          ? null
          : DateTime.parse(json['reportedTime'] as String),
      units: json['units'] as String?,
      version: (json['version'] as num?)?.toInt(),
    );

Map<String, dynamic> _$MetadataToJson(Metadata instance) => <String, dynamic>{
      'attributionURL': instance.attributionURL,
      'expireTime': instance.expireTime?.toIso8601String(),
      'latitude': instance.latitude,
      'longitude': instance.longitude,
      'readTime': instance.readTime?.toIso8601String(),
      'reportedTime': instance.reportedTime?.toIso8601String(),
      'units': instance.units,
      'version': instance.version,
    };

Wind _$WindFromJson(Map<String, dynamic> json) => Wind(
      speed: (json['speed'] as num?)?.toDouble(),
      direction: (json['direction'] as num?)?.toDouble(),
      gust: (json['gust'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$WindToJson(Wind instance) => <String, dynamic>{
      'speed': instance.speed,
      'direction': instance.direction,
      'gust': instance.gust,
    };

Pressure _$PressureFromJson(Map<String, dynamic> json) => Pressure(
      value: (json['value'] as num?)?.toDouble(),
      unit: json['unit'] as String?,
    );

Map<String, dynamic> _$PressureToJson(Pressure instance) => <String, dynamic>{
      'value': instance.value,
      'unit': instance.unit,
    };

Visibility _$VisibilityFromJson(Map<String, dynamic> json) => Visibility(
      value: (json['value'] as num?)?.toDouble(),
      unit: json['unit'] as String?,
    );

Map<String, dynamic> _$VisibilityToJson(Visibility instance) =>
    <String, dynamic>{
      'value': instance.value,
      'unit': instance.unit,
    };
