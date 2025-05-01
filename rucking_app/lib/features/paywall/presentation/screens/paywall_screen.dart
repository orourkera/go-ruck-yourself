import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/core/services/revenue_cat_service.dart';

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

  // Define the content for each card
  final List<Map<String, String>> _cards = [
    {
      'title': 'Go Ruck Yourself',
      'screenshot': 'assets/screenshots/screenshot1.png',
      'valueProp': 'Track your ruck sessions in standard or metric weights.',
    },
    {
      'title': 'Go Ruck Yourself',
      'screenshot': 'assets/screenshots/screenshot2.png',
      'valueProp': 'The most precise calorie tracking based on body weight, pace and real-time elevation change.',
    },
    {
      'title': 'Go Ruck Yourself',
      'screenshot': 'assets/screenshots/screenshot3.png',
      'valueProp': 'Easily sync all your rucks with Apple Fitness.',
    },
    {
      'title': 'Go Ruck Yourself',
      'valueProp': "You'll never have more fun rucking.",
      'screenshot': 'assets/screenshots/screenshot4.png',
    },
  ];

  @override
  void initState() {
    super.initState();
    // Start auto-scrolling timer
    _timer = Timer.periodic(const Duration(seconds: 5), (Timer timer) {
      if (_currentPage < _cards.length - 1) {
        _currentPage++;
      } else {
        _currentPage = 0;
      }
      _pageController.animateToPage(
        _currentPage,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeIn,
      );
    });
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
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (int page) {
                  setState(() {
                    _currentPage = page;
                  });
                },
                itemCount: _cards.length,
                itemBuilder: (context, index) {
                  return _buildCard(
                    title: _cards[index]['title']!,
                    screenshot: _cards[index]['screenshot']!,
                    valueProp: _cards[index]['valueProp']!,
                  );
                },
              ),
            ),
            // Page indicators
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
                        ? Theme.of(context).primaryColor
                        : Colors.grey.shade400,
                  ),
                ),
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Get Rucky',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
            style: AppTextStyles.paywallHeadline, 
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 30),
          // App Screenshot
          Container(
            height: MediaQuery.of(context).size.height * 0.5,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 10,
                  offset: Offset(0, 5),
                ),
              ],
              image: DecorationImage(
                image: AssetImage(screenshot),
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 30),
          // Value Proposition Text
          Text(
            valueProp,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
