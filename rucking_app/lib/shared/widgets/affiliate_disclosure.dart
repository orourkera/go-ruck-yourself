import 'package:flutter/material.dart';

/// Simple, reusable affiliate disclosure banner.
/// Place near gear lists/details and buy CTAs to satisfy FTC/Amazon policies.
class AffiliateDisclosure extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  final TextStyle? textStyle;
  final Color? backgroundColor;
  final BorderRadius? borderRadius;

  const AffiliateDisclosure({
    super.key,
    this.padding = const EdgeInsets.all(12),
    this.textStyle,
    this.backgroundColor,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ??
            theme.colorScheme.surfaceVariant.withOpacity(0.6),
        borderRadius: borderRadius ?? BorderRadius.circular(8),
      ),
      child: Text(
        'Disclosure: We may earn a commission from qualifying purchases (e.g., Amazon Associates).',
        style: textStyle ?? theme.textTheme.bodySmall,
      ),
    );
  }
}
