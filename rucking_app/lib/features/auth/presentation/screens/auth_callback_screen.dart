import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';

class AuthCallbackScreen extends StatefulWidget {
  final Uri uri;
  
  const AuthCallbackScreen({
    super.key,
    required this.uri,
  });

  @override
  State<AuthCallbackScreen> createState() => _AuthCallbackScreenState();
}

class _AuthCallbackScreenState extends State<AuthCallbackScreen> {
  @override
  void initState() {
    super.initState();
    _handleAuthCallback();
  }

  void _handleAuthCallback() {
    final uri = widget.uri;
    final queryParams = uri.queryParameters;
    
    // Check what type of callback this is
    final type = queryParams['type'];
    final accessToken = queryParams['access_token'];
    final refreshToken = queryParams['refresh_token'];
    
    if (type == 'recovery' && accessToken != null) {
      // This is a password reset callback
      // Navigate to password reset screen with the token
      Navigator.of(context).pushReplacementNamed(
        '/password_reset',
        arguments: accessToken,
      );
    } else if (type == 'signup') {
      // Email confirmation callback
      _showSuccessAndRedirect('Email confirmed successfully!');
    } else if (accessToken != null) {
      // General authentication callback
      // Could be from OAuth or other auth flows
      _showSuccessAndRedirect('Authentication successful!');
    } else {
      // Handle error cases
      final error = queryParams['error_description'] ?? queryParams['error'] ?? 'Unknown error';
      _showErrorAndRedirect(error);
    }
  }

  void _showSuccessAndRedirect(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
    
    // Redirect to home after a brief delay
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/');
      }
    });
  }

  void _showErrorAndRedirect(String error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Authentication error: $error'),
        backgroundColor: Colors.red,
      ),
    );
    
    // Redirect to login after a brief delay
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/login');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Processing authentication...'),
          ],
        ),
      ),
    );
  }
}
