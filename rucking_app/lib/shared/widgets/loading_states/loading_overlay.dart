import 'package:flutter/material.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

/// Loading overlay widget that covers the entire screen
class LoadingOverlay extends StatelessWidget {
  final String? message;
  final bool isVisible;
  final Widget child;
  final Color? backgroundColor;
  final Color? indicatorColor;

  const LoadingOverlay({
    super.key,
    required this.child,
    this.message,
    this.isVisible = false,
    this.backgroundColor,
    this.indicatorColor,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isVisible)
          Container(
            color: (backgroundColor ?? Colors.black).withOpacity(0.5),
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        indicatorColor ?? AppColors.primary,
                      ),
                    ),
                    if (message != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        message!,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textDark,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Simple loading overlay with just a spinner
class SimpleLoadingOverlay extends StatelessWidget {
  final bool isVisible;
  final Widget child;
  final Color? indicatorColor;

  const SimpleLoadingOverlay({
    super.key,
    required this.child,
    this.isVisible = false,
    this.indicatorColor,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isVisible)
          Container(
            color: Colors.black.withOpacity(0.3),
            child: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  indicatorColor ?? AppColors.primary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Loading overlay with custom content
class CustomLoadingOverlay extends StatelessWidget {
  final bool isVisible;
  final Widget child;
  final Widget loadingWidget;
  final Color? backgroundColor;

  const CustomLoadingOverlay({
    super.key,
    required this.child,
    required this.loadingWidget,
    this.isVisible = false,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isVisible)
          Container(
            color: (backgroundColor ?? Colors.black).withOpacity(0.5),
            child: Center(child: loadingWidget),
          ),
      ],
    );
  }
}
