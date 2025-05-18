import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/features/paywall/presentation/screens/paywall_screen.dart';
import 'package:rucking_app/core/services/revenue_cat_service.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/home_screen.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/features/splash/service/splash_helper.dart';

/// Splash screen shown on app launch
class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeInAnimation;
  bool _navigated = false; // To prevent multiple navigations
  static bool _hasAnimatedOnceThisLaunch = false;

  @override
  void initState() {
    super.initState();
    debugPrint('[Splash] initState: New _SplashScreenState created. HasAnimatedOnce: $_hasAnimatedOnceThisLaunch');
    
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _animationController.addStatusListener((status) {
      debugPrint('[Splash] Animation status changed: $status');
      if (status == AnimationStatus.completed) {
        if (mounted) { 
          _hasAnimatedOnceThisLaunch = true;
          debugPrint('[Splash] Animation completed and _hasAnimatedOnceThisLaunch set to true.');
        }
      }
    });
    
    _fadeInAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(_animationController);
    
    if (!_hasAnimatedOnceThisLaunch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        debugPrint('[Splash] addPostFrameCallback executed (condition: !_hasAnimatedOnceThisLaunch).');
        if (mounted && !_animationController.isAnimating && _animationController.status != AnimationStatus.completed) {
          debugPrint('[Splash] Forwarding animation controller from addPostFrameCallback.');
          _animationController.forward();
        } else {
          debugPrint('[Splash] NOT forwarding animation (check in addPostFrameCallback): mounted=$mounted, isAnimating=${_animationController.isAnimating}, status=${_animationController.status}');
        }
      });
    } else {
      debugPrint('[Splash] Animation already played this launch, skipping forward in initState.');
      if (mounted && _animationController.status != AnimationStatus.completed && !_animationController.isAnimating) {
        _animationController.value = 1.0; 
      }
    }
    
    // Check initial auth state after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final authState = BlocProvider.of<AuthBloc>(context).state;
        debugPrint('[Splash] initState - postFrameCallback - initial AuthState check: ${authState.runtimeType}');
        _handleAuthNavigation(context, authState);
      }
    });
  }

  Future<void> _handleAuthNavigation(BuildContext context, AuthState authState) async {
    // If already navigated or not mounted, do nothing.
    // The check for authState being AuthInitial or AuthLoading is implicitly handled by not setting _navigated = true
    // and allowing the BlocListener to pick up subsequent state changes.
    if (!mounted || _navigated && (authState is Authenticated || authState is Unauthenticated || authState is AuthError)) return;

    if (authState is Authenticated) {
      _navigated = true; // Set flag before async gap to prevent re-entry for this specific state change event
      debugPrint('[Splash] AuthState is Authenticated. Checking subscription.');
      final revenueCatService = GetIt.instance<RevenueCatService>();
      final isSubscribed = await revenueCatService.checkSubscriptionStatus();
      if (!mounted) return; // Check mounted again after await
      if (isSubscribed) {
        debugPrint('[Splash] User is subscribed. Navigating to /home.');
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        debugPrint('[Splash] User is NOT subscribed. Navigating to PaywallScreen.');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const PaywallScreen()),
        );
      }
    } else if (authState is Unauthenticated || authState is AuthError) {
      _navigated = true; // Set flag
      debugPrint('[Splash] AuthState is ${authState.runtimeType}. Navigating to /login.');
      Navigator.pushReplacementNamed(context, '/login');
    } else {
      // For states like AuthInitial or AuthLoading, do nothing here.
      // _navigated remains false, allowing BlocListener to catch the next definitive state.
      debugPrint('[Splash] AuthState is ${authState.runtimeType}. Waiting for Authenticated or Unauthenticated.');
    }
  }
  
  @override
  void dispose() {
    debugPrint('[Splash] dispose: _SplashScreenState disposed. HasAnimatedOnce: $_hasAnimatedOnceThisLaunch');
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('[Splash] build: _SplashScreenState build method called. Animation controller status: ${_animationController.status}');
    
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        debugPrint('[Splash] BlocListener received AuthState: ${state.runtimeType}');
        _handleAuthNavigation(context, state);
      },
      // listenWhen could be used to optimize if needed, e.g., listenWhen: (prev, curr) => !_navigated,
      child: FutureBuilder<bool>(
        future: SplashHelper.isLadyModeActive(),
        builder: (context, snapshot) {
          bool isLadyMode = snapshot.data ?? false;
          
          String? userGender;
          try {
            // Reading AuthBloc state here is for UI purposes (e.g. lady mode). Navigation is driven by the listener.
            final authStateFromBuildContext = context.read<AuthBloc>().state;
            if (authStateFromBuildContext is Authenticated) {
              userGender = authStateFromBuildContext.user.gender;
              isLadyMode = (userGender == 'female');
              
              SplashHelper.cacheLadyModeStatus(isLadyMode);
              
              debugPrint('[Splash] UI Build - Gender from auth state: $userGender, Lady mode: $isLadyMode');
            }
          } catch (e) {
            debugPrint('[Splash] UI Build - Using cached lady mode value: $isLadyMode');
          }
          
          final String splashImagePath = SplashHelper.getSplashImagePath(isLadyMode);
          
          final Color backgroundColor = SplashHelper.getBackgroundColor(isLadyMode);
          
          return Scaffold(
            backgroundColor: backgroundColor,
            body: Center(
              child: FadeTransition(
                opacity: _fadeInAnimation,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ScaleTransition(
                      scale: Tween<double>(begin: 1.0, end: 1.5).animate(
                        CurvedAnimation(
                          parent: _animationController,
                          curve: Curves.elasticOut,
                        ),
                      ),
                      child: Image.asset(
                        splashImagePath,
                        width: 281.25, 
                        height: 281.25, 
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 70),
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
        },
      ),
    );
  }
} 