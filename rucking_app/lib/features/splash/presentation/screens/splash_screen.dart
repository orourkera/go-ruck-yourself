import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/features/paywall/presentation/screens/paywall_screen.dart';
import 'package:rucking_app/core/services/revenue_cat_service.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/home_screen.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

/// Splash screen shown on app launch
class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeInAnimation;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    
    // Initialize animation controller
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    
    // Create fade-in animation
    _fadeInAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_animationController);
    
    // Start the animation
    _animationController.forward();
    
    // Navigate to the appropriate screen after a delay
    Timer(const Duration(seconds: 3), () async {
      if (!mounted || _navigated) return;
      _navigated = true;

      // First check authentication status
      final authBloc = BlocProvider.of<AuthBloc>(context);
      final authState = authBloc.state;
      
      if (authState is Unauthenticated || authState is AuthError) {
        // If not authenticated, navigate to login screen
        Navigator.pushReplacementNamed(context, '/login');
        return;
      }
      
      // Only check subscription if authenticated
      if (authState is Authenticated) {
        // Check subscription status via RevenueCatService
        final revenueCatService = GetIt.instance<RevenueCatService>();
        final isSubscribed = await revenueCatService.checkSubscriptionStatus();
        if (isSubscribed) {
          // If subscribed, navigate directly to Home Screen
          Navigator.pushReplacementNamed(context, '/home');
        } else {
          // If not subscribed, navigate to Paywall Screen
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const PaywallScreen()),
          );
        }
      } else {
        // If still loading or in initial state, wait a bit longer
        Timer(const Duration(seconds: 2), () {
          if (!mounted) return;
          final currentState = authBloc.state;
          
          if (currentState is Authenticated) {
            Navigator.pushReplacementNamed(context, '/home');
          } else {
            // If still not authenticated, go to login
            Navigator.pushReplacementNamed(context, '/login');
          }
        });
      }
    });
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Get user gender from AuthBloc if available
    String? userGender;
    try {
      final authBloc = GetIt.instance<AuthBloc>();
      if (authBloc.state is Authenticated) {
        userGender = (authBloc.state as Authenticated).user.gender;
      }
    } catch (e) {
      // If auth bloc is not available, continue with default image
      debugPrint('Could not get user gender for splash screen: $e');
    }
    
    // Determine which splash image to use based on gender
    final bool isLadyMode = (userGender == 'female');
    final String splashImagePath = isLadyMode
        ? 'assets/images/go_ruck_yourself_lady.png' // Female version
        : 'assets/images/go ruck yourself.png'; // Default/male version
        
    // Use lady mode colors for female users
    final Color backgroundColor = isLadyMode ? AppColors.ladyPrimary : AppColors.primary;
        
    return Scaffold(
      backgroundColor: backgroundColor,
      body: Center(
        child: FadeTransition(
          opacity: _fadeInAnimation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Main logo image with animation - gender-specific
              ScaleTransition(
                scale: Tween<double>(begin: 1.0, end: 1.5).animate(
                  CurvedAnimation(
                    parent: _animationController,
                    curve: Curves.elasticOut,
                  ),
                ),
                child: Image.asset(
                  splashImagePath,
                  width: 281.25, // 375 * 0.75
                  height: 281.25, // 375 * 0.75
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 70),
              // App tagline
              Text(
                'Track your ruck, count your calories.',
                style: AppTextStyles.titleMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'Bangers',
                  fontSize: AppTextStyles.titleMedium.fontSize != null ? AppTextStyles.titleMedium.fontSize! * 1.25 : 25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 