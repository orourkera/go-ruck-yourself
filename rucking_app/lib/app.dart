import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/core/services/service_locator.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/splash/presentation/screens/splash_screen.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/home_screen.dart';
import 'package:rucking_app/features/paywall/presentation/screens/paywall_screen.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/session_history_bloc.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/session_complete_screen.dart';
import 'package:rucking_app/features/ruck_session/domain/models/heart_rate_sample.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/active_session_page.dart';
import 'package:rucking_app/shared/theme/app_theme.dart';
import 'package:rucking_app/features/ruck_buddies/presentation/bloc/ruck_buddies_bloc.dart';
import 'package:rucking_app/features/ruck_buddies/presentation/pages/ruck_buddies_screen.dart';

/// Main application widget
class RuckingApp extends StatelessWidget {
  const RuckingApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => getIt<AuthBloc>()..add(AuthCheckRequested()),
        ),
        BlocProvider<SessionHistoryBloc>(
          create: (context) => getIt<SessionHistoryBloc>(),
        ),
        BlocProvider<ActiveSessionBloc>(
          create: (context) => getIt<ActiveSessionBloc>(),
        ),
        BlocProvider<RuckBuddiesBloc>(
          create: (context) => getIt<RuckBuddiesBloc>(),
        ),
      ],
      child: MaterialApp(
        title: 'GRY',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        home: const SplashScreen(),
        onGenerateRoute: (settings) {
          switch (settings.name) {
            case '/home':
              return MaterialPageRoute(builder: (_) => const HomeScreen());
            case '/paywall':
              return MaterialPageRoute(builder: (_) => const PaywallScreen());
            case '/ruck_buddies':
              return MaterialPageRoute(builder: (_) => const RuckBuddiesScreen());
            case '/session_complete':
              final args = settings.arguments as Map<String, dynamic>?;
              if (args != null) {
                return MaterialPageRoute(
                  builder: (_) => SessionCompleteScreen(
                    completedAt: args['completedAt'] as DateTime,
                    ruckId: args['ruckId'] as String,
                    duration: args['duration'] as Duration,
                    distance: args['distance'] as double,
                    caloriesBurned: args['caloriesBurned'] as int,
                    elevationGain: args['elevationGain'] as double,
                    elevationLoss: args['elevationLoss'] as double,
                    ruckWeight: args['ruckWeight'] as double,
                    initialNotes: args['initialNotes'] as String?,
                    heartRateSamples: args['heartRateSamples'] as List<HeartRateSample>?,
                  ),
                );
              } else {
                // Handle error: arguments are required for this route
                return MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('Error')),
                    body: const Center(child: Text('Missing session data.')),
                  ),
                );
              }
            case '/active_session':
              final args = settings.arguments;
              // --- BEGIN EXTRA DIAGNOSTIC LOGGING (remove after bug fixed) ---
              debugPrint('[Route] /active_session args runtimeType: ${args.runtimeType}');
              // If this is not ActiveSessionArgs, log its content for inspection
              if (args is Map) {
                (args as Map).forEach((k, v) => debugPrint('  $k => $v (type: ${v.runtimeType})'));
              }
              // --- END EXTRA DIAGNOSTIC LOGGING ---
              if (args is ActiveSessionArgs) {
                return MaterialPageRoute(
                  builder: (_) => ActiveSessionPage(args: args),
                );
              }
              return MaterialPageRoute(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('Error')),
                  body: const Center(child: Text('Invalid arguments for active session')),
                ),
              );
            default:
              // Optionally handle unknown routes
              return MaterialPageRoute(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: Text('Error')),
                  body: Center(child: Text('Route not found: ${settings.name}')),
                ),
              );
          }
        },
      ),
    );
  }
}