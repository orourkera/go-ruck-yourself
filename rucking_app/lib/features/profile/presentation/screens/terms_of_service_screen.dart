import 'package:flutter/material.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({Key? key}) : super(key: key);

  // Helper to create styled text sections (same as Privacy Policy)
  Widget _buildSection(String title, String content, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTextStyles.titleMedium.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          content,
          style: AppTextStyles.bodyMedium,
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Terms of Service'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSection(
              'Effective Date: April 10, 2025',
              'App Name: Go Ruck Yourself\nDeveloper: Get Rucky, Inc\nContact: rory@getrucky.com',
              context,
            ),
            _buildSection(
              '1. Acceptance of Terms',
              'By creating an account or using the Go Ruck Yourself app (the "App"), you agree to be bound by these Terms of Service ("Terms"). If you do not agree, do not use the App.',
              context,
            ),
            _buildSection(
              '2. Eligibility',
              'You must be at least 13 years old to use the App. By using the App, you represent that you meet this age requirement and have the legal capacity to enter into these Terms.',
              context,
            ),
             _buildSection(
              '3. User Accounts',
              'To use certain features, you must create an account. You agree to:\n\nProvide accurate and current information\nKeep your login credentials secure\nNotify us immediately if you suspect unauthorized access\n\nYou are responsible for all activity that occurs under your account.',
              context,
            ),
            _buildSection(
              '4. Use of the App',
              'You may use the App solely for personal, non-commercial fitness tracking. You agree not to:\n\nUse the App for any unlawful or harmful purpose\nAttempt to reverse-engineer, decompile, or tamper with the App\nUpload or distribute harmful content, spam, or unauthorized advertising',
              context,
            ),
             _buildSection(
              '5. Location & Health Data',
              'The App uses GPS data (with your permission) and personal metrics (such as height, weight, and age) to calculate calories burned and track ruck sessions. This data is used in accordance with our Privacy Policy.\n\nThe App is not a medical tool and does not provide medical advice. Always consult a qualified healthcare provider before starting any new fitness routine.',
              context,
            ),
             _buildSection(
              '6. Intellectual Property',
              'All content, branding, and functionality in the App is the property of Get Rucky, Inc or its licensors. You may not copy, reproduce, or distribute any part of the App without prior written permission.',
              context,
            ),
             _buildSection(
              '7. Termination',
              'We reserve the right to suspend or terminate your account at any time if you violate these Terms or engage in abusive or unlawful behavior.\n\nYou may delete your account at any time through the App or by contacting us at rory@getrucky.com.',
              context,
            ),
             _buildSection(
              '8. Disclaimers',
              'The App is provided "as is" without warranties of any kind.\nWe do not guarantee the accuracy of fitness calculations or uninterrupted access to the App.\nUse of the App is at your own risk.',
              context,
            ),
             _buildSection(
              '9. Limitation of Liability',
              'To the fullest extent permitted by law, Get Rucky, Inc is not liable for:\n\nAny injuries or health issues resulting from your rucking activity\nLoss or corruption of data\nIndirect, incidental, or consequential damages',
              context,
            ),
            _buildSection(
              '10. Modifications to Terms',
              'We may update these Terms occasionally. We\'ll notify you of any material changes, and your continued use of the App after such changes constitutes your acceptance of the updated Terms.',
              context,
            ),
            _buildSection(
              '11. Governing Law',
              'These Terms are governed by and interpreted under the laws of the State of Colorado, without regard to conflict of law principles.',
              context,
            ),
            _buildSection(
              '12. Contact Us',
              'If you have any questions about these Terms, contact us at:\nEmail: rory@getrucky.com',
              context,
            ),
          ],
        ),
      ),
    );
  }
} 