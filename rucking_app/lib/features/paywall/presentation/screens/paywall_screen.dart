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
      'title': 'Go Ruck Yourself',
      'screenshot': 'assets/images/go ruck yourself copy.png',
      'valueProp': 'Track your ruck sessions, calorie burn, and sync with Apple Fitness.',
    },
  ];

  @override
  void initState() {
    super.initState();
    // No auto-scrolling timer needed since we have only one card
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
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildCard(
                  title: _cards[0]['title']!,
                  screenshot: _cards[0]['screenshot']!,
                  valueProp: _cards[0]['valueProp']!,
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
                              child: _buildPlanCard('Weekly', r'$1.99 / week', _selectedPlanIndex == 0),
                            ),
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedPlanIndex = 1;
                                });
                              },
                              child: _buildPlanCard('Monthly', r'$4.99 / month', _selectedPlanIndex == 1),
                            ),
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedPlanIndex = 2;
                                });
                              },
                              child: _buildPlanCard('Annual', r'$29.99 / year', _selectedPlanIndex == 2),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Move Get Rucky Button up here
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.lock_open),
                            label: Text(
                              'GET RUCKY',
                              style: AppTextStyles.labelLarge.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.secondary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: () {
                              _handleGetRuckyPressed(context);
                            },
                          ),
                        ),
                      ),
                      // Subscription Information and Legal Links
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              "Subscription Information",
                              style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "• Title: Go Rucky Premium\n"
                              "• Length: Weekly, Monthly, or Annual\n"
                              "• Price: as shown above\n"
                              "• Payment will be charged to your Apple ID account at confirmation of purchase.\n"
                              "• Subscription automatically renews unless canceled at least 24 hours before the end of the current period.\n"
                              "• You can manage and cancel your subscription in your App Store account settings at any time.",
                              style: AppTextStyles.bodySmall,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: () async {
                                final url = Uri.parse("https://getrucky.com/terms");
                                if (await canLaunchUrl(url)) launchUrl(url);
                              },
                              child: Text(
                                "Terms of Use",
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.primary,
                                  decoration: TextDecoration.underline,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            GestureDetector(
                              onTap: () async {
                                final url = Uri.parse("https://getrucky.com/privacy");
                                if (await canLaunchUrl(url)) launchUrl(url);
                              },
                              child: Text(
                                "Privacy Policy",
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.primary,
                                  decoration: TextDecoration.underline,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
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
          // App Screenshot (larger, no background)
          SizedBox(
            height: 190, // doubled from 95
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
            "A subscription is required to use this app. It's by ruckers and for ruckers and that has a price.",
            style: AppTextStyles.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
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
