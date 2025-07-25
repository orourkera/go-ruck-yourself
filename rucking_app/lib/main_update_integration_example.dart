/// Example integration of the app update system
/// This shows how to integrate the update system into your main app

import 'package:flutter/material.dart';
import 'package:rucking_app/core/managers/app_update_manager.dart';
import 'package:rucking_app/features/home/widgets/update_banner_widget.dart';

/// Example: Add update banner to home screen
class HomeScreenWithUpdates extends StatelessWidget {
  const HomeScreenWithUpdates({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: Column(
        children: [
          // Update banner at the top (will auto-hide if no updates)
          const UpdateBannerWidget(),
          
          // Your existing home screen content
          const Expanded(
            child: Center(
              child: Text('Your home screen content here'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Example: Add update check to app initialization
class AppInitializer {
  static Future<void> initialize() async {
    // ... your existing initialization code
    
    // Check for updates on app start (after a delay)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 3), () {
        // This will check for updates and show prompt if needed
        final context = navigatorKey.currentContext;
        if (context != null) {
          AppUpdateManager.instance.checkAndPromptForUpdate(
            context,
            promptContext: UpdatePromptContext.automatic,
          );
        }
      });
    });
  }
}

/// Example: Add update check after session completion
class SessionCompletionScreen extends StatefulWidget {
  const SessionCompletionScreen({Key? key}) : super(key: key);

  @override
  State<SessionCompletionScreen> createState() => _SessionCompletionScreenState();
}

class _SessionCompletionScreenState extends State<SessionCompletionScreen>
    with UpdatePromptMixin {

  @override
  void initState() {
    super.initState();
    
    // Check for updates after session completion (good timing!)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkForUpdatesIfAppropriate(
        context: UpdatePromptContext.afterSession,
        features: [
          '🎯 Improved session tracking accuracy',
          '📊 Enhanced performance metrics',
          '🔧 Bug fixes and stability improvements',
        ],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Session Complete')),
      body: const Center(
        child: Text('Congratulations on completing your ruck!'),
      ),
    );
  }
}

/// Example: Add update check button to settings
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // ... your existing settings
          
          const Divider(),
          
          // Update check button
          const UpdateCheckButton(),
          
          // ... more settings
        ],
      ),
    );
  }
}

/// Don't forget to add this to your dependency injection setup
class DISetup {
  static void setupUpdateSystem() {
    // If using GetIt (you already have this)
    // GetIt.instance.registerSingleton<AppUpdateService>(
    //   AppUpdateService(GetIt.instance<ApiClient>()),
    // );
    
    // Or if you prefer to initialize the singleton
    AppUpdateManager.instance; // This will create the singleton
  }
}

// Add this to your main.dart
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  runApp(MyApp());
  
  // Initialize update system
  AppInitializer.initialize();
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey, // Important for update prompts
      title: 'Ruck App',
      home: const HomeScreenWithUpdates(),
    );
  }
}
