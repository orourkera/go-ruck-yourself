import 'package:flutter/material.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({Key? key}) : super(key: key);

  // Helper to create styled text sections
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
        title: const Text('Privacy Policy'),
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
              '1. Introduction',
              'Welcome to Go Ruck Yourself! We respect your privacy and are committed to protecting your personal information. This Privacy Policy explains how we collect, use, store, and protect your data when you use our app to track rucking sessions, calculate calories burned, and review your ruck history.\n\nBy using our app, you agree to the practices described in this policy.',
              context,
            ),
            _buildSection(
              '2. Information We Collect',
              'To provide and improve the Go Ruck Yourself experience, we may collect:\n\na. Account Information\nName or username\nEmail address\nPassword (encrypted and never stored in plain text)\n\nb. Activity, Fitness & Health Data\nHeight, weight, age, gender (used for calorie calculations)\nRuck details: distance, duration, pace, ruck weight\nHistorical session data tied to your account\nHeart rate data (if you enable Health integration):\n- Used for real-time feedback, calorie estimation, and post-session analytics (average, max, min heart rate)\n- Stored locally on your device using secure app storage\n- Never sold or used for advertising\n- Not shared with third parties unless you enable cloud sync or backup\n\nc. Location Data\nGPS data (used only with your permission to track sessions)\n\nd. Device and Technical Data\nDevice model and OS version\nApp usage and interaction data\nCrash logs and diagnostics (for performance improvements)',
              context,
            ),
             _buildSection(
              '3. How We Use Your Information',
              'We use your data to:\n\nAuthenticate and manage your account\nTrack your rucks and calculate calories burned\nStore your session history and progress\nDisplay heart rate analytics and provide feedback during sessions (if enabled)\nImprove app functionality and fix issues\nProvide user support and respond to feedback\nSend important updates or changes',
              context,
            ),
             _buildSection(
              '4. Data Storage & Security',
              'Your data is securely stored in the cloud and/or on your device. Heart rate samples are stored locally using secure app storage and are not uploaded unless you explicitly enable cloud sync. While we take strong precautions, no method of data transmission or storage is 100% secure. We recommend using a strong password and protecting your account.',
              context,
            ),
             _buildSection(
              '5. Data Sharing',
              'We do not sell or rent your personal data.\n\nWe share data in the following ways:\n\na. Third-Party Services\nThird-party providers who help us operate the app (e.g., cloud services, analytics)\nLaw enforcement or legal authorities, when required\nProtect against fraud or security threats\n\nb. Ruck Buddies Feature\nOur app includes a social feature called "Ruck Buddies" that allows users to view ruck sessions completed by other users. By default, your completed ruck sessions will be visible to other users in the Ruck Buddies feed, including your username and session details (distance, duration, calories burned, elevation gain, and an approximate route map). Your exact start/end locations are not shared for privacy reasons.\n\nAll third parties must agree to keep your data confidential.',
              context,
            ),
             _buildSection(
              '6. Your Rights & Choices',
              'You have control over your data. You can:\n\nUpdate your profile info\nAccess or export your ruck history\nDelete your account and all stored data\nTurn off location and health permissions in your device settings\nOpt out of heart rate data collection by disabling Health integration in the app settings. Disabling heart rate will revert calorie estimation to a standard MET-based calculation.\nControl Ruck Sharing Privacy by toggling the "Allow Ruck Sharing" option in your profile settings. Additionally, you can choose to make individual ruck sessions private even if sharing is enabled globally.\n\nTo exercise any of these rights, email us at rory@getrucky.com.',
              context,
            ),
             _buildSection(
              '7. Data Retention',
              'We keep your data as long as your account is active. When you delete your account, we remove your data from our systems within a reasonable timeframe, unless legally required to retain it.',
              context,
            ),
             _buildSection(
              '8. Children\'s Privacy',
              'Go Ruck Yourself is not intended for children under 13. We do not knowingly collect data from anyone under this age. If we discover such data has been collected, it will be deleted immediately.',
              context,
            ),
             _buildSection(
              '9. Changes to This Policy',
              'We may update this Privacy Policy as our app evolves or to comply with legal requirements. If major changes are made, we\'ll notify you via email or in-app notification.',
              context,
            ),
             _buildSection(
              '10. Contact Us',
              'If you have any questions about this Privacy Policy or your data, contact us:\nEmail: rory@getrucky.com',
              context,
            ),
          ],
        ),
      ),
    );
  }
} 