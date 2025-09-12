import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AboutAppScreen extends StatefulWidget {
  const AboutAppScreen({Key? key}) : super(key: key);

  @override
  State<AboutAppScreen> createState() => _AboutAppScreenState();
}

class _AboutAppScreenState extends State<AboutAppScreen> {
  String _version = '';
  String _buildNumber = '';

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      _version = info.version;
      _buildNumber = info.buildNumber;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About App'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Column(
                  children: [
                    // App icon
                    SizedBox(
                      width: 100,
                      height: 100,
                      child: Image.asset('assets/icon/app_icon.png',
                          fit: BoxFit.contain),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Ruck!',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text('Version $_version ($_buildNumber)',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'About the App',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 12),
              const Text(
                'Ruck! is a rucking tracker designed for the toughest athletes. Track your distance, pace, elevation, calories, and more. Integrates with Apple Health and your Apple Watch for seamless workout logging. Built for privacy, performance, and fun.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              const Text(
                'Contact',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 12),
              SelectableText('support@getrucky.com',
                  style: TextStyle(fontSize: 16)),
              const SizedBox(height: 24),
              const Text(
                'Legal',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 12),
              const Text('All rights reserved. 2025 Ruck!.'),
              const SizedBox(height: 8),
              const Text('Terrain data © OpenStreetMap contributors (ODbL).'),
            ],
          ),
        ),
      ),
    );
  }
}
