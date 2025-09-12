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
        titleTextStyle: AppTextStyles.titleLarge.copyWith(
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
          textStyle: AppTextStyles.labelLarge.copyWith(
            fontFamily: 'Bangers',
            fontSize: 18,
            letterSpacing: 1.2,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.secondary, // Olive green
          textStyle: AppTextStyles.labelLarge,
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
          textStyle: AppTextStyles.labelLarge.copyWith(
            // Changed from button
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
          borderSide:
              BorderSide(color: AppColors.secondary, width: 2), // Olive green
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide:
              BorderSide(color: AppColors.secondary, width: 2.5), // Olive green
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
        color: AppColors.surfaceLight, // Explicitly set for light theme
      ),
      snackBarTheme: SnackBarThemeData(
        contentTextStyle: _getTextTheme(AppColors.textDark).bodySmall,
        backgroundColor:
            AppColors.greyDark, // Darker background for light theme snackbar
        actionTextColor: AppColors.primaryLight, // Example, adjust as needed
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
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.primary,
        selectionColor: AppColors.primary.withOpacity(0.3),
        selectionHandleColor: AppColors.primary,
      ),
    );
  }

  /// Dark theme configuration: same as light, but with black background
  static ThemeData get darkTheme {
    final base = lightTheme;
    return base.copyWith(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.black,
      colorScheme: base.colorScheme.copyWith(
        brightness: Brightness.dark,
        background: Colors.black,
        surface: Colors.black,
      ),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.white,
        iconTheme:
            IconThemeData(color: AppColors.secondary), // Orange back arrows
      ),
      cardTheme: base.cardTheme.copyWith(
        color: AppColors
            .backgroundLight, // Use tan color for containers in dark mode
      ),
      bottomNavigationBarTheme: base.bottomNavigationBarTheme.copyWith(
        backgroundColor: Colors.black,
      ),
      checkboxTheme: base.checkboxTheme.copyWith(
        checkColor: MaterialStateProperty.all<Color>(Colors.white),
        fillColor: MaterialStateProperty.all<Color>(AppColors.secondary),
      ),
      textTheme: _getTextTheme(
          Color(0xFF728C69)), // Olive green for body text in dark mode
      snackBarTheme: SnackBarThemeData(
        contentTextStyle: _getTextTheme(AppColors.textLight).bodySmall,
        backgroundColor:
            AppColors.greyLight, // Lighter background for dark theme snackbar
        actionTextColor: AppColors.primaryDark, // Example, adjust as needed
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.secondary,
        selectionColor: AppColors.secondary.withOpacity(0.3),
        selectionHandleColor: AppColors.secondary,
      ),
    );
  }

  /// Dark theme configuration with rustic style
  static ThemeData get darkThemeOriginal {
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
        backgroundColor: AppColors.brown, // Darker brown for dark theme app bar
        foregroundColor: AppColors.textLight,
        titleTextStyle: AppTextStyles.titleLarge.copyWith(
          // Changed from headline6
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
          backgroundColor: AppColors.secondaryDark, // Dark olive green
          foregroundColor: AppColors.textLight,
          elevation: 4,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: AppTextStyles.labelLarge.copyWith(
            fontFamily: 'Bangers',
            fontSize: 18,
            letterSpacing: 1.2,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.secondaryLight, // Light olive green
          textStyle: AppTextStyles.labelLarge, // Changed from button
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: BorderSide(
              color: AppColors.secondaryLight, width: 2), // Light olive green
          foregroundColor: AppColors.secondaryLight, // Light olive green
          backgroundColor: AppColors.surfaceDark,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: AppTextStyles.labelLarge.copyWith(
            // Changed from button
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
      snackBarTheme: SnackBarThemeData(
        contentTextStyle: _getTextTheme(AppColors.textLight).bodySmall,
        backgroundColor:
            AppColors.greyLight, // Lighter background for dark theme snackbar
        actionTextColor: AppColors.primaryDark,
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
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.primary,
        selectionColor: AppColors.primary.withOpacity(0.3),
        selectionHandleColor: AppColors.primary,
      ),
    );
  }

  /// Helper to get a text theme with rustic style
  static TextTheme _getTextTheme(Color textColor) {
    return TextTheme(
      displayLarge: AppTextStyles.displayLarge
          .copyWith(color: AppColors.primary), // Was headline1
      displayMedium: AppTextStyles.displayMedium
          .copyWith(color: textColor), // Was headline2
      displaySmall: AppTextStyles.displaySmall
          .copyWith(color: textColor), // Was headline3
      headlineMedium: AppTextStyles.headlineLarge.copyWith(
          color:
              textColor), // Was headline4 (Note: Mapping MD3 headlineMedium to AppTextStyles.headlineLarge)
      headlineSmall: AppTextStyles.headlineMedium.copyWith(
          color:
              textColor), // Was headline5 (Note: Mapping MD3 headlineSmall to AppTextStyles.headlineMedium)
      titleLarge: AppTextStyles.titleLarge
          .copyWith(color: AppColors.brown), // Was headline6
      titleMedium:
          AppTextStyles.titleMedium.copyWith(color: textColor), // Was subtitle1
      titleSmall:
          AppTextStyles.titleSmall.copyWith(color: textColor), // Was subtitle2
      bodyLarge:
          AppTextStyles.bodyLarge.copyWith(color: textColor), // Was body1
      bodyMedium: AppTextStyles.bodyMedium
          .copyWith(color: textColor), // Was body2 (Added copyWith color)
      labelLarge:
          AppTextStyles.labelLarge.copyWith(color: textColor), // Was button
      bodySmall:
          AppTextStyles.bodySmall.copyWith(color: textColor), // Was caption
      labelSmall:
          AppTextStyles.labelSmall.copyWith(color: textColor), // Was overline
    );
  }
}
