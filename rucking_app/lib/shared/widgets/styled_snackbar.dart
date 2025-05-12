import 'package:flutter/material.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';

/// A utility class that provides badass SnackBars with Bangers font and custom animation
class StyledSnackBar {
  /// Shows a styled SnackBar with Bangers font and custom animation that flows from the bottom
  /// 
  /// [context] - The BuildContext
  /// [message] - The message to display
  /// [duration] - How long to display the message
  /// [isError] - Whether to show as an error (red) or success (normal)
  static void show({
    required BuildContext context,
    required String message,
    Duration? duration,
    bool isError = false,
  }) {
    // Dismiss any existing SnackBars
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    
    // Main and border colors based on type
    final Color mainColor = isError ? AppColors.error : AppColors.secondary;
    final Color borderColor = isError ? AppColors.errorDark : AppColors.secondaryDark;
    final Color shadowColor = isError ? AppColors.errorDark.withOpacity(0.5) : AppColors.secondaryDarkest.withOpacity(0.5);
    
    // Create and show the styled SnackBar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message.toUpperCase(), // EVERYTHING LOOKS MORE BADASS IN CAPS
          style: TextStyle(
            fontFamily: 'Bangers',
            fontSize: 20,
            letterSpacing: 1.5,
            color: AppColors.white,
            shadows: [
              Shadow(
                offset: const Offset(1.0, 1.0),
                blurRadius: 3.0,
                color: Colors.black.withOpacity(0.5),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        backgroundColor: mainColor,
        duration: duration ?? const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: BorderSide(
            color: borderColor,
            width: 3.0,
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        margin: const EdgeInsets.only(
          bottom: 60.0,
          left: 20.0,
          right: 20.0,
        ),
        dismissDirection: DismissDirection.down, // Flow off the bottom
        elevation: 12,
        clipBehavior: Clip.antiAlias,
        action: SnackBarAction( // Subtle dismiss button
          label: 'DISMISS',
          textColor: AppColors.white.withOpacity(0.8),
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
        animation: CurvedAnimation(
          parent: AnimationController(
            vsync: ScaffoldMessenger.of(context),
            duration: const Duration(milliseconds: 600),
          )..forward(),
          curve: Curves.elasticOut,
        ),
      ),
    );
  }
  
  /// Shows a success-styled SnackBar (primary color)
  static void showSuccess({
    required BuildContext context,
    required String message,
    Duration? duration,
  }) {
    show(
      context: context,
      message: message,
      duration: duration,
      isError: false,
    );
  }
  
  /// Shows an error-styled SnackBar (error color)
  static void showError({
    required BuildContext context,
    required String message,
    Duration? duration,
  }) {
    show(
      context: context,
      message: message,
      duration: duration ?? const Duration(seconds: 3),
      isError: true,
    );
  }
}
