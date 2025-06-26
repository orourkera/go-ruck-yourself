import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/services/location_service.dart';
import 'package:rucking_app/features/health_integration/domain/health_service.dart';
import 'package:rucking_app/core/services/battery_optimization_service.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/styled_snackbar.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/home_screen.dart';

/// Unified onboarding screen that handles all permissions for both iOS and Android
class UnifiedOnboardingScreen extends StatefulWidget {
  final String? userId;

  const UnifiedOnboardingScreen({
    Key? key,
    this.userId,
  }) : super(key: key);

  @override
  State<UnifiedOnboardingScreen> createState() => _UnifiedOnboardingScreenState();
}

class _UnifiedOnboardingScreenState extends State<UnifiedOnboardingScreen> {
  int _currentStep = 0;
  bool _isProcessing = false;

  // Permission states
  bool _locationPermissionGranted = false;
  bool _healthPermissionGranted = false;
  bool _batteryOptimizationHandled = false;

  @override
  void initState() {
    super.initState();
    _checkExistingPermissions();
  }

  Future<void> _checkExistingPermissions() async {
    try {
      // Check location permission
      final locationService = GetIt.instance<LocationService>();
      _locationPermissionGranted = await locationService.hasLocationPermission();

      // Check health permission (if available)
      if (Platform.isIOS || Platform.isAndroid) {
        final healthService = GetIt.instance<HealthService>();
        final isHealthAvailable = await healthService.isHealthDataAvailable();
        if (isHealthAvailable) {
          _healthPermissionGranted = healthService.isAuthorized;
        } else {
          _healthPermissionGranted = true; // Skip if not available
        }
      }

      // Battery optimization is only for Android
      if (Platform.isAndroid) {
        _batteryOptimizationHandled = false; // Always show for Android
      } else {
        _batteryOptimizationHandled = true; // Skip for other platforms
      }

      setState(() {});
    } catch (e) {
      AppLogger.error('[ONBOARDING] Error checking existing permissions: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: Text(
          'Setup',
          style: AppTextStyles.headlineMedium.copyWith(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: _isProcessing
            ? const Center(child: CircularProgressIndicator())
            : _buildCurrentStep(),
      ),
    );
  }

  Widget _buildCurrentStep() {
    // Determine which step to show
    if (!_locationPermissionGranted) {
      return _buildLocationPermissionStep();
    } else if (!_healthPermissionGranted && (Platform.isIOS || Platform.isAndroid)) {
      return _buildHealthPermissionStep();
    } else if (!_batteryOptimizationHandled && Platform.isAndroid) {
      return _buildBatteryOptimizationStep();
    } else {
      return _buildCompletedStep();
    }
  }

  Widget _buildLocationPermissionStep() {
    return _buildPermissionStep(
      icon: Icons.location_on,
      title: 'Location Access',
      description: 'We need location access to track your ruck sessions accurately. This enables:',
      features: [
        'GPS tracking during your rucks',
        'Distance and pace calculations',
        'Route mapping and elevation data',
        'Performance analytics',
      ],
      buttonText: 'Enable Location',
      onPressed: _requestLocationPermission,
      imagePath: 'assets/images/location_permission.png',
    );
  }

  Widget _buildHealthPermissionStep() {
    return _buildPermissionStep(
      icon: Icons.favorite,
      title: Platform.isIOS ? 'Apple Health Integration' : 'Health Integration',
      description: 'Connect with ${Platform.isIOS ? 'Apple Health' : 'your health app'} to enhance your experience:',
      features: [
        'Heart rate monitoring during rucks',
        'Automatic workout syncing',
        'Calorie tracking and analysis',
        'Comprehensive health insights',
      ],
      buttonText: 'Connect Health',
      onPressed: _requestHealthPermission,
      imagePath: Platform.isIOS ? 'assets/images/apple health screen.png' : 'assets/images/health_integration.png',
    );
  }

  Widget _buildBatteryOptimizationStep() {
    return _buildPermissionStep(
      icon: Icons.battery_saver,
      title: 'Background Tracking',
      description: 'For the best tracking experience on Android, we recommend optimizing battery settings:',
      features: [
        'Continuous GPS tracking',
        'Background location updates',
        'Uninterrupted session recording',
        'Reliable performance',
      ],
      buttonText: 'Optimize Settings',
      onPressed: _requestBatteryOptimization,
      imagePath: 'assets/images/battery_optimization.png',
    );
  }

  Widget _buildCompletedStep() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check_circle,
              size: 60,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'All Set!',
            style: AppTextStyles.headlineMedium.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Your app is ready for the best rucking experience. Let\'s get started!',
            style: AppTextStyles.bodyLarge.copyWith(
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _navigateToHome,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'START RUCKING',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward, size: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionStep({
    required IconData icon,
    required String title,
    required String description,
    required List<String> features,
    required String buttonText,
    required VoidCallback onPressed,
    String? imagePath,
  }) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Icon or Image
                  if (imagePath != null)
                    Image.asset(
                      imagePath,
                      height: 200,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            icon,
                            size: 50,
                            color: AppColors.primary,
                          ),
                        );
                      },
                    )
                  else
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        icon,
                        size: 50,
                        color: AppColors.primary,
                      ),
                    ),
                  const SizedBox(height: 32),
                  
                  // Title
                  Text(
                    title,
                    style: AppTextStyles.headlineMedium.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  
                  // Description
                  Text(
                    description,
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  
                  // Features list
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.primary.withOpacity(0.2),
                      ),
                    ),
                    child: Column(
                      children: features.map((feature) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.check_circle,
                              color: AppColors.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                feature,
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Action button
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                buttonText,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          
          // Skip button for non-essential permissions
          if (title.contains('Health') || title.contains('Background'))
            TextButton(
              onPressed: _skipCurrentStep,
              child: Text(
                'Skip for now',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: Colors.grey[600],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _requestLocationPermission() async {
    setState(() => _isProcessing = true);
    
    try {
      final locationService = GetIt.instance<LocationService>();
      final granted = await locationService.requestLocationPermission();
      
      setState(() {
        _locationPermissionGranted = granted;
        _isProcessing = false;
      });
      
      if (granted) {
        AppLogger.info('[ONBOARDING] Location permission granted');
      } else {
        StyledSnackBar.showError(
          context: context,
          message: 'Location permission is required for tracking your rucks.',
          duration: const Duration(seconds: 3),
        );
      }
    } catch (e) {
      AppLogger.error('[ONBOARDING] Error requesting location permission: $e');
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _requestHealthPermission() async {
    setState(() => _isProcessing = true);
    
    try {
      final healthService = GetIt.instance<HealthService>();
      final isAvailable = await healthService.isHealthDataAvailable();
      
      if (isAvailable) {
        final granted = await healthService.requestAuthorization();
        setState(() {
          _healthPermissionGranted = granted;
          _isProcessing = false;
        });
        
        if (granted) {
          AppLogger.info('[ONBOARDING] Health permission granted');
          StyledSnackBar.showSuccess(
            context: context,
            message: 'Health integration enabled!',
            duration: const Duration(seconds: 2),
          );
        }
      } else {
        setState(() {
          _healthPermissionGranted = true; // Skip if not available
          _isProcessing = false;
        });
      }
    } catch (e) {
      AppLogger.error('[ONBOARDING] Error requesting health permission: $e');
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _requestBatteryOptimization() async {
    setState(() => _isProcessing = true);
    
    try {
      if (Platform.isAndroid) {
        await BatteryOptimizationService.ensureBackgroundExecutionPermissions(context: context);
      }
      
      setState(() {
        _batteryOptimizationHandled = true;
        _isProcessing = false;
      });
      
      AppLogger.info('[ONBOARDING] Battery optimization handled');
    } catch (e) {
      AppLogger.error('[ONBOARDING] Error handling battery optimization: $e');
      setState(() {
        _batteryOptimizationHandled = true; // Continue anyway
        _isProcessing = false;
      });
    }
  }

  void _skipCurrentStep() {
    setState(() {
      if (!_locationPermissionGranted) {
        // Don't allow skipping location - it's essential
        return;
      } else if (!_healthPermissionGranted) {
        _healthPermissionGranted = true;
      } else if (!_batteryOptimizationHandled) {
        _batteryOptimizationHandled = true;
      }
    });
  }

  void _navigateToHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false, // Remove all previous routes
    );
  }
}
