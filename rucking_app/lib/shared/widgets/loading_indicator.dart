import 'package:flutter/material.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';

/// Reusable loading indicator widget
class LoadingIndicator extends StatelessWidget {
  final double? size;
  final Color? color;
  final String? message;

  const LoadingIndicator({
    Key? key,
    this.size,
    this.color,
    this.message,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: size ?? 32,
          height: size ?? 32,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation<Color>(
              color ?? AppColors.primary,
            ),
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: 16),
          Text(
            message!,
            style: TextStyle(
              color: AppColors.textDarkSecondary,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}
