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
  
  @override
  Widget build(BuildContext context) {
    final isTablet = _isTablet(context);
    final containerWidth = _getContainerWidth(context);
    
    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      // Use MediaQuery.removePadding to eliminate any unexpected padding
      body: MediaQuery.removePadding(
        context: context,
        removeBottom: true,
        child: SafeArea(
          bottom: true,
          // Use simple ListView instead of nested scroll containers
          child: ListView(
            // Add generous padding to ensure content doesn't touch edges
            padding: EdgeInsets.only(
              bottom: isTablet ? 100 : 80, // Much larger bottom padding
              top: isTablet ? 20 : 10,
            ),
            children: [
              Center(
                child: Container(
                  width: containerWidth,
                  // Main content column
                  child: Column(
                    mainAxisSize: MainAxisSize.min, // No intrinsic height issues
                    children: [
                      // Carousel of cards
                      Container(
                        height: isTablet ? 380 : 320,
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
                      
                      // Page indicators
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          _cards.length,
                          (index) => Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _currentPage == index
                                ? AppColors.primary
                                : Colors.grey.shade300,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      
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

  Widget _buildCard({
    required String title,
    required String screenshot,
    required String valueProp,
    bool isTablet = false,
}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          title,
          style: TextStyle(
            fontFamily: 'Bangers', 
            fontSize: isTablet ? 42 : 32,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : Colors.black87,
            letterSpacing: 1.2,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: isTablet ? 20 : 12),
        // App Screenshot (adapts to tablet size)
        Container(
          height: isTablet ? 160 : 120,
          margin: EdgeInsets.symmetric(horizontal: isTablet ? 40 : 20),
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
        SizedBox(height: isTablet ? 30 : 18),
        // Value Proposition Text
        Text(
          valueProp,
          style: TextStyle(
            fontSize: isTablet ? 22 : 18,
            fontWeight: FontWeight.w500,
            color: Colors.black,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: isTablet ? 15 : 10),
        // Disclaimer below value prop in same style
        Text(
          "A subscription is required to use this app. It's by ruckers and for ruckers and that has a price. All plans come with a free trial period so give it a shot, rucker.",
          style: AppTextStyles.bodySmall.copyWith(
            fontSize: isTablet ? 15 : null,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildPlanCard(String planName, String price, bool isSelected) {
    final isTablet = _isTablet(context);
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
              ),
            ),
            Text(
              price,
              style: TextStyle(
                fontSize: isSelected 
                  ? (isTablet ? 22 : 18) 
                  : (isTablet ? 20 : 16), 
                fontWeight: FontWeight.w500,
                color: isSelected ? Colors.white : null,
                fontFamily: isSelected ? 'Bangers' : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
