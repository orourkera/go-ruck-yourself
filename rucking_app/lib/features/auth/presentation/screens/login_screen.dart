import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/auth/presentation/screens/register_screen.dart';
import 'package:rucking_app/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/home_screen.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/custom_button.dart';
import 'package:rucking_app/shared/widgets/custom_text_field.dart';
import 'package:rucking_app/shared/utils/error_mapper.dart';
import 'package:rucking_app/shared/widgets/styled_snackbar.dart';

/// Login screen for user authentication
class LoginScreen extends StatefulWidget {
  LoginScreen({Key? key}) : super(key: key);

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  bool _isPasswordVisible = false;
  bool _rememberMe = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  /// Validates form and attempts login
  void _login() {
    if (_formKey.currentState!.validate()) {
      context.read<AuthBloc>().add(
            AuthLoginRequested(
              email: _emailController.text.trim(),
              password: _passwordController.text.trim(),
            ),
          );
    }
  }

  void _handleGoogleLogin() {
    context.read<AuthBloc>().add(AuthGoogleLoginRequested());
  }

  void _handleAppleLogin() {
    context.read<AuthBloc>().add(AuthAppleLoginRequested());
  }

  bool _isFormValid() {
    return _formKey.currentState!.validate();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is Authenticated) {
          // Revert to direct navigation to HomeScreen after login
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => HomeScreen()),
          );
        } else if (state is GoogleUserNeedsRegistration) {
          // Navigate to registration screen with Google user data pre-filled
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => RegisterScreen(
                prefilledEmail: state.email,
                prefilledDisplayName: state.displayName,
              ),
            ),
          );
        } else if (state is AuthError) {
          // Show error message if login fails using the styled snackbar
          StyledSnackBar.showError(
            context: context,
            message: mapFriendlyErrorMessage(state.message),
          );
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 48),

                  // Title
                  Text(
                    'WELCOME BACK',
                    style: TextStyle(
                      fontFamily: 'Bangers',
                      fontSize: 32,
                      letterSpacing: 1.5,
                      color: AppColors.textDark,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // Google Sign-In Button
                  OutlinedButton.icon(
                    onPressed: _handleGoogleLogin,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      side: BorderSide(color: AppColors.primary),
                    ),
                    icon: Icon(
                      Icons.g_translate, // You can replace with Google icon
                      color: AppColors.primary,
                    ),
                    label: Text(
                      'Continue with Google',
                      style: AppTextStyles.labelLarge.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Apple Sign-In Button (iOS only)
                  if (Platform.isIOS) ...[
                    OutlinedButton.icon(
                      onPressed: _handleAppleLogin,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        side: BorderSide(color: AppColors.textDark),
                        backgroundColor: AppColors.textDark,
                      ),
                      icon: Icon(
                        Icons.apple,
                        color: Colors.white,
                      ),
                      label: Text(
                        'Continue with Apple',
                        style: AppTextStyles.labelLarge.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),

                  // OR divider
                  Row(
                    children: [
                      Expanded(
                          child: Divider(color: AppColors.textDarkSecondary)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'OR',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textDarkSecondary,
                          ),
                        ),
                      ),
                      Expanded(
                          child: Divider(color: AppColors.textDarkSecondary)),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Email field
                  CustomTextField(
                    controller: _emailController,
                    label: 'Email',
                    hint: 'Enter your email',
                    keyboardType: TextInputType.emailAddress,
                    prefixIcon: Icons.email_outlined,
                    textInputAction: TextInputAction.next,
                    focusNode: _emailFocusNode,
                    onTap: () {
                      FocusScope.of(context).requestFocus(_emailFocusNode);
                    },
                    onFieldSubmitted: (_) {
                      FocusScope.of(context).requestFocus(_passwordFocusNode);
                    },
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your email';
                      }
                      if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                          .hasMatch(value)) {
                        return 'Please enter a valid email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),

                  // Password field
                  CustomTextField(
                    controller: _passwordController,
                    label: 'Password',
                    hint: 'Enter your password',
                    obscureText: !_isPasswordVisible,
                    prefixIcon: Icons.lock_outline,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _isPasswordVisible
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: AppColors.grey,
                      ),
                      onPressed: () {
                        setState(() {
                          _isPasswordVisible = !_isPasswordVisible;
                        });
                      },
                    ),
                    focusNode: _passwordFocusNode,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _login(),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your password';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Remember me and Forgot password
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Remember me checkbox
                      Row(
                        children: [
                          Checkbox(
                            value: _rememberMe,
                            onChanged: (value) {
                              setState(() {
                                _rememberMe = value ?? false;
                              });
                            },
                            activeColor: AppColors.primary,
                          ),
                          Text(
                            'Remember me',
                            style: AppTextStyles.bodyMedium,
                          ),
                        ],
                      ),

                      // Forgot password
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => ForgotPasswordScreen(),
                            ),
                          );
                        },
                        child: Text(
                          'Forgot password?',
                          style: AppTextStyles.bodyMedium
                              .copyWith(color: AppColors.primary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Login button
                  BlocBuilder<AuthBloc, AuthState>(
                    builder: (context, state) {
                      return CustomButton(
                        text: 'LOGIN',
                        isLoading: state is AuthLoading,
                        onPressed: _login,
                      );
                    },
                  ),
                  const SizedBox(height: 32),

                  // Register link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Don't have an account? ",
                        style: AppTextStyles.bodyMedium,
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => RegisterScreen(),
                            ),
                          );
                        },
                        child: Text(
                          'Sign Up',
                          style: TextStyle(
                            fontFamily: 'Bangers',
                            fontSize: 16,
                            letterSpacing: 1.0,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
