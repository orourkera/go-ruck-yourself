import 'package:shared_preferences/shared_preferences.dart';

class FirstLaunchService {
  static const String _hasSeenPaywallKey = 'has_seen_paywall';
  
  /// Check if the user has seen the paywall before
  static Future<bool> hasSeenPaywall() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_hasSeenPaywallKey) ?? false;
  }
  
  /// Mark that the user has seen the paywall
  static Future<void> markPaywallSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hasSeenPaywallKey, true);
  }
  
  /// Reset the first launch state (useful for testing)
  static Future<void> resetFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_hasSeenPaywallKey);
  }
}
