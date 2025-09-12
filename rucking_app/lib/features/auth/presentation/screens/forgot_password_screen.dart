import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/custom_button.dart';
import 'package:rucking_app/shared/widgets/custom_text_field.dart';
import 'package:rucking_app/shared/utils/error_mapper.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({Key? key}) : super(key: key);

  @override
  _ForgotPasswordScreenState createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isLoading = false;
  String? _message;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _sendResetLink() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
        _message = null;
      });
      try {
        final response = await http.post(
          Uri.parse('https://getrucky.com/api/auth/forgot-password'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': _emailController.text.trim()}),
        );
        final data = jsonDecode(response.body);
        if (response.statusCode == 200) {
          // Success - show success message
          setState(() {
            _message = data['message'] ??
                'If an account exists for this email, a password reset link has been sent.';
          });
          // Show success and navigate back after delay
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              Navigator.of(context).pop(); // Go back to login
            }
          });
        } else {
          // Error - show in SnackBar and navigate back to login
          final errorMessage = mapFriendlyErrorMessage(
              data['message'] ?? 'Failed to send reset link.');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMessage),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 4),
              ),
            );
            Navigator.of(context).pop(); // Go back to login
          }
        }
      } catch (e) {
        // Exception - show in SnackBar and navigate back to login
        final errorMessage = mapFriendlyErrorMessage(e.toString());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
          Navigator.of(context).pop(); // Go back to login
        }
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot Password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 32),
                // Lost Rucker Image
                Center(
                  child: Image.asset(
                    'assets/images/lost rucker.png',
                    width: 200,
                    height: 200,
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  'Enter your email to receive a password reset link.',
                  style: AppTextStyles.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                CustomTextField(
                  controller: _emailController,
                  label: 'Email',
                  hint: 'Enter your email',
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return mapFriendlyErrorMessage('Please enter your email');
                    }
                    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
                      return mapFriendlyErrorMessage(
                          'Please enter a valid email');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                if (_message != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.success),
                    ),
                    child: Text(
                      _message!,
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.success),
                      textAlign: TextAlign.center,
                    ),
                  ),
                if (_message != null) const SizedBox(height: 24),
                CustomButton(
                  text: 'Send Reset Link',
                  onPressed: _isLoading ? null : _sendResetLink,
                  isLoading: _isLoading,
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Back to Login'),
                ),
                const SizedBox(height: 32), // Extra padding at bottom
              ],
            ),
          ),
        ),
      ),
    );
  }
}
