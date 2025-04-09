import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/auth/presentation/screens/login_screen.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/home_screen.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

/// Splash screen shown during app initialization
class SplashScreen extends StatelessWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is Authenticated) {
          // Navigate to home screen if authenticated
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        } else if (state is Unauthenticated) {
          // Navigate to login screen if not authenticated
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
        }
      },
      child: Scaffold(
        body: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: AppColors.primaryGradient,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // App logo or icon
              const Icon(
                Icons.directions_walk,
                size: 120,
                color: Colors.white,
              ),
              const SizedBox(height: 24),
              
              // App name
              Text(
                'Rucking App',
                style: AppTextStyles.headline4.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              
              // Tagline
              Text(
                'Track your rucking sessions',
                style: AppTextStyles.subtitle1.copyWith(
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 64),
              
              // Loading indicator
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 