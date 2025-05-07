import 'dart:async';
import 'package:flutter/material.dart';
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

  List<dynamic> _packages = [];

  // Define the content for each card
  final List<Map<String, String>> _cards = [
    {
      'title': 'Go Ruck Yourself',
      'screenshot': 'assets/images/go ruck yourself copy.png',
      'valueProp': 'Track your ruck sessions, calorie burn, and sync with Apple Fitness.',
    },
  ];

  @override
  void initState() {
    super.initState();
    _fetchOfferings();
    // No auto-scrolling timer needed since we have only one card
  }

  Future<void> _fetchOfferings() async {
    final revenueCatService = GetIt.instance<RevenueCatService>();
    final offerings = await revenueCatService.getOfferings();
    if (offerings.isNotEmpty) {
      final pkgs = offerings.first.availablePackages;
      // Debug: Print identifiers and types
      print('Available packages:');
      for (final pkg in pkgs) {
        print('id: ${pkg.identifier}, type: ${pkg.packageType}, price: ${pkg.storeProduct.priceString}');
      }
      setState(() {
        _packages = pkgs;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _buildCard(
                title: _cards[0]['title']!,
                screenshot: _cards[0]['screenshot']!,
                valueProp: _cards[0]['valueProp']!,
              ),
            ),
            const SizedBox(height: 20),
            // Subscription Plans Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  Text(
                    'SUBSCRIPTION PLANS',
                    style: AppTextStyles.paywallHeadline.copyWith(fontSize: 20),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedPlanIndex = 0;
                            });
                          },
                          child: _buildPlanCard('Weekly', getPlanPrice(0), _selectedPlanIndex == 0),
                        ),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedPlanIndex = 1;
                            });
                          },
                          child: _buildPlanCard('Monthly', getPlanPrice(1), _selectedPlanIndex == 1),
                        ),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedPlanIndex = 2;
                            });
                          },
                          child: _buildPlanCard('Annual', getPlanPrice(2), _selectedPlanIndex == 2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Get Rucky Button
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    child: ElevatedButton(
                      onPressed: () async {
                        await _handleGetRuckyPressed(context);
                      },
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'GET RUCKY',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Bangers',
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  // Add legal links and subscription info at the bottom
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'Go Ruck Yourself Premium\nAuto-renewing subscription',
                          style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Prices may vary by region. Subscription auto-renews unless cancelled at least 24 hours before the end of the period.',
                          style: AppTextStyles.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            GestureDetector(
                              onTap: () async {
                                const url = 'https://getrucky.com/privacy';
                                if (await canLaunch(url)) {
                                  await launch(url);
                                }
                              },
                              child: Text(
                                'Privacy Policy',
                                style: AppTextStyles.bodySmall.copyWith(
                                  decoration: TextDecoration.underline,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 18),
                            GestureDetector(
                              onTap: () async {
                                const url = 'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';
                                if (await canLaunch(url)) {
                                  await launch(url);
                                }
                              },
                              child: Text(
                                'Terms of Use',
                                style: AppTextStyles.bodySmall.copyWith(
                                  decoration: TextDecoration.underline,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
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
      final packages = offerings.first.availablePackages;
      final selectedIndex = _selectedPlanIndex ?? 0;
      final identifiers = ['\$rc_weekly', '\$rc_monthly', '\$rc_annual'];
      final selectedIdentifier = identifiers[selectedIndex];
      dynamic package;
      try {
        package = packages.firstWhere((pkg) => pkg.identifier == selectedIdentifier);
      } catch (_) {
        package = packages.first;
      }
        final isPurchased = await revenueCatService.makePurchase(package);
        if (isPurchased) {
          // After successful purchase, go directly to Home Screen
          Navigator.pushReplacementNamed(context, '/home');
        } else {
          // Handle purchase failure
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Purchase failed. Please try again.')),
          );
        }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No subscription offerings available.')),
      );
    }
  }

  Widget _buildCard({
    required String title,
    required String screenshot,
    required String valueProp,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: AppTextStyles.paywallHeadline.copyWith(fontSize: 32), 
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          // App Screenshot (smaller, no background)
          SizedBox(
            height: 95, // Further reduced to save space
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset(
                screenshot,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
          const SizedBox(height: 18),
          // Value Proposition Text
          Text(
            valueProp,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.black,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          // Disclaimer below value prop in same style
          Text(
            "A subscription is required to use this app. It's by ruckers and for ruckers and that has a price. All plans come with a free trial period so give it a shot, rucker.",
            style: AppTextStyles.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String getPlanPrice(int index) {
    // Use identifier for robust mapping
    final identifiers = ['\$rc_weekly', '\$rc_monthly', '\$rc_annual'];
    if (_packages.isEmpty) return '';
    try {
      final pkg = _packages.firstWhere(
        (p) => p.identifier == identifiers[index],
      );
      return pkg.storeProduct.priceString ?? '';
    } catch (_) {
      return '';
    }
  }

  Widget _buildPlanCard(String planName, String price, bool isSelected) {
    return Card(
      elevation: isSelected ? 6 : 2,
      color: isSelected ? AppColors.secondary : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: EdgeInsets.all(isSelected ? 16.0 : 12.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              planName,
              style: TextStyle(
                fontSize: isSelected ? 18 : 16, 
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : null,
                fontFamily: isSelected ? 'Bangers' : null,
              ),
            ),
            Text(
              price,
              style: TextStyle(
                fontSize: isSelected ? 18 : 16, 
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
