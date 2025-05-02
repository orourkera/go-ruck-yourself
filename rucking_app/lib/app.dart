import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/core/services/service_locator.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/location_service.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/active_session_screen.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/session_complete_screen.dart';
import 'package:rucking_app/features/splash/presentation/screens/splash_screen.dart';
import 'package:rucking_app/shared/theme/app_theme.dart';

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
        BlocProvider(
          create: (context) => ActiveSessionBloc(apiClient: getIt<ApiClient>(), locationService: getIt<LocationService>()),
        ),
      ],
      child: MaterialApp(
        title: 'GRY',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        navigatorKey: getIt<GlobalKey<NavigatorState>>(),
        home: const SplashScreen(),
        // Routes will be added here as we develop more screens
        routes: {
          // Define routes here
        },
        onGenerateRoute: (settings) {
          if (settings.name == '/activeSession') {
            final args = settings.arguments as Map<String, dynamic>? ?? {};
            return MaterialPageRoute(
              builder: (context) => ActiveSessionScreen(
                ruckId: args['ruckId'] ?? '',
                ruckWeight: (args['ruckWeight'] as num?)?.toDouble() ?? 0.0,
                userWeight: (args['userWeight'] as num?)?.toDouble() ?? 0.0,
                displayRuckWeight: (args['ruckWeight'] as num?)?.toDouble() ?? 0.0,
                preferMetric: args['preferMetric'] ?? true,
                plannedDuration: args['plannedDuration'] as int?,
                notes: args['notes'] as String?,
              ),
              settings: settings,
            );
          }
          if (settings.name == '/sessionComplete') {
            // Expect ActiveSessionCompleted state as arguments
            final completedState = settings.arguments as ActiveSessionCompleted?;
            if (completedState != null) {
              return MaterialPageRoute(
                builder: (context) => SessionCompleteScreen(
                  // Pass individual fields from the state to the screen constructor
                  completedAt: completedState.completedAt,
                  ruckId: completedState.ruckId,
                  duration: completedState.elapsed,
                  distance: completedState.distance, // Assuming SessionCompleteScreen takes distance in km
                  caloriesBurned: completedState.caloriesBurned.toInt(), // Convert double to int
                  elevationGain: completedState.elevationGain,
                  elevationLoss: completedState.elevationLoss,
                  ruckWeight: completedState.ruckWeightKg ?? 0.0, // Use ruckWeightKg, provide default
                  // initialNotes might come from somewhere else or be null
                ),
                settings: settings, // Pass settings for potential future use
              );
            } else {
              print("Error: Missing or invalid arguments for /sessionComplete");
              return MaterialPageRoute(builder: (context) => const SplashScreen());
            }
          }
          return null;
        },
      ),
    );
  }
}