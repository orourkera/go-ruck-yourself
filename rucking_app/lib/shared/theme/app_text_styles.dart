import 'package:flutter/material.dart';

/// App text styles with rustic theme
class AppTextStyles {
  // Headline styles with Bangers font
  static const TextStyle headline1 = TextStyle(
    fontFamily: 'Bangers',
    fontWeight: FontWeight.bold,
    fontSize: 32,
    letterSpacing: 1.0,
  );
  
  static const TextStyle headline2 = TextStyle(
    fontFamily: 'Bangers',
    fontWeight: FontWeight.bold,
    fontSize: 28,
    letterSpacing: 0.8,
  );
  
  static const TextStyle headline3 = TextStyle(
    fontFamily: 'Bangers',
    fontWeight: FontWeight.bold,
    fontSize: 24,
    letterSpacing: 0.6,
  );
  
  static const TextStyle headline4 = TextStyle(
    fontFamily: 'Bangers',
    fontWeight: FontWeight.bold,
    fontSize: 22,
    letterSpacing: 0.5,
  );
  
  static const TextStyle headline5 = TextStyle(
    fontFamily: 'Bangers',
    fontWeight: FontWeight.bold,
    fontSize: 20,
    letterSpacing: 0.4,
  );
  
  static const TextStyle headline6 = TextStyle(
    fontFamily: 'Bangers',
    fontWeight: FontWeight.bold,
    fontSize: 18,
    letterSpacing: 0.4,
  );
  
  // Subtitle styles with Inter font
  static const TextStyle subtitle1 = TextStyle(
    fontFamily: 'Inter',
    fontWeight: FontWeight.w500,
    fontSize: 16,
    letterSpacing: 0.15,
  );
  
  static const TextStyle subtitle2 = TextStyle(
    fontFamily: 'Inter',
    fontWeight: FontWeight.w500,
    fontSize: 14,
    letterSpacing: 0.1,
  );
  
  // Body styles with Inter font
  static const TextStyle body1 = TextStyle(
    fontFamily: 'Inter',
    fontWeight: FontWeight.normal,
    fontSize: 16,
    letterSpacing: 0.5,
  );
  
  static const TextStyle body2 = TextStyle(
    fontFamily: 'Inter',
    fontWeight: FontWeight.normal,
    fontSize: 14,
    letterSpacing: 0.25,
    color: Color(0xFF728C69), // Olive green
  );
  
  // Other styles with Bangers font for buttons
  static const TextStyle button = TextStyle(
    fontFamily: 'Bangers',
    fontWeight: FontWeight.normal,
    fontSize: 18,
    letterSpacing: 1.2,
  );
  
  static const TextStyle caption = TextStyle(
    fontFamily: 'Inter',
    fontWeight: FontWeight.normal,
    fontSize: 12,
    letterSpacing: 0.4,
  );
  
  static const TextStyle overline = TextStyle(
    fontFamily: 'Inter',
    fontWeight: FontWeight.normal,
    fontSize: 10,
    letterSpacing: 1.5,
  );
  
  // Custom styles
  static const TextStyle tabLabel = TextStyle(
    fontFamily: 'Bangers',
    fontWeight: FontWeight.normal,
    fontSize: 16,
    letterSpacing: 1.0,
  );
  
  static const TextStyle statValue = TextStyle(
    fontFamily: 'Bangers',
    fontWeight: FontWeight.bold,
    fontSize: 24,
    letterSpacing: 0.5,
  );
  
  static const TextStyle statLabel = TextStyle(
    fontFamily: 'Inter',
    fontWeight: FontWeight.normal,
    fontSize: 12,
    letterSpacing: 0.4,
  );
  
  static const TextStyle timerDisplay = TextStyle(
    fontFamily: 'Bangers',
    fontWeight: FontWeight.normal,
    fontSize: 48,
    letterSpacing: 1.0,
  );
  
  // Private constructor to prevent instantiation
  AppTextStyles._();
} 