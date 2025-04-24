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
import 'package:keyboard_actions/keyboard_actions.dart';

/// Screen for registering new users
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({Key? key}) : super(key: key);

  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _weightController = TextEditingController();
  final _confirmPasswordFocusNode = FocusNode();
  final _weightFocusNode = FocusNode();
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _acceptTerms = false;
  bool _preferMetric = false; // Default to standard instead of metric

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _weightController.dispose();
    _weightFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
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
          displayName: _nameController.text.trim(),
          name: _nameController.text.trim(), // Using same value for backend compatibility
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
          weightKg: weight,
          preferMetric: _preferMetric,
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
          // Navigate to home screen after successful registration
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        } else if (state is AuthUserAlreadyExists) {
          // Show special error message with sign-in link
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text('An account already exists for this email.')),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pushReplacementNamed('/login');
                    },
                    child: Text(
                      'Sign In',
                      style: TextStyle(
                        color: Colors.white, 
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
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: AppColors.textDark,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: SafeArea(
          child: KeyboardActions(
            config: KeyboardActionsConfig(
              actions: [
                KeyboardActionsItem(
                  focusNode: _weightFocusNode,
                  toolbarButtons: [
                    (node) {
                      return GestureDetector(
                        onTap: () => node.unfocus(),
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text('Done', style: TextStyle(color: Colors.blue)),
                        ),
                      );
                    }
                  ],
                ),
              ],
            ),
            child: Stack(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 18.0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 8),
                          Center(
                            child: Text(
                              'CREATE ACCOUNT',
                              style: AppTextStyles.headline6.copyWith(
                                fontSize: 24,
                                letterSpacing: 1.5,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),
                          CustomTextField(
                            controller: _nameController,
                            label: 'What should we call you, rucker?',
                            hint: 'Name',
                            prefixIcon: Icons.person_outline,
                            textInputAction: TextInputAction.next,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your name';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),
                          CustomTextField(
                            controller: _emailController,
                            label: 'Email',
                            hint: 'Email',
                            prefixIcon: Icons.email_outlined,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your email';
                              }
                              if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                                return 'Please enter a valid email';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),
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
                            onFieldSubmitted: (_) {
                              FocusScope.of(context).requestFocus(_confirmPasswordFocusNode);
                            },
                          ),
                          const SizedBox(height: 20),
                          CustomTextField(
                            controller: _confirmPasswordController,
                            label: 'Confirm Password',
                            hint: 'Confirm Password',
                            prefixIcon: Icons.lock_outline,
                            obscureText: !_isConfirmPasswordVisible,
                            textInputAction: TextInputAction.done,
                            focusNode: _confirmPasswordFocusNode,
                            onFieldSubmitted: (_) {
                              FocusScope.of(context).unfocus();
                            },
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
                          ),
                          const SizedBox(height: 20),
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
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Text(
                                'Measurement units:',
                                style: AppTextStyles.subtitle1,
                              ),
                              const Spacer(),
                              Text(
                                'Standard',
                                style: AppTextStyles.body2.copyWith(
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
                                style: AppTextStyles.body2.copyWith(
                                  color: _preferMetric ? AppColors.primary : AppColors.grey,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 30),
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
                                  style: AppTextStyles.body2,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          BlocBuilder<AuthBloc, AuthState>(
                            builder: (context, state) {
                              return CustomButton(
                                text: 'Create Account',
                                isLoading: state is AuthLoading,
                                onPressed: _register,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}