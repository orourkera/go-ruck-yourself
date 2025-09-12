import 'package:flutter/material.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

/// Primary button widget with consistent styling across the app
class PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isFullWidth;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? textColor;
  final EdgeInsetsGeometry? padding;
  final double? borderRadius;
  final bool isLadyMode;

  const PrimaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.isFullWidth = true,
    this.icon,
    this.backgroundColor,
    this.textColor,
    this.padding,
    this.borderRadius,
    this.isLadyMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveBackgroundColor = backgroundColor ??
        (isLadyMode ? AppColors.ladyPrimary : AppColors.primary);
    final effectiveTextColor = textColor ?? Colors.white;
    final isDisabled = onPressed == null && !isLoading;

    return SizedBox(
      width: isFullWidth ? double.infinity : null,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor:
              isDisabled ? AppColors.greyLight : effectiveBackgroundColor,
          foregroundColor: effectiveTextColor,
          disabledBackgroundColor: AppColors.greyLight,
          disabledForegroundColor: AppColors.greyDark,
          elevation: isDisabled ? 0 : 2,
          shadowColor: effectiveBackgroundColor.withOpacity(0.3),
          padding: padding ??
              const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 16,
              ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius ?? 8),
          ),
        ),
        child: _buildButtonContent(),
      ),
    );
  }

  Widget _buildButtonContent() {
    if (isLoading) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                textColor ?? Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Loading...',
            style: AppTextStyles.labelLarge,
          ),
        ],
      );
    }

    if (icon != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(
            text,
            style: AppTextStyles.labelLarge,
          ),
        ],
      );
    }

    return Text(
      text,
      style: AppTextStyles.labelLarge,
    );
  }
}

/// Secondary button variant with outline style
class SecondaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isFullWidth;
  final IconData? icon;
  final Color? borderColor;
  final Color? textColor;
  final EdgeInsetsGeometry? padding;
  final double? borderRadius;
  final bool isLadyMode;

  const SecondaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.isFullWidth = true,
    this.icon,
    this.borderColor,
    this.textColor,
    this.padding,
    this.borderRadius,
    this.isLadyMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveBorderColor =
        borderColor ?? (isLadyMode ? AppColors.ladyPrimary : AppColors.primary);
    final effectiveTextColor = textColor ?? effectiveBorderColor;
    final isDisabled = onPressed == null && !isLoading;

    return SizedBox(
      width: isFullWidth ? double.infinity : null,
      child: OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: effectiveTextColor,
          disabledForegroundColor: AppColors.greyDark,
          padding: padding ??
              const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 16,
              ),
          side: BorderSide(
            color: isDisabled ? AppColors.greyLight : effectiveBorderColor,
            width: 1.5,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius ?? 8),
          ),
        ),
        child: _buildButtonContent(),
      ),
    );
  }

  Widget _buildButtonContent() {
    if (isLoading) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                textColor ?? AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Loading...',
            style: AppTextStyles.labelLarge.copyWith(
              color: textColor ?? AppColors.primary,
            ),
          ),
        ],
      );
    }

    if (icon != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(
            text,
            style: AppTextStyles.labelLarge.copyWith(
              color: textColor ?? AppColors.primary,
            ),
          ),
        ],
      );
    }

    return Text(
      text,
      style: AppTextStyles.labelLarge.copyWith(
        color: textColor ?? AppColors.primary,
      ),
    );
  }
}
