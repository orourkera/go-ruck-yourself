import 'package:flutter/material.dart';

/// App text styles
class AppTextStyles {
  // Headline styles
  static const TextStyle headline1 = TextStyle(
    fontFamily: 'Roboto',
    fontWeight: FontWeight.w300,
    fontSize: 96,
    letterSpacing: -1.5,
  );
  
  static const TextStyle headline2 = TextStyle(
    fontFamily: 'Roboto',
    fontWeight: FontWeight.w300,
    fontSize: 60,
    letterSpacing: -0.5,
  );
  
  static const TextStyle headline3 = TextStyle(
    fontFamily: 'Roboto',
    fontWeight: FontWeight.normal,
    fontSize: 48,
    letterSpacing: 0,
  );
  
  static const TextStyle headline4 = TextStyle(
    fontFamily: 'Roboto',
    fontWeight: FontWeight.normal,
    fontSize: 34,
    letterSpacing: 0.25,
  );
  
  static const TextStyle headline5 = TextStyle(
    fontFamily: 'Roboto',
    fontWeight: FontWeight.normal,
    fontSize: 24,
    letterSpacing: 0,
  );
  
  static const TextStyle headline6 = TextStyle(
    fontFamily: 'Roboto',
    fontWeight: FontWeight.w500,
    fontSize: 20,
    letterSpacing: 0.15,
  );
  
  // Subtitle styles
  static const TextStyle subtitle1 = TextStyle(
    fontFamily: 'Roboto',
    fontWeight: FontWeight.normal,
    fontSize: 16,
    letterSpacing: 0.15,
  );
  
  static const TextStyle subtitle2 = TextStyle(
    fontFamily: 'Roboto',
    fontWeight: FontWeight.w500,
    fontSize: 14,
    letterSpacing: 0.1,
  );
  
  // Body styles
  static const TextStyle body1 = TextStyle(
    fontFamily: 'Roboto',
    fontWeight: FontWeight.normal,
    fontSize: 16,
    letterSpacing: 0.5,
  );
  
  static const TextStyle body2 = TextStyle(
    fontFamily: 'Roboto',
    fontWeight: FontWeight.normal,
    fontSize: 14,
    letterSpacing: 0.25,
  );
  
  // Other styles
  static const TextStyle button = TextStyle(
    fontFamily: 'Roboto',
    fontWeight: FontWeight.w500,
    fontSize: 14,
    letterSpacing: 1.25,
  );
  
  static const TextStyle caption = TextStyle(
    fontFamily: 'Roboto',
    fontWeight: FontWeight.normal,
    fontSize: 12,
    letterSpacing: 0.4,
  );
  
  static const TextStyle overline = TextStyle(
    fontFamily: 'Roboto',
    fontWeight: FontWeight.normal,
    fontSize: 10,
    letterSpacing: 1.5,
  );
  
  // Custom styles
  static const TextStyle tabLabel = TextStyle(
    fontFamily: 'Roboto',
    fontWeight: FontWeight.w500,
    fontSize: 14,
    letterSpacing: 1.25,
  );
  
  static const TextStyle statValue = TextStyle(
    fontFamily: 'Roboto',
    fontWeight: FontWeight.bold,
    fontSize: 24,
  );
  
  static const TextStyle statLabel = TextStyle(
    fontFamily: 'Roboto',
    fontWeight: FontWeight.normal,
    fontSize: 12,
    letterSpacing: 0.4,
  );
  
  static const TextStyle timerDisplay = TextStyle(
    fontFamily: 'Roboto',
    fontWeight: FontWeight.w300,
    fontSize: 48,
    letterSpacing: 0,
  );
  
  // Private constructor to prevent instantiation
  AppTextStyles._();
} 