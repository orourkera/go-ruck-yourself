import 'package:flutter/material.dart';

/// App text styles with rustic theme
class AppTextStyles {
  // Headline styles (Mapped to MD3 Display/Headline)
  static const TextStyle displayLarge = TextStyle( // Renamed from headline1
    fontFamily: 'Bangers',
    fontWeight: FontWeight.bold,
    fontSize: 32,
    letterSpacing: 1.0,
  );
  
  static const TextStyle displayMedium = TextStyle( // Renamed from headline2
    fontFamily: 'Bangers',
    fontWeight: FontWeight.bold,
    fontSize: 28,
    letterSpacing: 0.8,
  );
  
  static const TextStyle displaySmall = TextStyle( // Renamed from headline3
    fontFamily: 'Bangers',
    fontWeight: FontWeight.bold,
    fontSize: 24,
    letterSpacing: 0.6,
  );
  
  static const TextStyle headlineLarge = TextStyle( // Renamed from headline4
    fontFamily: 'Bangers',
    fontWeight: FontWeight.bold,
    fontSize: 22,
    letterSpacing: 0.5,
  );
  
  static const TextStyle headlineMedium = TextStyle( // Renamed from headline5
    fontFamily: 'Bangers',
    fontWeight: FontWeight.bold,
    fontSize: 20,
    letterSpacing: 0.4,
  );
  
  static const TextStyle titleLarge = TextStyle( // Renamed from headline6
    fontFamily: 'Bangers',
    fontWeight: FontWeight.bold,
    fontSize: 18,
    letterSpacing: 0.4,
  );
  
  // Paywall header style with 3D text effect
  static const TextStyle paywallHeadline = TextStyle(
    fontFamily: 'Bangers',
    fontSize: 38, // Equivalent to ~5.4em for mobile
    color: Color(0xFFCC6A2A), // #CC6A2A orange
    letterSpacing: 2.0,
    height: 1.2,
    shadows: [
      Shadow(
        offset: Offset(-2.0, -2.0),
        color: Colors.white,
      ),
      Shadow(
        offset: Offset(2.0, -2.0),
        color: Colors.white,
      ),
      Shadow(
        offset: Offset(-2.0, 2.0),
        color: Colors.white,
      ),
      Shadow(
        offset: Offset(2.0, 2.0),
        color: Colors.white,
      ),
    ],
  );
  
  // Subtitle styles (Mapped to MD3 Title)
  static const TextStyle titleMedium = TextStyle( // Renamed from subtitle1
    fontFamily: 'Inter',
    fontWeight: FontWeight.w500,
    fontSize: 16,
    letterSpacing: 0.15,
  );
  
  static const TextStyle titleSmall = TextStyle( // Renamed from subtitle2
    fontFamily: 'Inter',
    fontWeight: FontWeight.w500,
    fontSize: 14,
    letterSpacing: 0.1,
  );
  
  // Body styles (Mapped to MD3 Body)
  static const TextStyle bodyLarge = TextStyle( // Renamed from body1
    fontFamily: 'Inter',
    fontWeight: FontWeight.normal,
    fontSize: 16,
    letterSpacing: 0.5,
    // No color here; set by theme
  );
  
  static const TextStyle bodyMedium = TextStyle( // Renamed from body2
    fontFamily: 'Inter',
    fontWeight: FontWeight.normal,
    fontSize: 14,
    letterSpacing: 0.25,
    // No color here; set by theme
  );
  
  // Other styles (Mapped to MD3 Label/Body)
  static const TextStyle labelLarge = TextStyle( // Renamed from button
    fontFamily: 'Bangers',
    fontWeight: FontWeight.normal,
    fontSize: 18,
    letterSpacing: 1.2,
  );

  static const TextStyle labelMedium = TextStyle(
    fontFamily: 'Inter',
    fontWeight: FontWeight.w500,
    fontSize: 14,
    letterSpacing: 0.5,
  );
  
  static const TextStyle bodySmall = TextStyle( // Renamed from caption
    fontFamily: 'Inter',
    fontWeight: FontWeight.normal,
    fontSize: 12,
    letterSpacing: 0.4,
  );
  
  static const TextStyle labelSmall = TextStyle( // Renamed from overline
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