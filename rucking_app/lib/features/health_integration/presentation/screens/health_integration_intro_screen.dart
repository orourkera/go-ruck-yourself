import 'package:flutter/material.dart';
import 'package:rucking_app/shared/widgets/styled_snackbar.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/health_integration/bloc/health_bloc.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/home_screen.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

class HealthIntegrationIntroScreen extends StatelessWidget {
  final bool navigateToHome;
  final String? userId;

  const HealthIntegrationIntroScreen({
    Key? key, 
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
          
          // Only show success message when permission is granted (Apple Store compliant)
          if (state.authorized) {
            StyledSnackBar.showSuccess(
              context: context,
              message: 'Apple Health integration enabled!',
              duration: const Duration(seconds: 2),
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
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.black),
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 24,
                    ),
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
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
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
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                        const SizedBox(height: 12),
                        const Text(
                          'We request access to the following HealthKit data:',
                          textAlign: TextAlign.left,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // List of data points with bullet points
                        const Padding(
                          padding: EdgeInsets.only(left: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('• Heart rate data', style: TextStyle(fontSize: 14)),
                              SizedBox(height: 4),
                              Text('• Workout information', style: TextStyle(fontSize: 14)),
                              SizedBox(height: 4),
                              Text('• Activity data', style: TextStyle(fontSize: 14)),
                              SizedBox(height: 4),
                              Text('• Energy burned (calories)', style: TextStyle(fontSize: 14)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Your data privacy is important - we only access the health data necessary for tracking your workouts.',
                          textAlign: TextAlign.center,
                          softWrap: true,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  // Action buttons
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: ElevatedButton(
                      onPressed: () async {
                        AppLogger.info('Requesting HealthKit authorization from intro screen');
                        try {
                          // Using the direct health service call to ensure the system dialog shows
                          final authorized = await context.read<HealthBloc>().healthService.requestAuthorization();
                          AppLogger.info('HealthKit authorization result: $authorized');
                          
                          // Notify bloc of authorization result
                          context.read<HealthBloc>().add(const RequestHealthAuthorization());
                        } catch (e) {
                          AppLogger.error('Error requesting HealthKit authorization: $e');
                          // Show error to user
                          StyledSnackBar.showError(
                            context: context,
                            message: 'Failed to request HealthKit access: $e',
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.arrow_forward, color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'CONTINUE',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // No skip or 'I don't own one' buttons to comply with App Store guidelines
                  const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
