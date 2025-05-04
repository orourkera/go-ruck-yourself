import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// Screen for registering new users
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({Key? key}) : super(key: key);

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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please accept the terms and conditions'),
            backgroundColor: Colors.red,
          ),
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

      context.read<AuthBloc>().add(
        AuthRegisterRequested(
          username: _displayNameController.text.trim(),
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
          weightKg: weight,
          preferMetric: _preferMetric,
          heightCm: null,
          dateOfBirth: null,
        ),
      );
    }
  }

  String _friendlyErrorMessage(String? error) {
    return mapFriendlyErrorMessage(error);
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is Authenticated) {
          // Navigate to Apple Health integration screen after successful registration
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
        } else if (state is AuthUserAlreadyExists) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Text('Email already in use. '),
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                    },
                    child: const Text(
                      'Login',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.red,
            ),
          );
        } else if (state is AuthError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_friendlyErrorMessage(state.message)),
              backgroundColor: Colors.red,
            ),
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
                    // Password field
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
                    const SizedBox(height: 24),
                    // Weight unit preference
                    Text('Preferred Units', style: AppTextStyles.titleMedium),
                    Row(
                      children: [
                        Text(
                          'Standard',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: !_preferMetric ? AppColors.primary : AppColors.grey,
                          ),
                        ),
                        Switch(
                          value: _preferMetric,
                          activeColor: AppColors.primary,
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
                            color: _preferMetric ? AppColors.primary : AppColors.grey,
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
                          activeColor: AppColors.primary,
                        ),
                        Expanded(
                          child: Text(
                            'I accept the Terms and Conditions and Privacy Policy',
                            style: AppTextStyles.bodyMedium,
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
                          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary),
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