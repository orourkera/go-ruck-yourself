import 'dart:async';
import 'package:flutter/material.dart';
import 'package:rucking_app/shared/widgets/styled_snackbar.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/core/services/revenue_cat_service.dart';
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
      'valueProp': 'Log your rucks with detailed metrics including distance, pace, elevation gain, and the most accurate calories burned calculation based on ruck weight, pace and real time elevation change.',
    },
    {
      'title': 'Apple Watch Ready',
      'screenshot': 'assets/images/paywall/watch screenshot.png',
      'valueProp': 'Full Apple Watch integration lets you track your rucks directly from your wrist with live metrics, split notifications and the ability to pause the ruck.',
    },
    {
      'title': 'Ruck Buddies',
      'screenshot': 'assets/images/paywall/ruck_buddies.png',
      'valueProp': 'Connect with fellow ruckers, share routes and compete with your friends to stay motivated.',
    },
    {
      'title': 'Health Integration',
      'screenshot': 'assets/images/paywall/apple health.png',
      'valueProp': 'All your workouts sync directly to Apple Health/Google Fit to keep your fitness data consolidated.',
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
          height: isTablet ? 570 : 480,
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
                    ? Colors.white  // White dot for active page
                    : Colors.white.withOpacity(0.5), // Translucent white for inactive
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
                        mainAxisSize: MainAxisSize.min, // No intrinsic height issues
                        children: [
                          // No need for extra spacing as the carousel is now separate
                          
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
                            child: _buildPlanCard('Weekly', getPlanPrice(0), _selectedPlanIndex == 0),
                          ),
                          SizedBox(height: isTablet ? 12 : 8),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedPlanIndex = 1;
                              });
                            },
                            child: _buildPlanCard('Monthly', getPlanPrice(1), _selectedPlanIndex == 1),
                          ),
                          SizedBox(height: isTablet ? 12 : 8),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedPlanIndex = 2;
                              });
                            },
                            child: _buildPlanCard('Annual', getPlanPrice(2), _selectedPlanIndex == 2),
                          ),
                          
                          // CTA button
                          SizedBox(height: isTablet ? 30 : 25),
                          SizedBox(
                            width: isTablet ? containerWidth * 0.8 : double.infinity,
                            child: ElevatedButton(
                              onPressed: () async {
                                await _handleGetRuckyPressed(context);
                              },
                              style: ElevatedButton.styleFrom(
                                minimumSize: Size(double.infinity, isTablet ? 60 : 50),
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
                          
                          // Legal text and links
                          SizedBox(height: isTablet ? 20 : 15),
                          Text(
                            'Go Ruck Yourself Premium\nAuto-renewing subscription',
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
                                  final uri = Uri.parse('https://getrucky.com/privacy');
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
                                  final uri = Uri.parse('https://getrucky.com/terms');
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
    final revenueCatService = GetIt.instance<RevenueCatService>();
    final offerings = await revenueCatService.getOfferings();
    if (offerings.isNotEmpty) {
      final package = offerings.first.availablePackages.first;
      final isPurchased = await revenueCatService.makePurchase(package);
      if (isPurchased) {
        // After successful purchase, go directly to Home Screen
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        // Handle purchase failure
        StyledSnackBar.showError(
          context: context,
          message: 'Purchase failed. Please try again.',
          duration: const Duration(seconds: 3),
        );
      }
    } else {
      StyledSnackBar.showError(
        context: context,
        message: 'No subscription offerings available.',
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
      padding: EdgeInsets.symmetric(horizontal: isTablet ? 40 : 30), // More horizontal padding
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start, // Move content up
        crossAxisAlignment: CrossAxisAlignment.start, // Left align content
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
                  Shadow(color: Colors.white, offset: Offset(-1, -1), blurRadius: 1),
                  Shadow(color: Colors.white, offset: Offset(1, -1), blurRadius: 1),
                  Shadow(color: Colors.white, offset: Offset(-1, 1), blurRadius: 1),
                  Shadow(color: Colors.white, offset: Offset(1, 1), blurRadius: 1),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
          
          // Reduced spacing to move content up
          SizedBox(height: isTablet ? 20 : 15),
          
          // App Screenshot (adapts to tablet size)
          Container(
            height: isTablet ? 240 : 180, // Increased image height by 50%
            width: double.infinity, // Full width within padding
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(isTablet ? 20 : 16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(isTablet ? 20 : 16),
              child: Image.asset(
                screenshot,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.grey.shade200,
                    child: const Icon(Icons.image_not_supported, size: 40, color: Colors.grey),
                  );
                },
              ),
            ),
          ),
          
          // Reduced spacing to move content up
          SizedBox(height: isTablet ? 25 : 20),
          
          // Value Proposition Text - now left-aligned
          Text(
            valueProp,
            style: TextStyle(
              fontSize: isTablet ? 22 : 18,
              fontWeight: FontWeight.w500,
              color: Colors.white, // White text
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(isTablet ? 12 : 10)),
      child: Padding(
        padding: EdgeInsets.all(isSelected ? (isTablet ? 20.0 : 16.0) : (isTablet ? 16.0 : 12.0)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              planName,
              style: TextStyle(
                fontSize: isSelected 
                  ? (isTablet ? 22 : 18) 
                  : (isTablet ? 20 : 16), 
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
