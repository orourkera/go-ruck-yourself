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
  bool _navigated = false;
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
    
    Timer(const Duration(seconds: 2), () async {
      if (!mounted || _navigated) return;
      _navigated = true;

      final authBloc = BlocProvider.of<AuthBloc>(context);
      final authState = authBloc.state;
      
      if (authState is Unauthenticated || authState is AuthError) {
        Navigator.pushReplacementNamed(context, '/login');
        return;
      }
      
      if (authState is Authenticated) {
        final revenueCatService = GetIt.instance<RevenueCatService>();
        final isSubscribed = await revenueCatService.checkSubscriptionStatus();
        if (isSubscribed) {
          Navigator.pushReplacementNamed(context, '/home');
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const PaywallScreen()),
          );
        }
      } else {
        Timer(const Duration(seconds: 2), () {
          if (!mounted) return;
          final currentState = authBloc.state;
          
          if (currentState is Authenticated) {
            Navigator.pushReplacementNamed(context, '/home');
          } else {
            Navigator.pushReplacementNamed(context, '/login');
          }
        });
      }
    });
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
    
    return FutureBuilder<bool>(
      future: SplashHelper.isLadyModeActive(),
      builder: (context, snapshot) {
        bool isLadyMode = snapshot.data ?? false;
        
        String? userGender;
        try {
          final authState = context.read<AuthBloc>().state;
          if (authState is Authenticated) {
            userGender = authState.user.gender;
            isLadyMode = (userGender == 'female');
            
            SplashHelper.cacheLadyModeStatus(isLadyMode);
            
            debugPrint('[Splash] Gender from auth state: $userGender, Lady mode: $isLadyMode');
          }
        } catch (e) {
          debugPrint('[Splash] Using cached lady mode value: $isLadyMode');
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
    );
  }
} 