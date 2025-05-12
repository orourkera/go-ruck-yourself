import 'package:flutter/material.dart';
import 'package:rucking_app/shared/widgets/styled_snackbar.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/health_integration/bloc/health_bloc.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/home_screen.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

class HealthIntegrationIntroScreen extends StatelessWidget {
  final bool showSkipButton;
  final bool navigateToHome;
  final String? userId;

  const HealthIntegrationIntroScreen({
    Key? key, 
    this.showSkipButton = true,
    this.navigateToHome = true,
    this.userId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocListener<HealthBloc, HealthState>(
      listenWhen: (previous, current) => 
        current is HealthAuthorizationStatus || 
        current is HealthIntroShown,
      listener: (context, state) {
        if (state is HealthAuthorizationStatus) {
          // Mark intro as seen regardless of authorization status
          context.read<HealthBloc>().add(const MarkHealthIntroSeen());
          
          // Show appropriate message based on authorization
          if (state.authorized) {
            StyledSnackBar.showSuccess(
              context: context,
              message: 'Apple Health integration enabled!',
              duration: const Duration(seconds: 2),
            );
          } else {
            StyledSnackBar.showError(
              context: context,
              message: 'Apple Health access was not granted.',
              duration: const Duration(seconds: 3),
            );
          }
        } else if (state is HealthIntroShown) {
          // Only navigate after intro has been marked as seen
          // and use Future.microtask to avoid calling setState during build
          Future.microtask(() {
            if (navigateToHome) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const HomeScreen()),
                (route) => false, // Remove all previous routes
              );
            } else {
              Navigator.of(context).pop();
            }
          });
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Apple Health Screen Image
                  Padding(
                    padding: const EdgeInsets.only(top: 12.0, bottom: 8.0),
                    child: Image.asset(
                      'assets/images/apple health screen.png',
                      height: 200,
                      fit: BoxFit.contain,
                    ),
                  ),
                  
                  // Text content
                  const SizedBox(height: 20),
                  const Text(
                    'Connect Apple Health',
                    style: TextStyle(
                      fontFamily: 'Banger',
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Get more from your workouts with Apple Health integration. Your rucking distance and calories burned will be synced automatically.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'It only takes 30 seconds, and you don\'t need to have your Apple Watch with you.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Your data privacy is important - we only access the health data necessary for tracking your workouts.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 40),
                  
                  // Action buttons
                  ElevatedButton(
                    onPressed: () async {
                      // Directly trigger HealthKit authorization prompt
                      await context.read<HealthBloc>().healthService.requestAuthorization();
                      // Notify bloc of authorization result
                      context.read<HealthBloc>().add(const RequestHealthAuthorization());
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'YES',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (showSkipButton)
                    TextButton(
                      onPressed: () {
                        // Mark as seen when skipped, but don't request authorization
                        // Navigation will be handled by the BlocListener
                        context.read<HealthBloc>().add(const MarkHealthIntroSeen());
                      },
                      style: TextButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                      ),
                      child: const Text(
                        'Later',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  
                  TextButton(
                    onPressed: () {
                      // Mark as seen and don't show again
                      // Navigation will be handled by the BlocListener
                      context.read<HealthBloc>().add(const SetHasAppleWatch(hasWatch: false));
                    },
                    style: TextButton.styleFrom(
                      minimumSize: const Size(double.infinity, 40),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    child: const Text(
                      'I don\'t own one',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
