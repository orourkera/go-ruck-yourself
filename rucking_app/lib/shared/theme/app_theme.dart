import 'package:flutter/material.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

/// App theme configuration
class AppTheme {
  /// Light theme configuration
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColors.surfaceLight,
        background: AppColors.backgroundLight,
        error: AppColors.error,
      ),
      scaffoldBackgroundColor: AppColors.backgroundLight,
      appBarTheme: AppBarTheme(
        elevation: 0,
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.white,
        titleTextStyle: AppTextStyles.headline6.copyWith(color: AppColors.white),
      ),
      textTheme: _getTextTheme(AppColors.textDark),
      buttonTheme: ButtonThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        buttonColor: AppColors.primary,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: AppTextStyles.button,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: AppTextStyles.button,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: BorderSide(color: AppColors.primary),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: AppTextStyles.button,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceLight,
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.error, width: 2),
        ),
        errorStyle: TextStyle(color: AppColors.error),
      ),
      cardTheme: CardTheme(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        color: AppColors.surfaceLight,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.surfaceLight,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textLight,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.dividerLight,
        thickness: 1,
        space: 1,
      ),
      tabBarTheme: TabBarTheme(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textLight,
        indicatorColor: AppColors.primary,
        labelStyle: AppTextStyles.button,
        unselectedLabelStyle: AppTextStyles.button,
      ),
    );
  }

  /// Dark theme configuration
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: AppColors.primaryDark,
        secondary: AppColors.secondaryDark,
        surface: AppColors.surfaceDark,
        background: AppColors.backgroundDark,
        error: AppColors.errorDark,
      ),
      scaffoldBackgroundColor: AppColors.backgroundDark,
      appBarTheme: AppBarTheme(
        elevation: 0,
        backgroundColor: AppColors.surfaceDark,
        foregroundColor: AppColors.white,
        titleTextStyle: AppTextStyles.headline6.copyWith(color: AppColors.white),
      ),
      textTheme: _getTextTheme(AppColors.textLight),
      buttonTheme: ButtonThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        buttonColor: AppColors.primaryDark,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryDark,
          foregroundColor: AppColors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: AppTextStyles.button,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryDark,
          textStyle: AppTextStyles.button,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryDark,
          side: BorderSide(color: AppColors.primaryDark),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: AppTextStyles.button,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceDark,
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.primaryDark, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.errorDark, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.errorDark, width: 2),
        ),
        errorStyle: TextStyle(color: AppColors.errorDark),
      ),
      cardTheme: CardTheme(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        color: AppColors.surfaceDark,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primaryDark,
        foregroundColor: AppColors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.surfaceDark,
        selectedItemColor: AppColors.primaryDark,
        unselectedItemColor: AppColors.textDarkSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.dividerDark,
        thickness: 1,
        space: 1,
      ),
      tabBarTheme: TabBarTheme(
        labelColor: AppColors.primaryDark,
        unselectedLabelColor: AppColors.textDarkSecondary,
        indicatorColor: AppColors.primaryDark,
        labelStyle: AppTextStyles.button,
        unselectedLabelStyle: AppTextStyles.button,
      ),
    );
  }

  /// Helper to get a text theme with a specific primary color
  static TextTheme _getTextTheme(Color textColor) {
    return TextTheme(
      displayLarge: AppTextStyles.headline1.copyWith(color: textColor),
      displayMedium: AppTextStyles.headline2.copyWith(color: textColor),
      displaySmall: AppTextStyles.headline3.copyWith(color: textColor),
      headlineMedium: AppTextStyles.headline4.copyWith(color: textColor),
      headlineSmall: AppTextStyles.headline5.copyWith(color: textColor),
      titleLarge: AppTextStyles.headline6.copyWith(color: textColor),
      titleMedium: AppTextStyles.subtitle1.copyWith(color: textColor),
      titleSmall: AppTextStyles.subtitle2.copyWith(color: textColor),
      bodyLarge: AppTextStyles.body1.copyWith(color: textColor),
      bodyMedium: AppTextStyles.body2.copyWith(color: textColor),
      labelLarge: AppTextStyles.button.copyWith(color: textColor),
      bodySmall: AppTextStyles.caption.copyWith(color: textColor),
      labelSmall: AppTextStyles.overline.copyWith(color: textColor),
    );
  }
} 