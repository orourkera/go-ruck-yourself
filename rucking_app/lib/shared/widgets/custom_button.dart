import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

/// Custom button with loading state and various customization options
class CustomButton extends StatelessWidget {
  /// Text to display on the button
  final String text;

  /// Called when button is pressed
  final VoidCallback? onPressed;

  /// Whether the button should display a loading indicator
  final bool isLoading;

  /// Icon to display before text (optional)
  final IconData? icon;

  /// Button color (defaults to primary color)
  final Color? color;

  /// Text color (defaults to white)
  final Color? textColor;

  /// Width of the button (defaults to maximum width)
  final double? width;

  /// Height of the button (defaults to 56)
  final double height;

  /// Border radius of the button (defaults to 8)
  final double borderRadius;

  /// Elevation of the button (defaults to 0)
  final double elevation;

  /// Whether the button is outlined (defaults to false)
  final bool isOutlined;

  /// Creates a new custom button
  const CustomButton({
    Key? key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    this.color,
    this.textColor,
    this.width,
    this.height = 56,
    this.borderRadius = 8,
    this.elevation = 0,
    this.isOutlined = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Check if we're in lady mode
    bool isLadyMode = false;
    try {
      final authState = context.read<AuthBloc>().state;
      if (authState is Authenticated) {
        isLadyMode = authState.user.gender == 'female';
      }
    } catch (e) {
      // If can't access AuthBloc, continue with default colors
    }

    // Use lady colors for female users if no explicit color is provided
    final buttonColor =
        color ?? (isLadyMode ? AppColors.ladyPrimary : AppColors.primary);
    final buttonTextColor = textColor ?? Colors.white;

    if (isOutlined) {
      return SizedBox(
        width: width,
        height: height,
        child: OutlinedButton(
          onPressed: isLoading ? null : onPressed,
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: buttonColor),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(borderRadius),
            ),
          ),
          child: _buildButtonContent(buttonColor, isLadyMode),
        ),
      );
    }

    return SizedBox(
      width: width,
      height: height,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: buttonColor,
          foregroundColor: buttonTextColor,
          elevation: elevation,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
        ),
        child: _buildButtonContent(buttonTextColor, isLadyMode),
      ),
    );
  }

  /// Builds the content of the button (text, icon, or loading indicator)
  Widget _buildButtonContent(Color contentColor, bool isLadyMode) {
    if (isLoading) {
      return SizedBox(
        height: 24,
        width: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(
            isOutlined
                ? (isLadyMode ? AppColors.ladyPrimary : AppColors.primary)
                : Colors.white,
          ),
        ),
      );
    }

    if (icon != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: contentColor),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.labelLarge.copyWith(
                color: contentColor,
              ),
            ),
          ),
        ],
      );
    }

    return Text(
      text,
      style: AppTextStyles.labelLarge.copyWith(
        color: contentColor,
      ),
    );
  }
}
