import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:rucking_app/shared/widgets/styled_snackbar.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/health_integration/bloc/health_bloc.dart';
import 'package:rucking_app/features/health_integration/presentation/screens/health_integration_intro_screen.dart';
import 'package:rucking_app/features/health_integration/domain/health_service.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/home_screen.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/core/services/revenue_cat_service.dart';
import 'package:rucking_app/core/services/first_launch_service.dart';
import 'package:url_launcher/url_launcher.dart';

/// Paywall screen with auto-scrolling cards to encourage subscription
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({Key? key}) : super(key: key);

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  Timer? _timer;
  int? _selectedPlanIndex;

  // Define the content for each card
  final List<Map<String, String>> _cards = [
    {
      'title': 'Track Your Rucks',
      'screenshot': 'assets/images/paywall/session tracking.PNG',
      'valueProp':
          'Detailed metrics including distance, pace, elevation gain, and METs based calories burned.',
    },
    {
      'title': 'Apple Watch Ready',
      'screenshot': 'assets/images/paywall/watch screenshot.png',
      'valueProp':
          'Apple Watch integration tracks real time heartrate, stats and splits.',
    },
    {
      'title': 'Ruck Buddies',
      'screenshot': 'assets/images/paywall/ruck_buddies.png',
      'valueProp':
          'Like, comment, and connect with fellow ruckers around the world.',
    },
    {
      'title': 'Health Integration',
      'screenshot': 'assets/images/paywall/apple health.png',
      'valueProp':
          'Sync with Apple Health/Google Fit to keep your fitness data consolidated.',
    },
  ];

  @override
  void initState() {
    super.initState();
    // Start auto-scrolling timer
    _startAutoScroll();
  }

  void _startAutoScroll() {
    // Auto-scroll every 5 seconds
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_currentPage < _cards.length - 1) {
        _currentPage++;
      } else {
        _currentPage = 0;
      }

      _pageController.animateToPage(
        _currentPage,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  // Helper method to determine if we're on a tablet
  bool _isTablet(BuildContext context) {
    final data = MediaQuery.of(context);
    return data.size.shortestSide >= 600;
  }

  // Get the appropriate container width based on device
  double _getContainerWidth(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (_isTablet(context)) {
      // On tablets, use a percentage of screen width, with min/max constraints
      return width > 900 ? 500 : width * 0.65;
    } else {
      // On phones, use the full width minus padding
      return width - 40;
    }
  }

  // Helper method to get plan prices (can be made dynamic later)
  String getPlanPrice(int index) {
    if (index == 0) return r'$1.99 / week';
    if (index == 1) return r'$4.99 / month';
    if (index == 2) return r'$29.99 / year';
    return ''; // Default empty string or handle error
  }

  // New method to build the full-bleed carousel
  Widget _buildFullBleedCarousel(bool isTablet) {
    return Stack(
      children: [
        // Main PageView carousel
        Container(
          height:
              isTablet ? 520 : 430, // Reduced height to eliminate extra space
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: PageView.builder(
            controller: _pageController,
            itemCount: _cards.length,
            onPageChanged: (index) {
              setState(() {
                _currentPage = index;
              });
            },
            itemBuilder: (context, index) {
              return _buildCard(
                title: _cards[index]['title']!,
                screenshot: _cards[index]['screenshot']!,
                valueProp: _cards[index]['valueProp']!,
                isTablet: isTablet,
              );
            },
          ),
        ),

        // Page indicators positioned at the bottom of the carousel
        Positioned(
          bottom: 16,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              _cards.length,
              (index) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 6),
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _currentPage == index
                      ? Colors.white // White dot for active page
                      : Colors.white
                          .withOpacity(0.5), // Translucent white for inactive
                  border: Border.all(
                    color: Colors.white,
                    width: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = _isTablet(context);
    final containerWidth = _getContainerWidth(context);

    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      body: MediaQuery.removePadding(
        context: context,
        removeBottom: true,
        child: Column(
          children: [
            // Full bleed green background for carousel that extends to the top edge
            Container(
              color: AppColors.primary,
              width: double.infinity,
              child: Column(
                children: [
                  // Add SafeArea to handle the status bar correctly
                  SafeArea(
                    bottom: false,
                    child: SizedBox(), // Empty widget to create proper spacing
                  ),
                  // Carousel goes here
                  _buildFullBleedCarousel(isTablet),
                ],
              ),
            ),

            // Rest of content (subscription plans, etc.)
            Expanded(
              child: ListView(
                padding: EdgeInsets.only(
                  bottom: isTablet ? 100 : 80, // Bottom padding
                  top: 24, // Space after carousel
                ),
                children: [
                  Center(
                    child: Container(
                      width: containerWidth,
                      // Main content column
                      child: Column(
                        mainAxisSize:
                            MainAxisSize.min, // No intrinsic height issues
                        children: [
                          // No need for extra spacing as the carousel is now separate

                          // Big Orange "Continue for Free" Button
                          Container(
                            width: double.infinity,
                            margin: EdgeInsets.symmetric(
                                horizontal: isTablet ? 24 : 16),
                            child: ElevatedButton(
                              onPressed: () async {
                                // Mark paywall as seen so user doesn't see it again
                                await FirstLaunchService.markPaywallSeen();
                                // Navigate to home screen in free mode
                                Navigator.of(context).pushNamedAndRemoveUntil(
                                  '/home',
                                  (route) => false,
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(
                                  vertical: isTablet ? 16 : 14,
                                  horizontal: isTablet ? 32 : 24,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 2,
                              ),
                              child: Text(
                                'START FOR FREE!',
                                style: TextStyle(
                                  fontFamily: 'Bangers',
                                  fontSize: isTablet ? 22 : 20,
                                  fontWeight: FontWeight.normal,
                                  letterSpacing: 1.2,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                          SizedBox(height: isTablet ? 32 : 24),

                          // Subscription Plans heading
                          Text(
                            'SUBSCRIPTION PLANS',
                            style: AppTextStyles.paywallHeadline.copyWith(
                              fontSize: isTablet ? 24 : 20,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 15),

                          // Plan options
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedPlanIndex = 0;
                              });
                            },
                            child: _buildPlanCard('Weekly', getPlanPrice(0),
                                _selectedPlanIndex == 0),
                          ),
                          SizedBox(height: isTablet ? 12 : 8),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedPlanIndex = 1;
                              });
                            },
                            child: _buildPlanCard('Monthly', getPlanPrice(1),
                                _selectedPlanIndex == 1),
                          ),
                          SizedBox(height: isTablet ? 12 : 8),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedPlanIndex = 2;
                              });
                            },
                            child: _buildPlanCard('Annual', getPlanPrice(2),
                                _selectedPlanIndex == 2),
                          ),

                          // CTA button
                          SizedBox(height: isTablet ? 30 : 25),
                          SizedBox(
                            width: isTablet
                                ? containerWidth * 0.8
                                : double.infinity,
                            child: ElevatedButton(
                              onPressed: () async {
                                await _handleGetRuckyPressed(context);
                              },
                              style: ElevatedButton.styleFrom(
                                minimumSize:
                                    Size(double.infinity, isTablet ? 60 : 50),
                                backgroundColor: AppColors.primary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                'GET RUCKY',
                                style: TextStyle(
                                  fontSize: isTablet ? 22 : 18,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Bangers',
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),

                          // Info text below CTA button
                          SizedBox(height: isTablet ? 16 : 12),
                          Text(
                            'Only subscribers have access to social features and detailed ruck tracking.',
                            style: AppTextStyles.bodySmall.copyWith(
                              fontSize: isTablet ? 14 : null,
                            ),
                            textAlign: TextAlign.center,
                          ),

                          // Legal text and links
                          SizedBox(height: isTablet ? 20 : 15),
                          Text(
                            'Ruck! Premium\nAuto-renewing subscription',
                            style: AppTextStyles.bodySmall.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: isTablet ? 14 : null,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: isTablet ? 8 : 4),
                          Text(
                            'Prices may vary by region. Subscription auto-renews unless cancelled at least 24 hours before the end of the period.',
                            style: AppTextStyles.bodySmall.copyWith(
                              fontSize: isTablet ? 13 : null,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: isTablet ? 12 : 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              GestureDetector(
                                onTap: () async {
                                  final uri =
                                      Uri.parse('https://getrucky.com/privacy');
                                  if (await canLaunchUrl(uri)) {
                                    await launchUrl(uri);
                                  }
                                },
                                child: Text(
                                  'Privacy Policy',
                                  style: AppTextStyles.labelSmall.copyWith(
                                    decoration: TextDecoration.underline,
                                    fontSize: isTablet ? 12 : 10,
                                  ),
                                ),
                              ),
                              SizedBox(width: isTablet ? 20 : 12),
                              GestureDetector(
                                onTap: () async {
                                  final uri =
                                      Uri.parse('https://getrucky.com/terms');
                                  if (await canLaunchUrl(uri)) {
                                    await launchUrl(uri);
                                  }
                                },
                                child: Text(
                                  'Terms of Use',
                                  style: AppTextStyles.labelSmall.copyWith(
                                    decoration: TextDecoration.underline,
                                    fontSize: isTablet ? 12 : 10,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          // Extra bottom padding for safety
                          SizedBox(height: isTablet ? 60 : 45),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleGetRuckyPressed(BuildContext context) async {
    print('[Paywall] Get Rucky button pressed');
    try {
      final revenueCatService = GetIt.instance<RevenueCatService>();
      print('[Paywall] RevenueCatService obtained');

      final offerings = await revenueCatService.getOfferings();
      print('[Paywall] Offerings received: ${offerings.length} offerings');

      if (offerings.isNotEmpty) {
        final package = offerings.first.availablePackages.first;
        print('[Paywall] Making purchase for package: ${package.identifier}');

        final isPurchased = await revenueCatService.makePurchase(package);
        print('[Paywall] Purchase result: $isPurchased');

        if (isPurchased) {
          // Mark paywall as seen since user successfully purchased
          await FirstLaunchService.markPaywallSeen();

          print('[Paywall] Purchase successful, navigating to next screen');
          final authBloc = BlocProvider.of<AuthBloc>(context);
          final authState = authBloc.state;

          if (authState is Authenticated) {
            if (Platform.isIOS) {
              // Navigate to Apple Health integration screen on iOS
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => BlocProvider(
                    create: (context) => HealthBloc(
                      healthService: HealthService(),
                      userId: authState.user.userId,
                    ),
                    child: HealthIntegrationIntroScreen(
                      userId: authState.user.userId,
                    ),
                  ),
                ),
              );
            } else {
              // Navigate directly to HomeScreen on Android and other platforms
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const HomeScreen()),
              );
            }
          } else {
            // Fallback if user is not authenticated (shouldn't happen)
            Navigator.pushReplacementNamed(context, '/home');
          }
        } else {
          // Handle purchase failure
          print('[Paywall] Purchase failed');
          StyledSnackBar.showError(
            context: context,
            message: 'Purchase failed. Please try again.',
            duration: const Duration(seconds: 3),
          );
        }
      } else {
        print('[Paywall] No offerings available');
        StyledSnackBar.showError(
          context: context,
          message: 'No subscription offerings available.',
          duration: const Duration(seconds: 3),
        );
      }
    } catch (e) {
      print('[Paywall] Error in _handleGetRuckyPressed: $e');
      StyledSnackBar.showError(
        context: context,
        message: 'Error occurred: $e',
        duration: const Duration(seconds: 3),
      );
    }
  }

  // Build card with more horizontal padding and left-aligned text
  Widget _buildCard({
    required String title,
    required String screenshot,
    required String valueProp,
    bool isTablet = false,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: isTablet ? 40 : 30), // More horizontal padding
      // Use padding only at the top to eliminate space at the bottom
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start, // Move content up
        crossAxisAlignment: CrossAxisAlignment.start, // Left align content
        mainAxisSize: MainAxisSize.min, // Minimize vertical space
        children: [
          // Reduced top padding to move content up
          SizedBox(height: isTablet ? 10 : 5),

          // Title still centered
          Center(
            child: Text(
              title,
              style: TextStyle(
                fontFamily: 'Bangers',
                fontSize: isTablet ? 42 : 32,
                color: AppColors.secondary, // Orange color
                letterSpacing: 1.2,
                shadows: [
                  // White outline effect
                  Shadow(
                      color: Colors.white,
                      offset: Offset(-1, -1),
                      blurRadius: 1),
                  Shadow(
                      color: Colors.white,
                      offset: Offset(1, -1),
                      blurRadius: 1),
                  Shadow(
                      color: Colors.white,
                      offset: Offset(-1, 1),
                      blurRadius: 1),
                  Shadow(
                      color: Colors.white, offset: Offset(1, 1), blurRadius: 1),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),

          // Reduced spacing to move content up
          SizedBox(height: isTablet ? 20 : 15),

          // App Screenshot with no background or container effects - larger size
          Image.asset(
            screenshot,
            height: isTablet ? 300 : 220, // Increased image height
            width: double.infinity,
            fit: BoxFit.contain, // Keep contain to prevent cropping
            errorBuilder: (context, error, stackTrace) {
              return SizedBox(
                height: isTablet ? 300 : 220, // Match increased height
                child: Icon(Icons.image_not_supported,
                    size: 40, color: Colors.white.withOpacity(0.8)),
              );
            },
          ),

          // Increased spacing between image and text
          SizedBox(height: isTablet ? 30 : 24),

          // Value Proposition Text - now left-aligned with tightened spacing
          Text(
            valueProp,
            style: TextStyle(
              fontSize: isTablet ? 22 : 18,
              fontWeight: FontWeight.w500,
              color: Colors.white, // White text
              height: 1.2, // Tighter line spacing
            ),
            textAlign: TextAlign.left, // Left aligned text
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard(String planName, String price, bool isSelected) {
    final isTablet = _isTablet(context);

    // Determine free trial period based on plan name
    String trialPeriod = '';
    if (planName == 'Weekly') {
      trialPeriod = '3 day free trial!';
    } else if (planName == 'Monthly') {
      trialPeriod = '1 week free trial!';
    } else if (planName == 'Annual') {
      trialPeriod = '1 month free trial!';
    }

    return Card(
      elevation: isSelected ? 6 : 2,
      color: isSelected ? AppColors.secondary : null,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(isTablet ? 12 : 10)),
      child: Padding(
        padding: EdgeInsets.all(
            isSelected ? (isTablet ? 20.0 : 16.0) : (isTablet ? 16.0 : 12.0)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              planName,
              style: TextStyle(
                fontSize:
                    isSelected ? (isTablet ? 22 : 18) : (isTablet ? 20 : 16),
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : null,
                fontFamily: isSelected ? 'Bangers' : null,
                inherit: false, // Fix TextStyle interpolation issue
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  price,
                  style: TextStyle(
                    fontSize: isSelected
                        ? (isTablet ? 22 : 18)
                        : (isTablet ? 20 : 16),
                    fontWeight: FontWeight.w500,
                    color: isSelected ? Colors.white : null,
                    fontFamily: isSelected ? 'Bangers' : null,
                    inherit: false, // Fix TextStyle interpolation issue
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  trialPeriod,
                  style: TextStyle(
                    fontSize: isSelected
                        ? (isTablet ? 14 : 12)
                        : (isTablet ? 13 : 11),
                    fontWeight: FontWeight.w500,
                    color: isSelected
                        ? Colors.white
                        : AppColors.primary, // Use app's green color
                    fontStyle: FontStyle.italic,
                    inherit: false, // Fix TextStyle interpolation issue
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
