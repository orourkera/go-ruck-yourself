import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/home_screen.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/custom_button.dart';
import 'package:rucking_app/shared/widgets/custom_text_field.dart';
import 'package:rucking_app/shared/utils/error_mapper.dart';
import 'package:rucking_app/features/health_integration/bloc/health_bloc.dart';
import 'package:rucking_app/features/health_integration/domain/health_service.dart';
import 'package:rucking_app/features/health_integration/presentation/screens/health_integration_intro_screen.dart';
import 'package:rucking_app/shared/widgets/styled_snackbar.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:url_launcher/url_launcher.dart';

/// Screen for registering new users
class RegisterScreen extends StatefulWidget {
  final String? prefilledEmail;
  final String? prefilledDisplayName;
  
  const RegisterScreen({
    Key? key,
    this.prefilledEmail,
    this.prefilledDisplayName,
  }) : super(key: key);

  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _weightController = TextEditingController();
  final _displayNameFocusNode = FocusNode();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _confirmPasswordFocusNode = FocusNode();
  final _weightFocusNode = FocusNode();
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _preferMetric = false; // Default to Standard (lbs)
  bool _acceptTerms = false;
  String _selectedGender = 'male'; // Default to male
  
  // Dynamically get primary color based on selected gender
  Color get _primaryColor => _selectedGender == 'female' ? AppColors.ladyPrimary : AppColors.primary;
  
  // Check if this is Google registration
  // A user might be coming from Google registration flow even if tokens are null
  // We should consider it a Google registration if any Google data is provided
  bool get _isGoogleRegistration => 
      widget.prefilledEmail != null || 
      widget.prefilledDisplayName != null;

  @override
  void initState() {
    super.initState();
    
    // Pre-fill controllers with Google data if available
    if (widget.prefilledEmail != null) {
      _emailController.text = widget.prefilledEmail!;
    }
    if (widget.prefilledDisplayName != null) {
      _displayNameController.text = widget.prefilledDisplayName!;
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _weightController.dispose();
    _displayNameFocusNode.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    _weightFocusNode.dispose();
    super.dispose();
  }

  /// Validates form and registers a new user
  void _register() {
    if (_formKey.currentState!.validate()) {
      if (!_acceptTerms) {
        StyledSnackBar.showError(
          context: context,
          message: 'Please accept the terms and conditions',
          animationStyle: SnackBarAnimationStyle.slideUpBounce,
        );
        return;
      }

      double? weight = _weightController.text.isEmpty
          ? null
          : double.tryParse(_weightController.text);
      // If user prefers metric, do nothing. If standard, convert lbs to kg before sending
      if (weight != null && !_preferMetric) {
        weight = weight * 0.453592;
      }

      if (_isGoogleRegistration) {
        // Google registration flow - handle cases where tokens may be null
        // If tokens are null, we'll still try to use the Google info we have
        AppLogger.info('Proceeding with Google registration');
        context.read<AuthBloc>().add(
          AuthGoogleRegisterRequested(
            username: _displayNameController.text.trim(),
            email: _emailController.text.trim(),
            displayName: widget.prefilledDisplayName ?? _displayNameController.text.trim(),
            weightKg: weight,
            preferMetric: _preferMetric,
            heightCm: null,
            dateOfBirth: null,
            gender: _selectedGender,
          ),
        );
      } else {
        // Regular registration flow
        context.read<AuthBloc>().add(
          AuthRegisterRequested(
            username: _displayNameController.text.trim(),
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
            weightKg: weight,
            preferMetric: _preferMetric,
            heightCm: null,
            dateOfBirth: null,
            gender: _selectedGender,
          ),
        );
      }
    }
  }

  String _friendlyErrorMessage(dynamic error) {
  // Always convert error to a String safely, even if it's null or not a String
  if (error == null) return 'An unknown error occurred.';
  if (error is String) return mapFriendlyErrorMessage(error);
  // If error has a message property, try to use it
  if (error is Exception && error.toString().isNotEmpty) {
    return mapFriendlyErrorMessage(error.toString());
  }
  return mapFriendlyErrorMessage(error.toString());
}

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is Authenticated) {
          // Force app-wide theme rebuild with the new user settings
          // This ensures gender-based theme is applied immediately after registration
          Future.delayed(Duration.zero, () {
            // Navigate based on platform - only iOS has Apple Health integration
            if (Platform.isIOS) {
              // Navigate to Apple Health integration screen on iOS
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => BlocProvider(
                    create: (context) => HealthBloc(
                      healthService: HealthService(),
                      userId: state.user.userId, // Pass the user ID from authenticated state
                    ),
                    child: HealthIntegrationIntroScreen(
                      userId: state.user.userId, // Pass the user ID to the intro screen
                    ),
                  ),
                ),
              );
            } else {
              // Navigate directly to HomeScreen on Android and other platforms
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const HomeScreen()),
              );
            }
          });
        } else if (state is AuthUserAlreadyExists) {
          // Using a custom widget with clickable login button
          final content = Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('EMAIL ALREADY IN USE. ', 
                style: TextStyle(
                  fontFamily: 'Bangers',
                  fontSize: 20.0,
                  letterSpacing: 1.5,
                  color: Colors.white,
                ),
              ),
              GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                },
                child: const Text(
                  'LOGIN',
                  style: TextStyle(
                    fontFamily: 'Bangers',
                    fontSize: 20.0,
                    letterSpacing: 1.5,
                    color: Colors.white,
                    decoration: TextDecoration.underline,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
          
          // Show error with the custom widget
          StyledSnackBar.showError(
            context: context,
            message: '', // Empty because we're using a custom widget
          );
          
          // Insert our custom widget into the overlay (similar to how StyledSnackBar does it)
          final overlayState = Overlay.of(context);
          final overlayEntry = OverlayEntry(
            builder: (context) => Positioned(
              bottom: MediaQuery.of(context).viewInsets.bottom + 32,
              left: 20,
              right: 20,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(15.0),
                    border: Border.all(
                      color: AppColors.errorDark,
                      width: 2.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.errorDark.withOpacity(0.5),
                        offset: const Offset(0, 3),
                        blurRadius: 6.0,
                        spreadRadius: 1.0,
                      ),
                    ],
                  ),
                  child: content,
                ),
              ),
            ),
          );
          
          overlayState.insert(overlayEntry);
          
          // Remove after delay
          Future.delayed(const Duration(seconds: 4), () {
            overlayEntry.remove();
          });
        } else if (state is AuthError) {
          StyledSnackBar.showError(
            context: context,
            message: _friendlyErrorMessage(state.message),
            animationStyle: SnackBarAnimationStyle.popIn,
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Register')),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 40),
            child: Form(
              key: _formKey,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 18.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        'CREATE ACCOUNT',
                        style: AppTextStyles.titleLarge.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Display Name Field
                    CustomTextField(
                      controller: _displayNameController,
                      label: 'What should we call you, rucker?',
                      hint: 'Enter your display name',
                      prefixIcon: Icons.person_outline,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a display name';
                        }
                        if (value.length < 3) {
                          return 'Display name must be at least 3 characters';
                        }
                        // Basic alphanumeric check (allow underscore)
                        if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value)) {
                          return 'Display name can only contain letters, numbers, and underscores';
                        }
                        return null;
                      },
                      textInputAction: TextInputAction.next,
                      focusNode: _displayNameFocusNode,
                      onFieldSubmitted: (_) {
                        FocusScope.of(context).requestFocus(_emailFocusNode);
                      },
                    ),
                    const SizedBox(height: 16),
                    // Email Field
                    CustomTextField(
                      controller: _emailController,
                      label: 'Email',
                      hint: 'Enter your email address',
                      prefixIcon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      focusNode: _emailFocusNode,
                      onFieldSubmitted: (_) {
                        FocusScope.of(context).requestFocus(_passwordFocusNode);
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your email';
                        }
                        if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
                          return 'Please enter a valid email address';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    // Password field - only show for regular registration
                    if (!_isGoogleRegistration) ...[
                      CustomTextField(
                        controller: _passwordController,
                        label: 'Password',
                        hint: 'Password',
                        prefixIcon: Icons.lock_outline,
                        obscureText: !_isPasswordVisible,
                        textInputAction: TextInputAction.next,
                        suffixIcon: IconButton(
                          icon: Icon(_isPasswordVisible ? Icons.visibility_off : Icons.visibility),
                          onPressed: () {
                            setState(() {
                              _isPasswordVisible = !_isPasswordVisible;
                            });
                          },
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter a password';
                          }
                          if (value.length < 6) {
                            return 'Password must be at least 6 characters';
                          }
                          return null;
                        },
                        focusNode: _passwordFocusNode,
                        onFieldSubmitted: (_) {
                          FocusScope.of(context).requestFocus(_confirmPasswordFocusNode);
                        },
                      ),
                      const SizedBox(height: 16),
                      // Confirm Password field
                      CustomTextField(
                        controller: _confirmPasswordController,
                        label: 'Confirm Password',
                        hint: 'Confirm Password',
                        prefixIcon: Icons.lock_outline,
                        obscureText: !_isConfirmPasswordVisible,
                        textInputAction: TextInputAction.next,
                        focusNode: _confirmPasswordFocusNode,
                        suffixIcon: IconButton(
                          icon: Icon(_isConfirmPasswordVisible ? Icons.visibility_off : Icons.visibility),
                          onPressed: () {
                            setState(() {
                              _isConfirmPasswordVisible = !_isConfirmPasswordVisible;
                            });
                          },
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please confirm your password';
                          }
                          if (value != _passwordController.text) {
                            return 'Passwords do not match';
                          }
                          return null;
                        },
                        onFieldSubmitted: (_) {
                          FocusScope.of(context).requestFocus(_weightFocusNode);
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                    // Google registration info
                    if (_isGoogleRegistration) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _primaryColor.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: _primaryColor, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'You\'ll sign in with Google - no password needed!',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: _primaryColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    // Weight unit preference
                    Text('Preferred Units', style: AppTextStyles.titleMedium),
                    Row(
                      children: [
                        Text(
                          'Standard',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: !_preferMetric ? _primaryColor : AppColors.grey,
                          ),
                        ),
                        Switch(
                          value: _preferMetric,
                          activeColor: _primaryColor,
                          onChanged: (value) {
                            setState(() {
                              _preferMetric = value;
                              _weightController.clear();
                            });
                          },
                        ),
                        Text(
                          'Metric',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: _preferMetric ? _primaryColor : AppColors.grey,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Weight input field
                    CustomTextField(
                      controller: _weightController,
                      label: _preferMetric ? 'Weight (kg)' : 'Weight (lbs)',
                      hint: _preferMetric ? 'Enter your weight in kg' : 'Enter your weight in lbs',
                      keyboardType: TextInputType.number,
                      prefixIcon: Icons.monitor_weight_outlined,
                      textInputAction: TextInputAction.done,
                      focusNode: _weightFocusNode,
                      onFieldSubmitted: (_) {
                        FocusScope.of(context).unfocus();
                      },
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Gender selection toggle
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 8.0, bottom: 8.0),
                          child: Row(
                            children: [
                              Icon(Icons.person_outline, color: AppColors.grey),
                              const SizedBox(width: 8),
                              Text(
                                'Gender',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).brightness == Brightness.dark
                                ? Colors.grey[800]
                                : Colors.grey[200],
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedGender = 'male';
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    decoration: BoxDecoration(
                                      color: _selectedGender == 'male'
                                          ? _primaryColor
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Center(
                                      child: Text(
                                        'M',
                                        style: AppTextStyles.bodyLarge.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: _selectedGender == 'male'
                                              ? Colors.white
                                              : AppColors.grey,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedGender = 'female';
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    decoration: BoxDecoration(
                                      color: _selectedGender == 'female'
                                          ? _primaryColor
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Center(
                                      child: Text(
                                        'F',
                                        style: AppTextStyles.bodyLarge.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: _selectedGender == 'female'
                                              ? Colors.white
                                              : AppColors.grey,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Explanation text for gender, weight, and height fields
                    Text(
                      'Gender and weight information helps calculate calories more accurately and personalize your experience.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: Theme.of(context).brightness == Brightness.dark ? Color(0xFF728C69) : AppColors.textDarkSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    // Terms and Conditions Checkbox
                    Row(
                      children: [
                        Checkbox(
                          value: _acceptTerms,
                          onChanged: (value) {
                            setState(() {
                              _acceptTerms = value ?? false;
                            });
                          },
                          activeColor: _primaryColor,
                        ),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: Theme.of(context).textTheme.bodyMedium?.color,
                              ),
                              children: [
                                const TextSpan(text: 'I accept the '),
                                TextSpan(
                                  text: 'Terms of Service',
                                  style: const TextStyle(decoration: TextDecoration.underline),
                                  recognizer: (TapGestureRecognizer()
                                    ..onTap = () async {
                                      final uri = Uri.parse('https://getrucky.com/terms');
                                      if (await canLaunchUrl(uri)) {
                                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                                      }
                                    }),
                                ),
                                const TextSpan(text: ' and '),
                                TextSpan(
                                  text: 'Privacy Policy',
                                  style: const TextStyle(decoration: TextDecoration.underline),
                                  recognizer: (TapGestureRecognizer()
                                    ..onTap = () async {
                                      final uri = Uri.parse('https://getrucky.com/privacy');
                                      if (await canLaunchUrl(uri)) {
                                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                                      }
                                    }),
                                ),
                                const TextSpan(text: '.'),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Register Button
                    BlocBuilder<AuthBloc, AuthState>(
                      builder: (context, state) {
                        return CustomButton(
                          text: 'CREATE ACCOUNT',
                          isLoading: state is AuthLoading,
                          onPressed: _register,
                          color: _primaryColor,
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    // Login Link
                    Center(
                      child: TextButton(
                        onPressed: () {
                          Navigator.of(context).pop(); // Go back to login screen
                        },
                        child: Text(
                          'Already have an account? Sign In',
                          style: AppTextStyles.bodyMedium.copyWith(color: _primaryColor),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}