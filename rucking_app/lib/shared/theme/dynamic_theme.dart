import 'package:flutter/material.dart';
import 'package:rucking_app/core/models/user.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_theme.dart';

/// Dynamic theme provider that changes the app theme based on user preferences
class DynamicTheme {
  /// Get the appropriate theme data based on user settings
  static ThemeData getThemeData(User? user, bool isDarkMode) {
    // Base theme to start with
    final baseTheme = isDarkMode ? AppTheme.darkTheme : AppTheme.lightTheme;
    
    // If the user is female, update with lady mode colors
    if (user != null && user.gender == 'female') {
      return _applyLadyModeColors(baseTheme);
    }
    
    // Return default theme
    return baseTheme;
  }
  
  /// Apply lady mode colors to the theme
  static ThemeData _applyLadyModeColors(ThemeData baseTheme) {
    final Color primaryColor = AppColors.ladyPrimary;
    final Color primaryLightColor = AppColors.ladyPrimaryLight;
    
    // Create a new colorScheme based on the existing one
    final ColorScheme newColorScheme = baseTheme.colorScheme.copyWith(
      primary: primaryColor,
      primaryContainer: primaryLightColor,
      onPrimary: Colors.white,
    );
    
    // Create a new theme with lady colors
    return baseTheme.copyWith(
      primaryColor: primaryColor,
      colorScheme: newColorScheme,
      appBarTheme: baseTheme.appBarTheme.copyWith(
        backgroundColor: primaryColor,
      ),
      floatingActionButtonTheme: baseTheme.floatingActionButtonTheme.copyWith(
        backgroundColor: primaryColor,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
        ),
      ),
      tabBarTheme: baseTheme.tabBarTheme.copyWith(
        labelColor: primaryColor,
        indicatorColor: primaryColor,
      ),
    );
  }
}
