import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/auth/presentation/screens/login_screen.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/home_screen.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

/// Splash screen shown during app initialization
class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeInAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _taglineAnimation;
  bool _showAuthCheck = false;

  @override
  void initState() {
    super.initState();
    
    // Initialize animation controller
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    
    // Create fade-in animation
    _fadeInAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );
    
    // Create pulsing animation for icon
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Interval(0.5, 1.0, curve: Curves.easeInOut),
      ),
    )..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _animationController.reverse();
      } else if (status == AnimationStatus.dismissed) {
        _animationController.forward();
      }
    });
    
    // Create delayed animation for tagline
    _taglineAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Interval(0.3, 0.8, curve: Curves.easeIn),
      ),
    );
    
    // Start animation
    _animationController.forward();
    
    // Delay before checking authentication
    _setupAuthCheckDelay();
  }
  
  /// Sets up the delay before checking authentication
  void _setupAuthCheckDelay() {
    // Display splash screen for 4 seconds before checking auth
    Timer(const Duration(milliseconds: 4000), () {
      if (mounted) {
        setState(() {
          _showAuthCheck = true;
        });
        // Dispatch auth check event
        context.read<AuthBloc>().add(AuthCheckRequested());
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
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (!_showAuthCheck) return; // Don't navigate away before delay completes
        
        if (state is Authenticated) {
          // Navigate to home screen if authenticated with fade transition
          Navigator.of(context).pushReplacement(
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) => const HomeScreen(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                const begin = 0.0;
                const end = 1.0;
                const curve = Curves.easeInOut;
                
                var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
                return FadeTransition(opacity: animation.drive(tween), child: child);
              },
              transitionDuration: const Duration(milliseconds: 800),
            ),
          );
        } else if (state is Unauthenticated) {
          // Navigate to login screen if not authenticated with fade transition
          Navigator.of(context).pushReplacement(
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) => const LoginScreen(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                const begin = 0.0;
                const end = 1.0;
                const curve = Curves.easeInOut;
                
                var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
                return FadeTransition(opacity: animation.drive(tween), child: child);
              },
              transitionDuration: const Duration(milliseconds: 800),
            ),
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
              colors: [
                Color(0xFFCC6A2A), // Brownish-orange
                Color(0xFF4B3621), // Dark brown
              ],
            ),
          ),
          child: FadeTransition(
            opacity: _fadeInAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // "Go Ruck Yourself" image
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: ScaleTransition(
                    scale: _pulseAnimation,
                    child: Image.asset(
                      'assets/images/go ruck yourself.png',
                      width: 300,
                      height: 300,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                
                // App name or tagline can be part of the image now
                /*
                Text(
                  'Rucking App',
                  style: AppTextStyles.headline4.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                */
                const SizedBox(height: 16),
                
                // Tagline
                FadeTransition(
                  opacity: _taglineAnimation,
                  child: Text(
                    'TRACK YOUR RUCKING. CHALLENGE YOURSELF.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Bangers',
                      fontSize: 24,
                      letterSpacing: 1.5,
                      color: Colors.white,
                    ),
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
      ),
    );
  }
} 