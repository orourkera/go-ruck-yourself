import 'package:flutter/material.dart';
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                state.authorized 
                    ? 'Apple Health integration enabled!' 
                    : 'Apple Health access was not granted.',
              ),
              backgroundColor: state.authorized ? Colors.green : Colors.red,
            ),
          );
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
                  
                  // Text content with HealthKit badge
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Connect ',
                        style: TextStyle(
                          fontFamily: 'Banger',
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      // Heart icon to represent HealthKit
                      const Icon(
                        Icons.favorite,
                        color: Colors.red,
                        size: 30,
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        ' Apple Health',
                        style: TextStyle(
                          fontFamily: 'Banger',
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      'HealthKit Integration',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                      textAlign: TextAlign.center,
                    ),
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
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Column(
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.shield, color: Colors.green),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'HealthKit Data Access',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'We request access to the following HealthKit data:',
                          textAlign: TextAlign.left,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Padding(
                          padding: EdgeInsets.only(left: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('• Heart rate data', style: TextStyle(fontSize: 14)),
                              Text('• Workout information', style: TextStyle(fontSize: 14)),
                              Text('• Activity data', style: TextStyle(fontSize: 14)),
                              Text('• Energy burned (calories)', style: TextStyle(fontSize: 14)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Your data privacy is important - we only access the health data necessary for tracking your workouts.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.black54,
                          ),
                        ),
                      ],
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
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.favorite, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'ENABLE HEALTHKIT',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
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
