/// Application configuration constants
class AppConfig {
  // API configuration
  static const String apiBaseUrl = 'https://getrucky.com/api';
  static const int apiTimeout = 30; // seconds
  
  // App information
  static const String appName = 'Go Ruck Yourself';
  static const String appVersion = '1.0.0';
  
  // Weight Conversion and Options
  static const double kgToLbs = 2.20462;
  static const double defaultRuckWeight = 10.0; // Default weight in KG
  static const List<double> metricWeightOptions = [0.0, 2.6, 4.5, 9.0, 11.3, 13.6, 20.4, 22.7, 27.2]; 
  static const List<double> standardWeightOptions = [0.0, 10.0, 15.0, 20.0, 25.0, 30.0, 35.0, 40.0, 45.0, 50.0, 60.0]; // LBS
  
  // Storage keys
  static const String tokenKey = 'auth_token';
  static const String userIdKey = 'user_id';
  static const String userProfileKey = 'user_profile';
  static const String themeKey = 'app_theme';
  static const String unitSystemKey = 'unit_system'; // metric or imperial
  static const String refreshTokenKey = 'refresh_token';
  
  // Feature flags
  static const bool enableHealthSync = true;
  static const bool enableOfflineMode = true;
  
  // Notification channels
  static const String ruckSessionChannel = 'ruck_session_channel';
  
  // Permission related
  static const int locationPermissionRequestInterval = 7; // days
  
  // Private constructor to prevent instantiation
  AppConfig._();
} 