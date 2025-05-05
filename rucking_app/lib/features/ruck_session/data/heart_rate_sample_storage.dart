import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/models/heart_rate_sample.dart';

class HeartRateSampleStorage {
  static const _key = 'heart_rate_samples';

  /// Save a list of heart rate samples to SharedPreferences
  static Future<void> saveSamples(List<HeartRateSample> samples) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = samples.map((e) => e.toJson()).toList();
    await prefs.setString(_key, jsonEncode(jsonList));
  }

  /// Load a list of heart rate samples from SharedPreferences
  static Future<List<HeartRateSample>> loadSamples() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_key);
    if (jsonString == null) return [];
    final List<dynamic> decoded = jsonDecode(jsonString);
    return decoded.map((e) => HeartRateSample.fromJson(e)).toList();
  }

  /// Clear all saved heart rate samples
  static Future<void> clearSamples() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
