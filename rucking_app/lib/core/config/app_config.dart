/// Application configuration constants
class AppConfig {
  // API configuration
  static const String apiBaseUrl = 'https://api.ruckingapp.com/v1';
  static const int apiTimeout = 30; // seconds
  
  // App information
  static const String appName = 'GRY';
  static const String appVersion = '1.0.0';
  
  // Storage keys
  static const String tokenKey = 'auth_token';
  static const String userIdKey = 'user_id';
  static const String userProfileKey = 'user_profile';
  static const String themeKey = 'app_theme';
  static const String unitSystemKey = 'unit_system'; // metric or imperial
  
  // Feature flags
  static const bool enableHealthSync = true;
  static const bool enableOfflineMode = true;
  
  // Default values
  static const double defaultRuckWeight = 10.0; // kg
  
  // Notification channels
  static const String ruckSessionChannel = 'ruck_session_channel';
  
  // Permission related
  static const int locationPermissionRequestInterval = 7; // days
  
  // Private constructor to prevent instantiation
  AppConfig._();
} 