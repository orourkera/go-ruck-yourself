import 'package:flutter/material.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

/// App theme configuration with rustic style
class AppTheme {
  /// Light theme configuration with rustic style
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: 'Inter',
      primaryColor: AppColors.primary, // Brownish-orange
      scaffoldBackgroundColor: AppColors.backgroundLight, // Light beige
      colorScheme: ColorScheme.light(
        primary: AppColors.primary, // Brownish-orange
        secondary: AppColors.secondary, // Olive green
        surface: AppColors.surfaceLight,
        background: AppColors.backgroundLight,
        error: AppColors.error,
      ),
      appBarTheme: AppBarTheme(
        elevation: 4,
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.white,
        titleTextStyle: AppTextStyles.headline6.copyWith(
          color: AppColors.white,
          fontSize: 20,
        ),
      ),
      textTheme: _getTextTheme(AppColors.textDark),
      buttonTheme: ButtonThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        buttonColor: AppColors.secondary, // Olive green
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.secondary, // Olive green
          foregroundColor: Colors.white,
          elevation: 4,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: AppTextStyles.button.copyWith(
            fontFamily: 'Bangers',
            fontSize: 18,
            letterSpacing: 1.2,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.secondary, // Olive green
          textStyle: AppTextStyles.button,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: AppColors.secondary, width: 2), // Olive green
          foregroundColor: AppColors.secondary, // Olive green
          backgroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: AppTextStyles.button.copyWith(
            fontFamily: 'Bangers',
            fontSize: 16,
            letterSpacing: 1.0,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.secondary, width: 2), // Olive green
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.secondary, width: 2.5), // Olive green
          borderRadius: BorderRadius.circular(12),
        ),
        errorBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.error, width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.error, width: 2.5),
          borderRadius: BorderRadius.circular(12),
        ),
        labelStyle: TextStyle(color: AppColors.secondary),
      ),
      cardTheme: CardTheme(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        color: AppColors.surfaceLight,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary, // Brownish-orange
        foregroundColor: AppColors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.surfaceLight,
        selectedItemColor: AppColors.primary, // Brownish-orange
        unselectedItemColor: AppColors.textDarkSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.dividerLight,
        thickness: 1,
        space: 1,
      ),
      tabBarTheme: TabBarTheme(
        labelColor: AppColors.primary, // Brownish-orange
        unselectedLabelColor: AppColors.textDarkSecondary,
        indicatorColor: AppColors.primary, // Brownish-orange
        labelStyle: AppTextStyles.tabLabel,
        unselectedLabelStyle: AppTextStyles.tabLabel.copyWith(
          color: AppColors.textDarkSecondary,
        ),
      ),
    );
  }

  /// Dark theme configuration with rustic style
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Inter',
      primaryColor: AppColors.primaryDark,
      scaffoldBackgroundColor: AppColors.backgroundDark,
      colorScheme: ColorScheme.dark(
        primary: AppColors.primaryDark,
        secondary: AppColors.secondaryDark,
        surface: AppColors.surfaceDark,
        background: AppColors.backgroundDark,
        error: AppColors.errorDark,
      ),
      appBarTheme: AppBarTheme(
        elevation: 4,
        backgroundColor: AppColors.brown,
        foregroundColor: AppColors.textLight,
        titleTextStyle: AppTextStyles.headline6.copyWith(
          color: AppColors.textLight,
          fontSize: 20,
        ),
      ),
      textTheme: _getTextTheme(AppColors.textLight),
      buttonTheme: ButtonThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        buttonColor: AppColors.secondaryDark,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.secondaryDark,
          foregroundColor: AppColors.textLight,
          elevation: 4,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: AppTextStyles.button.copyWith(
            fontFamily: 'Bangers',
            fontSize: 18,
            letterSpacing: 1.2,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.secondaryLight,
          textStyle: AppTextStyles.button,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: AppColors.secondaryLight, width: 2),
          foregroundColor: AppColors.secondaryLight,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: AppTextStyles.button.copyWith(
            fontFamily: 'Bangers',
            fontSize: 16,
            letterSpacing: 1.0,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceDark,
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.secondaryDark, width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.secondaryLight, width: 2.5),
          borderRadius: BorderRadius.circular(12),
        ),
        errorBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.errorDark, width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.errorDark, width: 2.5),
          borderRadius: BorderRadius.circular(12),
        ),
        labelStyle: TextStyle(color: AppColors.textLightSecondary),
      ),
      cardTheme: CardTheme(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        color: AppColors.surfaceDark,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primaryDark,
        foregroundColor: AppColors.textLight,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.surfaceDark,
        selectedItemColor: AppColors.primaryLight,
        unselectedItemColor: AppColors.textLightSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.dividerDark,
        thickness: 1,
        space: 1,
      ),
      tabBarTheme: TabBarTheme(
        labelColor: AppColors.primaryLight,
        unselectedLabelColor: AppColors.textLightSecondary,
        indicatorColor: AppColors.primaryLight,
        labelStyle: AppTextStyles.tabLabel,
        unselectedLabelStyle: AppTextStyles.tabLabel.copyWith(
          color: AppColors.textLightSecondary,
        ),
      ),
    );
  }

  /// Helper to get a text theme with rustic style
  static TextTheme _getTextTheme(Color textColor) {
    return TextTheme(
      displayLarge: AppTextStyles.headline1.copyWith(color: AppColors.primary),
      displayMedium: AppTextStyles.headline2.copyWith(color: textColor),
      displaySmall: AppTextStyles.headline3.copyWith(color: textColor),
      headlineMedium: AppTextStyles.headline4.copyWith(color: textColor),
      headlineSmall: AppTextStyles.headline5.copyWith(color: textColor),
      titleLarge: AppTextStyles.headline6.copyWith(color: AppColors.brown),
      titleMedium: AppTextStyles.subtitle1.copyWith(color: textColor),
      titleSmall: AppTextStyles.subtitle2.copyWith(color: textColor),
      bodyLarge: AppTextStyles.body1.copyWith(color: textColor),
      bodyMedium: AppTextStyles.body2,
      labelLarge: AppTextStyles.button.copyWith(color: textColor),
      bodySmall: AppTextStyles.caption.copyWith(color: textColor),
      labelSmall: AppTextStyles.overline.copyWith(color: textColor),
    );
  }
} 