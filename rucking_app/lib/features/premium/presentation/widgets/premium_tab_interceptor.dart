import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/premium/presentation/bloc/premium_bloc.dart';
import 'package:rucking_app/features/premium/presentation/bloc/premium_state.dart';
import 'package:rucking_app/features/premium/presentation/screens/premium_paywall_screen.dart';

/// Widget that intercepts navigation to premium tabs and shows paywall for free users
class PremiumTabInterceptor extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return BlocBuilder<PremiumBloc, PremiumState>(
      builder: (context, state) {
        // Allow access if user has premium
        if (state is PremiumLoaded && state.isPremium) {
          return child;
        }

        // Block access to premium tabs (index 2 = Ruck Buddies, index 3 = Stats)
        if (tabIndex == 2 || tabIndex == 3) {
          return PremiumPaywallScreen(
            feature: featureName,
            description: _getFeatureDescription(tabIndex),
          );
        }

        // Allow access to free tabs
        return child;
      },
    );
  }

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
}