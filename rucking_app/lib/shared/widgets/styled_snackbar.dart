import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:rucking_app/shared/theme/app_colors.dart';

/// Animation styles for the StyledSnackBar
enum SnackBarAnimationStyle {
  /// Slide up from bottom with bounce effect
  slideUpBounce,
  
  /// Slide in from the right side
  slideFromRight,
  
  /// Slide in from the left side
  slideFromLeft,
  
  /// Fade in and scale up for an explosive entrance
  popIn,
  
  /// Slide down from the top
  slideFromTop,
  
  /// Appear with a rotation effect
  spin,
}

/// Types of SnackBars for different states
enum SnackBarType {
  /// Normal information SnackBar (slate grey)
  normal,
  
  /// Success SnackBar (green)
  success,
  
  /// Error SnackBar (red)
  error,
}

/// A utility class that provides badass SnackBars with Bangers font and custom animation
class StyledSnackBar {
  /// Shows a styled SnackBar with Bangers font and custom animation
  /// 
  /// [context] - The BuildContext
  /// [message] - The message to display
  /// [duration] - How long to display the message
  /// [type] - The type of snackbar (normal, success, or error)
  /// [animationStyle] - The animation style to use (default: popIn)
  static void show({
    required BuildContext context,
    required String message,
    Duration? duration,
    SnackBarType type = SnackBarType.normal,
    SnackBarAnimationStyle animationStyle = SnackBarAnimationStyle.popIn,
  }) {
    // Dismiss any existing SnackBars
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    
    // Main and border colors based on type
    late Color mainColor;
    late Color borderColor;
    late Color shadowColor;
    
    switch (type) {
      case SnackBarType.error:
        mainColor = AppColors.error;
        borderColor = AppColors.errorDark;
        shadowColor = AppColors.errorDark.withOpacity(0.5);
        break;
      case SnackBarType.success:
        mainColor = Colors.green.shade600;
        borderColor = Colors.green.shade800;
        shadowColor = Colors.green.shade800.withOpacity(0.5);
        break;
      case SnackBarType.normal:
        mainColor = AppColors.slateGrey;
        borderColor = AppColors.greyDark;
        shadowColor = AppColors.black.withOpacity(0.3);
        break;
    }
    
    // Create the snackbar content with CAPS for badass effect
    final Widget content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: BoxDecoration(
        color: mainColor,
        borderRadius: BorderRadius.circular(15.0),
        border: Border.all(
          color: borderColor,
          width: 2.5,
        ),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            offset: const Offset(0, 3),
            blurRadius: 6.0,
            spreadRadius: 1.0,
          ),
        ],
      ),
      child: Text(
        message.toUpperCase(), // EVERYTHING LOOKS MORE BADASS IN CAPS
        style: const TextStyle(
          fontFamily: 'Bangers',
          fontSize: 20.0,
          letterSpacing: 1.5,
          color: Colors.white,
          shadows: [
            Shadow(
              offset: Offset(1.0, 1.0),
              blurRadius: 3.0,
              color: Colors.black54,
            ),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
    
    // Create an overlay entry with animation
    final OverlayState overlayState = Overlay.of(context);
    final AnimationController controller = AnimationController(
      vsync: Navigator.of(context),
      duration: const Duration(milliseconds: 500),
    );
    
    late final Animation<double> opacity;
    late final Animation<double> scale;
    late final Animation<Offset> position;
    
    // Configure animations based on the style
    switch (animationStyle) {
      case SnackBarAnimationStyle.slideUpBounce:
        opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(parent: controller, curve: const Interval(0.0, 0.4, curve: Curves.easeOut)),
        );
        scale = Tween<double>(begin: 1.0, end: 1.0).animate(controller);
        position = Tween<Offset>(begin: const Offset(0.0, 1.0), end: Offset.zero).animate(
          CurvedAnimation(parent: controller, curve: Curves.elasticOut),
        );
        break;
        
      case SnackBarAnimationStyle.slideFromRight:
        opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(parent: controller, curve: const Interval(0.0, 0.4, curve: Curves.easeOut)),
        );
        scale = Tween<double>(begin: 1.0, end: 1.0).animate(controller);
        position = Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(
          CurvedAnimation(parent: controller, curve: Curves.elasticOut),
        );
        break;
        
      case SnackBarAnimationStyle.slideFromLeft:
        opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(parent: controller, curve: const Interval(0.0, 0.4, curve: Curves.easeOut)),
        );
        scale = Tween<double>(begin: 1.0, end: 1.0).animate(controller);
        position = Tween<Offset>(begin: const Offset(-1.0, 0.0), end: Offset.zero).animate(
          CurvedAnimation(parent: controller, curve: Curves.elasticOut),
        );
        break;
        
      case SnackBarAnimationStyle.slideFromTop:
        opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(parent: controller, curve: const Interval(0.0, 0.4, curve: Curves.easeOut)),
        );
        scale = Tween<double>(begin: 1.0, end: 1.0).animate(controller);
        position = Tween<Offset>(begin: const Offset(0.0, -1.0), end: Offset.zero).animate(
          CurvedAnimation(parent: controller, curve: Curves.elasticOut),
        );
        break;
        
      case SnackBarAnimationStyle.spin:
        opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(parent: controller, curve: const Interval(0.0, 0.5, curve: Curves.easeOut)),
        );
        scale = Tween<double>(begin: 0.6, end: 1.0).animate(
          CurvedAnimation(parent: controller, curve: Curves.elasticOut),
        );
        position = Tween<Offset>(begin: Offset.zero, end: Offset.zero).animate(controller);
        break;
        
      case SnackBarAnimationStyle.popIn:
        opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(parent: controller, curve: const Interval(0.0, 0.5, curve: Curves.easeOut)),
        );
        scale = Tween<double>(begin: 0.5, end: 1.0).animate(
          CurvedAnimation(parent: controller, curve: Curves.elasticOut),
        );
        position = Tween<Offset>(begin: const Offset(0.0, 0.2), end: Offset.zero).animate(
          CurvedAnimation(parent: controller, curve: Curves.easeOutCubic),
        );
        break;
    }
    
    // Create animation widgets
    late OverlayEntry overlayEntry;
    overlayEntry = OverlayEntry(
      builder: (BuildContext context) => Positioned(
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
        left: 20,
        right: 20,
        child: AnimatedBuilder(
          animation: controller,
          builder: (_, Widget? child) {
            return Opacity(
              opacity: opacity.value,
              child: Transform.translate(
                offset: position.value.scale(50, 50),  // Scale for more dramatic effect
                child: Transform.scale(
                  scale: scale.value,
                  child: animationStyle == SnackBarAnimationStyle.spin
                    ? Transform.rotate(
                        angle: controller.value * 2 * math.pi,
                        child: child,
                      )
                    : child,
                ),
              ),
            );
          },
          child: Material(
            color: Colors.transparent,
            child: content,
          ),
        ),
      ),
    );
    
    // Show the overlay and remove after duration
    overlayState.insert(overlayEntry);
    controller.forward();
    
    Future.delayed(duration ?? const Duration(seconds: 3), () {
      controller.reverse().then((_) {
        if (overlayEntry.mounted) {
          overlayEntry.remove();
        }
      });
    });
  }
  
  /// Shows a success-styled SnackBar (green color)
  static void showSuccess({
    required BuildContext context,
    required String message,
    Duration? duration,
    SnackBarAnimationStyle animationStyle = SnackBarAnimationStyle.popIn,
  }) {
    show(
      context: context,
      message: message,
      duration: duration,
      type: SnackBarType.success,
      animationStyle: animationStyle,
    );
  }
  
  /// Shows an error-styled SnackBar (red color)
  static void showError({
    required BuildContext context,
    required String message,
    Duration? duration,
    SnackBarAnimationStyle animationStyle = SnackBarAnimationStyle.popIn,
  }) {
    show(
      context: context,
      message: message,
      duration: duration ?? const Duration(seconds: 3),
      type: SnackBarType.error,
      animationStyle: animationStyle,
    );
  }
}
