import 'package:flutter/material.dart';

/// App color palette with rustic theme
class AppColors {
  // Primary colors - Brownish-orange
  static final Color primary = Color(0xFFCC6A2A); 
  static final Color primaryLight = Color(0xFFE09355);
  static final Color primaryDark = Color(0xFFA04F18);
  
  // Secondary colors - Olive green
  static final Color secondary = Color(0xFF728C69); 
  static final Color secondaryLight = Color(0xFF94A98C);
  static final Color secondaryDark = Color(0xFF546A4A);
  static final Color secondaryDarkest = Color(0xFF3A4A33);
  
  // Accent colors (earthy red)
  static final Color accent = Color(0xFFB84934); 
  static final Color accentLight = Color(0xFFD67D6D);
  static final Color accentDark = Color(0xFF9A311E);
  
  // Neutral colors
  static final Color white = Color(0xFFFFFFFF);
  static final Color black = Color(0xFF000000);
  static final Color grey = Color(0xFF9E9E9E);
  static final Color greyLight = Color(0xFFE0E0E0);
  static final Color greyDark = Color(0xFF616161);
  
  // Brown color
  static final Color brown = Color(0xFF4B3621);
  
  // Background colors
  static final Color backgroundLight = Color(0xFFF4F1EA); // Light beige
  static final Color backgroundDark = Color(0xFF2C2418); // Dark brown
  
  // Surface colors
  static final Color surfaceLight = Color(0xFFFAF7F2); // Lighter beige
  static final Color surfaceDark = Color(0xFF352D1F); // Dark brown
  
  // Text colors
  static final Color textDark = Color(0xFF1F1F1F);
  static final Color textDarkSecondary = Color(0xFF4B3621); // Brown
  static final Color textLight = Color(0xFFF4F1EA); // Light beige
  static final Color textLightSecondary = Color(0xFFE0DAD0); // Light beige secondary
  
  // Status colors
  static final Color success = Color(0xFF728C69); // Olive green
  static final Color error = Color(0xFFB84934); // Earthy red
  static final Color errorDark = Color(0xFF9A311E);
  static final Color warning = Color(0xFFE09355); // Light orange
  static final Color info = Color(0xFF546A4A); // Dark olive
  
  // Divider colors
  static final Color dividerLight = Color(0xFFE0DAD0);
  static final Color dividerDark = Color(0xFF4B3621);
  
  // Gradient colors
  static final List<Color> primaryGradient = [
    Color(0xFFCC6A2A), // Brownish-orange
    Color(0xFFE09355), // Light orange
  ];
  
  static final List<Color> secondaryGradient = [
    Color(0xFF728C69), // Olive green
    Color(0xFF94A98C), // Light olive
  ];
  
  static final List<Color> accentGradient = [
    Color(0xFFB84934), // Earthy red
    Color(0xFFD67D6D), // Light red
  ];
  
  // Private constructor to prevent instantiation
  AppColors._();
} 