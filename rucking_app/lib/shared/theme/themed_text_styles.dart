import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_text_styles.dart';

/// Themed text styles that automatically adapt to dark/light mode
class ThemedTextStyles {
  /// Get body text style with theme-appropriate color
  static TextStyle bodyLarge(BuildContext context) {
    return AppTextStyles.bodyLarge.copyWith(
      color: AppColors.getTextColor(context),
    );
  }

  static TextStyle bodyMedium(BuildContext context) {
    return AppTextStyles.bodyMedium.copyWith(
      color: AppColors.getTextColor(context),
    );
  }

  static TextStyle bodySmall(BuildContext context) {
    return AppTextStyles.bodySmall.copyWith(
      color: AppColors.getTextColor(context),
    );
  }

  /// Get secondary text style with theme-appropriate color
  static TextStyle bodyLargeSecondary(BuildContext context) {
    return AppTextStyles.bodyLarge.copyWith(
      color: AppColors.getSecondaryTextColor(context),
    );
  }

  static TextStyle bodyMediumSecondary(BuildContext context) {
    return AppTextStyles.bodyMedium.copyWith(
      color: AppColors.getSecondaryTextColor(context),
    );
  }

  /// Get subtle text style (for secondary information)
  static TextStyle bodyLargeSubtle(BuildContext context) {
    return AppTextStyles.bodyLarge.copyWith(
      color: AppColors.getSubtleTextColor(context),
    );
  }

  static TextStyle bodyMediumSubtle(BuildContext context) {
    return AppTextStyles.bodyMedium.copyWith(
      color: AppColors.getSubtleTextColor(context),
    );
  }

  static TextStyle bodySmallSubtle(BuildContext context) {
    return AppTextStyles.bodySmall.copyWith(
      color: AppColors.getSubtleTextColor(context),
    );
  }

  /// Get title styles with theme-appropriate colors
  static TextStyle titleLarge(BuildContext context) {
    return AppTextStyles.titleLarge.copyWith(
      color: AppColors.getTextColor(context),
    );
  }

  static TextStyle titleMedium(BuildContext context) {
    return AppTextStyles.titleMedium.copyWith(
      color: AppColors.getTextColor(context),
    );
  }

  static TextStyle titleSmall(BuildContext context) {
    return AppTextStyles.titleSmall.copyWith(
      color: AppColors.getTextColor(context),
    );
  }

  /// Get location text style (special case for location text)
  static TextStyle locationText(BuildContext context,
      {bool isLadyMode = false}) {
    return AppTextStyles.bodyLarge.copyWith(
      color: AppColors.getLocationTextColor(context, isLadyMode: isLadyMode),
      decoration: TextDecoration.underline,
    );
  }

  /// Get primary colored text (adapts to dark mode)
  static TextStyle primaryText(BuildContext context,
      {bool isLadyMode = false}) {
    return AppTextStyles.bodyLarge.copyWith(
      color: AppColors.getPrimaryTextColor(context, isLadyMode: isLadyMode),
    );
  }

  // Private constructor to prevent instantiation
  ThemedTextStyles._();
}
