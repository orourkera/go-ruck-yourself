import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

/// Custom text field with consistent styling and validation
class CustomTextField extends StatelessWidget {
  /// Controller for the text field
  final TextEditingController controller;
  
  /// Label text for the field
  final String label;
  
  /// Hint text to display when field is empty
  final String hint;
  
  /// Error text to display (overrides validator)
  final String? errorText;
  
  /// Helper text to display below the field
  final String? helperText;
  
  /// Icon to display at the start of the field
  final IconData? prefixIcon;
  
  /// Widget to display at the end of the field
  final Widget? suffixIcon;
  
  /// Whether to obscure text (for passwords)
  final bool obscureText;
  
  /// Keyboard type for the field
  final TextInputType keyboardType;
  
  /// Input formatters for the field
  final List<TextInputFormatter>? inputFormatters;
  
  /// Maximum lines for the field
  final int? maxLines;
  
  /// Minimum lines for the field
  final int? minLines;
  
  /// Maximum length of input
  final int? maxLength;
  
  /// Whether the field is enabled
  final bool enabled;
  
  /// Auto-focus when the field is displayed
  final bool autofocus;
  
  /// Focus node for the field
  final FocusNode? focusNode;
  
  /// Called when text is changed
  final ValueChanged<String>? onChanged;
  
  /// Called when editing is complete
  final VoidCallback? onEditingComplete;
  
  /// Called when field is submitted
  final ValueChanged<String>? onFieldSubmitted;
  
  /// Called when field gets focus
  final VoidCallback? onTap;
  
  /// Validator function for the field
  final FormFieldValidator<String>? validator;
  
  /// Text capitalization for the field
  final TextCapitalization textCapitalization;

  /// Text input action for the field
  final TextInputAction? textInputAction;

  /// Creates a new custom text field
  const CustomTextField({
    Key? key,
    required this.controller,
    required this.label,
    required this.hint,
    this.errorText,
    this.helperText,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.inputFormatters,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.enabled = true,
    this.autofocus = false,
    this.focusNode,
    this.onChanged,
    this.onEditingComplete,
    this.onFieldSubmitted,
    this.onTap,
    this.validator,
    this.textCapitalization = TextCapitalization.none,
    this.textInputAction,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Field label
        if (label.isNotEmpty) ...[
          Text(
            label,
            style: AppTextStyles.subtitle2.copyWith(
              color: Theme.of(context).brightness == Brightness.dark ? Color(0xFF728C69) : AppColors.textDark,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
        ],
        
        // Text field
        TextFormField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hint,
            errorText: errorText,
            helperText: helperText,
            prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
            suffixIcon: suffixIcon,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: enabled
                ? AppColors.surfaceLight
                : AppColors.greyLight.withOpacity(0.5),
            errorStyle: AppTextStyles.caption.copyWith(
              color: AppColors.error,
            ),
            helperStyle: AppTextStyles.caption,
            hintStyle: AppTextStyles.body1.copyWith(
              color: AppColors.textDarkSecondary.withOpacity(0.6),
            ),
          ),
          style: AppTextStyles.body1,
          obscureText: obscureText,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          maxLines: obscureText ? 1 : maxLines,
          minLines: minLines,
          maxLength: maxLength,
          enabled: enabled,
          autofocus: autofocus,
          focusNode: focusNode,
          onChanged: onChanged,
          onEditingComplete: onEditingComplete,
          onFieldSubmitted: onFieldSubmitted,
          onTap: onTap,
          validator: validator,
          textCapitalization: textCapitalization,
          textInputAction: textInputAction,
        ),
      ],
    );
  }
} 