import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/premium/presentation/bloc/premium_bloc.dart';
import 'package:rucking_app/features/premium/presentation/bloc/premium_state.dart';
import 'package:rucking_app/features/premium/presentation/bloc/premium_event.dart';
import 'package:rucking_app/features/premium/presentation/screens/premium_paywall_screen.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';

/// Widget that intercepts navigation to premium tabs and shows paywall for free users
/// TEMPORARILY DISABLED: All features are currently free
class PremiumTabInterceptor extends StatefulWidget {
  final int tabIndex;
  final Widget child;
  final String featureName;

  const PremiumTabInterceptor({
    Key? key,
    required this.tabIndex,
    required this.child,
    required this.featureName,
  }) : super(key: key);

  @override
  State<PremiumTabInterceptor> createState() => _PremiumTabInterceptorState();
}

class _PremiumTabInterceptorState extends State<PremiumTabInterceptor> {
  @override
  void initState() {
    super.initState();
    
    // PAYWALL DISABLED: Commenting out premium status checks
    // Trigger a fresh premium status check when accessing premium tabs
    // if (widget.tabIndex == 2 || widget.tabIndex == 3) {
    //   WidgetsBinding.instance.addPostFrameCallback((_) {
    //     context.read<PremiumBloc>().add(CheckPremiumStatus());
    //   });
    // }
  }

  @override
  Widget build(BuildContext context) {
    // PAYWALL DISABLED: Always allow access to all features
    // Making app 100% free temporarily
    return widget.child;
    
    /* 
    // ORIGINAL PAYWALL LOGIC - PRESERVED FOR FUTURE RESTORATION
    return BlocBuilder<PremiumBloc, PremiumState>(
      builder: (context, state) {
        // Show loading indicator while checking premium status
        if (state is PremiumLoading) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        // Allow access if user has premium
        if (state is PremiumLoaded && state.isPremium) {
          return widget.child;
        }

        // Block access to premium tabs (index 2 = Ruck Buddies, index 3 = Stats)
        if (widget.tabIndex == 2 || widget.tabIndex == 3) {
          return PremiumPaywallScreen(
            feature: widget.featureName,
            description: _getFeatureDescription(widget.tabIndex),
          );
        }

        // Allow access to free tabs
        return widget.child;
      },
    );
    */
  }

  /* 
  // PRESERVED FOR FUTURE RESTORATION
  String _getFeatureDescription(int index) {
    switch (index) {
      case 2:
        return 'Connect with other ruckers, see their sessions, and join the community!';
      case 3:
        return 'Track your progress with detailed analytics, charts, and insights!';
      default:
        return 'Unlock this premium feature to enhance your rucking experience!';
    }
  }
  */
}