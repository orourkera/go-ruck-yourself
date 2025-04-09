import 'package:flutter/material.dart';

/// App color palette
class AppColors {
  // Primary colors
  static final Color primary = Color(0xFF1E6E42); // Deep Green
  static final Color primaryLight = Color(0xFF5A9C7A);
  static final Color primaryDark = Color(0xFF004D28);
  
  // Secondary colors
  static final Color secondary = Color(0xFF4CAF50); // Green
  static final Color secondaryLight = Color(0xFF80E27E);
  static final Color secondaryDark = Color(0xFF087F23);
  static final Color secondaryDarkest = Color(0xFF005100);
  
  // Accent colors
  static final Color accent = Color(0xFFFF6D00); // Orange
  static final Color accentLight = Color(0xFFFF9E40);
  static final Color accentDark = Color(0xFFC43C00);
  
  // Neutral colors
  static final Color white = Color(0xFFFFFFFF);
  static final Color black = Color(0xFF000000);
  static final Color grey = Color(0xFF9E9E9E);
  static final Color greyLight = Color(0xFFE0E0E0);
  static final Color greyDark = Color(0xFF616161);
  
  // Background colors
  static final Color backgroundLight = Color(0xFFF5F5F5);
  static final Color backgroundDark = Color(0xFF121212);
  
  // Surface colors
  static final Color surfaceLight = Color(0xFFFFFFFF);
  static final Color surfaceDark = Color(0xFF1E1E1E);
  
  // Text colors
  static final Color textDark = Color(0xFF212121);
  static final Color textDarkSecondary = Color(0xFF757575);
  static final Color textLight = Color(0xFFFAFAFA);
  static final Color textLightSecondary = Color(0xFFE0E0E0);
  
  // Status colors
  static final Color success = Color(0xFF4CAF50); // Green
  static final Color error = Color(0xFFE53935); // Red
  static final Color errorDark = Color(0xFFEF5350);
  static final Color warning = Color(0xFFFFA000); // Amber
  static final Color info = Color(0xFF2196F3); // Blue
  
  // Divider colors
  static final Color dividerLight = Color(0xFFE0E0E0);
  static final Color dividerDark = Color(0xFF424242);
  
  // Gradient colors
  static final List<Color> primaryGradient = [
    Color(0xFF1E6E42), // Deep Green
    Color(0xFF4CAF50), // Green
  ];
  
  static final List<Color> secondaryGradient = [
    Color(0xFF4CAF50), // Green
    Color(0xFF8BC34A), // Light Green
  ];
  
  static final List<Color> accentGradient = [
    Color(0xFFFF6D00), // Orange
    Color(0xFFFF9E40), // Light Orange
  ];
  
  // Private constructor to prevent instantiation
  AppColors._();
} 