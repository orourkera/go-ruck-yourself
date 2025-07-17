import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/services/revenue_cat_service.dart';
import 'package:rucking_app/core/services/first_launch_service.dart';
import 'package:rucking_app/core/services/battery_optimization_service.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/paywall/presentation/screens/paywall_screen.dart';
import 'package:rucking_app/features/auth/presentation/screens/login_screen.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/home_screen.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/features/splash/service/splash_helper.dart';

/// Splash screen shown on app launch
class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static bool _hasAnimatedOnceThisLaunch = false;

  // New state variables for timed splash screen
  bool _minimumDisplayTimeElapsed = false;
  bool _authCheckCompleted = false;
  AuthState? _definitiveAuthState; 
  bool _navigationAttempted = false;
  bool _authRetryScheduled = false; // Prevent multiple retry timers 

  @override
  void initState() {
    super.initState();
    debugPrint('[Splash] initState: Splash screen initialized');
    
    // Mark animation as completed since GIF handles its own animation
    _hasAnimatedOnceThisLaunch = true;
    
    // Check initial auth state after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final authState = BlocProvider.of<AuthBloc>(context).state;
        debugPrint('[Splash] initState - postFrameCallback - initial AuthState check: ${authState.runtimeType}');
        _processAuthState(authState); // New call
      }
    });

    // Start 3-second timer for minimum display duration
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        debugPrint('[Splash] Minimum 3-second display time elapsed.');
        setState(() {
          _minimumDisplayTimeElapsed = true;
        });
        _attemptNavigation(); // Attempt navigation when timer elapses
      }
    });
  }

  void _processAuthState(AuthState authState) {
    if (authState is Authenticated || authState is Unauthenticated || authState is AuthError) {
      if (!_authCheckCompleted) { // Process only the first definitive auth state
        debugPrint('[Splash] Definitive AuthState received: ${authState.runtimeType}');
        if (mounted) {
          setState(() {
            _authCheckCompleted = true;
            _definitiveAuthState = authState;
          });
        }
        _attemptNavigation(); // Attempt navigation when auth state is definitive
      } else {
        debugPrint('[Splash] Auth check already completed with ${_definitiveAuthState?.runtimeType}, new state ${authState.runtimeType} ignored for navigation processing.');
      }
    } else if (authState is AuthLoading) {
      // Set up multiple timeouts to re-check auth if stuck in loading
      if (!_authRetryScheduled) {
        debugPrint('[Splash] AuthLoading state detected. Setting up retry timeouts...');
        _authRetryScheduled = true;
        
        // First retry after 3 seconds (for quick token refresh)
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && !_authCheckCompleted) {
            debugPrint('[Splash] Auth still loading after 3 seconds, triggering first retry');
            context.read<AuthBloc>().add(AuthCheckRequested());
          }
        });
        
        // Second retry after 6 seconds (for slower network)
        Future.delayed(const Duration(seconds: 6), () {
          if (mounted && !_authCheckCompleted) {
            debugPrint('[Splash] Auth still loading after 6 seconds, triggering second retry');
            context.read<AuthBloc>().add(AuthCheckRequested());
          }
        });
      } else {
        debugPrint('[Splash] AuthLoading detected but retries already scheduled');
      }
    } else {
      // For states like AuthInitial, do nothing here.
      debugPrint('[Splash] Non-definitive AuthState: ${authState.runtimeType}. Waiting.');
    }
  }

  Future<void> _attemptNavigation() async {
    if (!mounted || _navigationAttempted || !_minimumDisplayTimeElapsed || !_authCheckCompleted || _definitiveAuthState == null) {
      debugPrint('[Splash] Navigation attempt condition not met: mounted=$mounted, attempted=$_navigationAttempted, timerElapsed=$_minimumDisplayTimeElapsed, authDone=$_authCheckCompleted, authStateIsNull=${_definitiveAuthState == null}');
      if(_definitiveAuthState != null) {
          debugPrint('[Splash] Definitive auth state for non-navigation: ${_definitiveAuthState.runtimeType}');
      }
      return;
    }

    _navigationAttempted = true; // Set flag immediately to prevent re-entry
    debugPrint('[Splash] Attempting navigation with AuthState: ${_definitiveAuthState!.runtimeType}');

    final authStateToNavigate = _definitiveAuthState!; 

    if (authStateToNavigate is Authenticated) {
      debugPrint('[Splash] AuthState is Authenticated. Checking subscription.');
      final revenueCatService = GetIt.instance<RevenueCatService>();
      final bool isSubscribed = await revenueCatService.checkSubscriptionStatus(); 
      if (!mounted) return; // Check mounted after await

      // Check if user has seen the paywall before
      final bool hasSeenPaywall = await FirstLaunchService.hasSeenPaywall();

      // Check battery optimization permissions for authenticated users
      try {
        debugPrint('[Splash] Checking battery optimization permissions...');
        await BatteryOptimizationService.ensureBackgroundExecutionPermissions(context: context);
        if (!mounted) return; // Check mounted after await
      } catch (e) {
        debugPrint('[Splash] Error checking battery optimization: $e');
        // Continue anyway - don't block app startup for this
      }

      if (isSubscribed) {
        debugPrint('[Splash] User is subscribed. Navigating to HomeScreen.');
        Navigator.pushReplacementNamed(context, '/home');
      } else if (!hasSeenPaywall) {
        // PAYWALL DISABLED: Skip paywall and go straight to home
        debugPrint('[Splash] First launch - PAYWALL DISABLED, navigating to HomeScreen.');
        await FirstLaunchService.markPaywallSeen();
        Navigator.pushReplacementNamed(context, '/home');
        
        /* ORIGINAL PAYWALL LOGIC - PRESERVED FOR FUTURE RESTORATION
        // First time user sees paywall - show it and mark as seen
        debugPrint('[Splash] First launch - showing PaywallScreen.');
        await FirstLaunchService.markPaywallSeen();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const PaywallScreen()),
        );
        */
      } else {
        // User has seen paywall before - go straight to home
        debugPrint('[Splash] User has seen paywall before. Navigating to HomeScreen.');
        Navigator.pushReplacementNamed(context, '/home');
      }
    } else if (authStateToNavigate is Unauthenticated || authStateToNavigate is AuthError) {
      debugPrint('[Splash] AuthState is ${authStateToNavigate.runtimeType}. Navigating to /login.');
      Navigator.pushReplacementNamed(context, '/login');
    } else {
      // Should not happen due to the checks above, but good for completeness
      debugPrint('[Splash] Critical: _attemptNavigation called with unexpected authState: ${authStateToNavigate.runtimeType}');
    }
  }
  


  @override
  void dispose() {
    debugPrint('[Splash] dispose: Cleaning up splash screen');
    // Note: Future.delayed doesn't return cancelable timers, but we check mounted in all callbacks
    // This ensures that any pending futures won't cause issues
    super.dispose();
  }

  /// Builds the splash image with defensive error handling to prevent native crashes
  Widget _buildSplashImage(String primaryImagePath) {
    return Container(
      width: 200,
      height: 200,
      child: _buildImageWithFallbacks(),
    );
  }
  
  /// Attempts to load images with multiple fallbacks
  Widget _buildImageWithFallbacks() {
    final fallbackPaths = SplashHelper.getFallbackImagePaths();
    
    return _tryLoadImage(fallbackPaths, 0);
  }
  
  /// Recursively tries to load images from the fallback list
  Widget _tryLoadImage(List<String> imagePaths, int currentIndex) {
    if (currentIndex >= imagePaths.length) {
      debugPrint('[Splash] All image fallbacks exhausted, using programmatic fallback');
      return _buildFallbackImage();
    }
    
    final currentPath = imagePaths[currentIndex];
    debugPrint('[Splash] Attempting to load image: $currentPath (attempt ${currentIndex + 1}/${imagePaths.length})');
    
    try {
      // Special handling for GIF files to prevent native crashes
      if (currentPath.endsWith('.gif')) {
        // Skip GIF loading on devices where it's unsafe
        if (_shouldAvoidGifLoading()) {
          debugPrint('[Splash] Skipping GIF loading for safety, trying next fallback');
          return _tryLoadImage(imagePaths, currentIndex + 1);
        }
        
        return _buildSafeGifImage(currentPath, imagePaths, currentIndex);
      }
      
      return Image.asset(
        currentPath,
        width: 200,
        height: 200,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('[Splash] Failed to load $currentPath: $error');
          // Try next fallback
          return _tryLoadImage(imagePaths, currentIndex + 1);
        },
      );
    } catch (e, stackTrace) {
      debugPrint('[Splash] Critical error loading $currentPath: $e');
      
      // Log comprehensive crash context
      _logSplashCrashContext(currentPath, e, stackTrace, currentIndex);
      
      // Try next fallback or show programmatic fallback
      return _tryLoadImage(imagePaths, currentIndex + 1);
    }
  }
  
  /// Checks if we should avoid GIF loading on this device to prevent crashes
  bool _shouldAvoidGifLoading() {
    // Only avoid GIF on very old Android devices (API < 21) in release mode
    // Modern Android devices should handle GIF animations fine
    if (!kDebugMode && Platform.isAndroid) {
      // You could add more specific checks here like:
      // - Android API level detection
      // - Device model detection
      // - Available memory checks
      // For now, we'll be more permissive and only block on known problematic devices
      
      // TODO: Add actual device compatibility checks if needed
      // For now, let's try GIF first and fall back naturally on errors
      debugPrint('[Splash] Android release build - trying GIF with fallback');
      return false; // Allow GIF, but we have fallbacks in place
    }
    
    return false;
  }

  /// Builds a GIF image with safer memory management to prevent native crashes
  Widget _buildSafeGifImage(String gifPath, List<String> imagePaths, int currentIndex) {
    debugPrint('[Splash] Attempting to load GIF with safe memory management: $gifPath');
    
    try {
      // Use a Container to limit memory usage and add disposal handling
      return Container(
        width: 200,
        height: 200,
        child: Image.asset(
          gifPath,
          width: 200,
          height: 200,
          fit: BoxFit.contain,
          // Add memory management
          gaplessPlayback: false, // Disable gapless playback to reduce memory usage
          errorBuilder: (context, error, stackTrace) {
            debugPrint('[Splash] GIF load failed: $error');
            
            // Log GIF-specific crash context
            _logSplashCrashContext(gifPath, error, stackTrace ?? StackTrace.current, currentIndex);
            
            // Skip GIF and try next fallback immediately
            return _tryLoadImage(imagePaths, currentIndex + 1);
          },
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('[Splash] Critical GIF error: $e');
      
      // Log comprehensive crash context for GIF
      _logSplashCrashContext(gifPath, e, stackTrace, currentIndex);
      
      // Skip GIF and try next fallback
      return _tryLoadImage(imagePaths, currentIndex + 1);
    }
  }

  /// Logs detailed context for splash screen crashes to help with debugging
  void _logSplashCrashContext(String imagePath, dynamic error, StackTrace stackTrace, int attemptIndex) {
    try {
      final crashContext = {
        'image_path': imagePath,
        'attempt_index': attemptIndex,
        'error_type': error.runtimeType.toString(),
        'error_message': error.toString(),
        'widget_mounted': mounted,
        'has_material_app': context.mounted,
      };
      
      debugPrint('[Splash] CRASH CONTEXT: $crashContext');
      
      // TODO: Send to crashlytics when available
      // FirebaseCrashlytics.instance.recordError(error, stackTrace, 
      //   information: crashContext.entries.map((e) => 
      //     DiagnosticsProperty(e.key, e.value)).toList());
      
    } catch (loggingError) {
      debugPrint('[Splash] Failed to log crash context: $loggingError');
    }
  }

  /// Builds a fallback image when primary assets fail to load
  Widget _buildFallbackImage() {
    return Container(
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[400]!, width: 2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.fitness_center,
            size: 60,
            color: Colors.grey[600],
          ),
          const SizedBox(height: 8),
          Text(
            'RUCK',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
              fontFamily: 'Impact',
              letterSpacing: 2.0,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('[Splash] build: Splash screen building with GIF animation');
    debugPrint('[Splash] BUILD METHOD CALLED - Widget is building');
    
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        debugPrint('[Splash] BlocListener received AuthState: ${state.runtimeType}');
        _processAuthState(state); // New call
      },
      // listenWhen could be used to optimize if needed, e.g., listenWhen: (prev, curr) => !_navigationAttempted,
      child: FutureBuilder<bool>(
        future: SplashHelper.isLadyModeActive(),
        builder: (context, snapshot) {
          debugPrint('[Splash] FutureBuilder called - snapshot: ${snapshot.data}');
          bool isLadyMode = snapshot.data ?? false;
          
          String? userGender;
          try {
            // Reading AuthBloc state here is for UI purposes (e.g. lady mode). Navigation is driven by the listener.
            final authStateFromBuildContext = context.read<AuthBloc>().state;
            debugPrint('[Splash] Successfully read AuthBloc state: ${authStateFromBuildContext.runtimeType}');
            if (authStateFromBuildContext is Authenticated) {
              userGender = authStateFromBuildContext.user.gender;
              isLadyMode = (userGender == 'female');
              
              SplashHelper.cacheLadyModeStatus(isLadyMode);
              
              debugPrint('[Splash] UI Build - Gender from auth state: $userGender, Lady mode: $isLadyMode');
            }
          } catch (e) {
            debugPrint('[Splash] ERROR reading AuthBloc: $e');
            debugPrint('[Splash] UI Build - Using cached lady mode value: $isLadyMode');
          }
          
          final String splashImagePath = SplashHelper.getSplashImagePath(isLadyMode);
          
          final Color backgroundColor = SplashHelper.getBackgroundColor(isLadyMode);
          
          return Scaffold(
            backgroundColor: backgroundColor,
            body: Center(
              child: _buildSplashImage(splashImagePath),
            ),
          );
        },
      ),
    );
  }
}

/// Custom painter that creates a painted/drawn text effect
class PaintedTextPainter extends CustomPainter {
  final String text;
  final double progress;
  
  PaintedTextPainter({
    required this.text,
    required this.progress,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    // Create text style - smaller and lighter
    final textStyle = TextStyle(
      fontSize: 65, // Smaller than 80
      fontWeight: FontWeight.w400, // Much lighter than w600
      fontFamily: 'Impact',
      letterSpacing: 4.0, // Good spacing
    );
    
    final textSpan = TextSpan(text: text, style: textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    
    textPainter.layout();
    
    // Center the text
    final textOffset = Offset(
      (size.width - textPainter.width) / 2,
      (size.height - textPainter.height) / 2,
    );
    
    // Create paint for stroke effect
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5 // Thinner stroke
      ..color = Colors.white
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    
    // Create paint for shadow
    final shadowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..color = Colors.black.withOpacity(0.3)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    
    // Draw each letter with progress-based reveal
    const letters = ['R', 'U', 'C', 'K'];
    double currentX = textOffset.dx;
    
    for (int i = 0; i < letters.length; i++) {
      final letter = letters[i];
      final letterProgress = ((progress * letters.length) - i).clamp(0.0, 1.0);
      
      if (letterProgress > 0) {
        // Create individual letter painter
        final letterTextSpan = TextSpan(text: letter, style: textStyle);
        final letterPainter = TextPainter(
          text: letterTextSpan,
          textDirection: TextDirection.ltr,
        );
        letterPainter.layout();
        
        final letterOffset = Offset(currentX, textOffset.dy);
        
        // Draw shadow first
        canvas.save();
        canvas.translate(letterOffset.dx + 1, letterOffset.dy + 2);
        
        // Create shadow with opacity based on progress
        final shadowWithOpacity = shadowPaint..color = Colors.black.withOpacity(0.3 * letterProgress);
        
        // Draw shadow stroke
        final shadowSpan = TextSpan(
          text: letter,
          style: textStyle.copyWith(color: Colors.transparent),
        );
        final shadowTextPainter = TextPainter(
          text: shadowSpan,
          textDirection: TextDirection.ltr,
        );
        shadowTextPainter.layout();
        shadowTextPainter.paint(canvas, Offset.zero);
        
        canvas.restore();
        
        // Draw main letter stroke
        canvas.save();
        canvas.translate(letterOffset.dx, letterOffset.dy);
        
        // Adjust stroke opacity based on progress
        final strokeWithOpacity = strokePaint..color = Colors.white.withOpacity(letterProgress);
        
        // Use a clipRect to simulate drawing progress
        if (letterProgress < 1.0) {
          final clipHeight = letterPainter.height * letterProgress;
          canvas.clipRect(Rect.fromLTWH(0, 0, letterPainter.width, clipHeight));
        }
        
        // Draw the letter stroke
        final strokeSpan = TextSpan(
          text: letter,
          style: textStyle.copyWith(
            foreground: strokeWithOpacity,
          ),
        );
        final strokeTextPainter = TextPainter(
          text: strokeSpan,
          textDirection: TextDirection.ltr,
        );
        strokeTextPainter.layout();
        strokeTextPainter.paint(canvas, Offset.zero);
        
        canvas.restore();
        
        currentX += letterPainter.width;
      } else {
        // Even if not drawing, we need to account for letter width
        final letterTextSpan = TextSpan(text: letter, style: textStyle);
        final letterPainter = TextPainter(
          text: letterTextSpan,
          textDirection: TextDirection.ltr,
        );
        letterPainter.layout();
        currentX += letterPainter.width;
      }
    }
  }
  
  @override
  bool shouldRepaint(covariant PaintedTextPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.text != text;
  }
} 