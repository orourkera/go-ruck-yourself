import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import 'package:rucking_app/core/services/app_lifecycle_service.dart';
import 'package:rucking_app/core/services/service_locator.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/auth/presentation/screens/login_screen.dart';
import 'package:rucking_app/features/auth/presentation/screens/password_reset_screen.dart';
import 'package:rucking_app/features/auth/presentation/screens/auth_callback_screen.dart';
import 'package:rucking_app/features/splash/presentation/screens/splash_screen.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/home_screen.dart';
import 'package:rucking_app/features/paywall/presentation/screens/paywall_screen.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/session_history_bloc.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/session_bloc.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/session_complete_screen.dart';
import 'package:rucking_app/features/ruck_session/domain/models/heart_rate_sample.dart';
import 'package:rucking_app/features/ruck_session/domain/models/session_split.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_session.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/active_session_page.dart';
import 'package:rucking_app/shared/theme/dynamic_theme.dart';
import 'package:rucking_app/features/ruck_buddies/presentation/bloc/ruck_buddies_bloc.dart';
import 'package:rucking_app/features/ruck_buddies/presentation/pages/ruck_buddies_screen.dart';
import 'package:rucking_app/features/health_integration/bloc/health_bloc.dart';
import 'package:rucking_app/features/health_integration/domain/health_service.dart';
import 'package:rucking_app/features/social/presentation/bloc/social_bloc.dart';
import 'package:rucking_app/features/notifications/presentation/bloc/notification_bloc.dart';
import 'package:rucking_app/features/notifications/presentation/bloc/notification_event.dart';
import 'package:rucking_app/features/achievements/presentation/screens/achievements_hub_screen.dart';
import 'package:rucking_app/features/achievements/presentation/bloc/achievement_bloc.dart';
import 'package:rucking_app/features/premium/presentation/screens/post_session_upsell_screen.dart';
import 'package:rucking_app/features/duels/presentation/screens/duels_list_screen.dart';
import 'package:rucking_app/features/duels/presentation/screens/duel_detail_screen.dart';
import 'package:rucking_app/features/duels/presentation/screens/create_duel_screen.dart';
import 'package:rucking_app/features/duels/presentation/screens/duel_invitations_screen.dart';
import 'package:rucking_app/features/duels/presentation/screens/duel_stats_screen.dart';

/// Main application widget
class RuckingApp extends StatefulWidget {
  const RuckingApp({Key? key}) : super(key: key);

  @override
  State<RuckingApp> createState() => _RuckingAppState();
}

class _RuckingAppState extends State<RuckingApp> with WidgetsBindingObserver {
  late AppLifecycleService _lifecycleService;

  @override
  void initState() {
    super.initState();
    
    // Initialize the lifecycle service
    _lifecycleService = getIt<AppLifecycleService>();
    _lifecycleService.initialize();
    WidgetsBinding.instance?.addObserver(this);
  }

  @override
  void dispose() {
    _lifecycleService.dispose();
    WidgetsBinding.instance?.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // The AppLifecycleService automatically handles this via WidgetsBindingObserver
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>(
          create: (context) => getIt<AuthBloc>(),
        ),
        BlocProvider<SessionHistoryBloc>(
          create: (context) => getIt<SessionHistoryBloc>(),
        ),
        BlocProvider<ActiveSessionBloc>(
          create: (context) {
            final bloc = getIt<ActiveSessionBloc>();
            // Set bloc reference in lifecycle service
            _lifecycleService.setBlocReferences(activeSessionBloc: bloc);
            return bloc;
          },
        ),
        BlocProvider<SessionBloc>(
          create: (context) => getIt<SessionBloc>(),
        ),
        BlocProvider<RuckBuddiesBloc>(
          create: (context) => getIt<RuckBuddiesBloc>(),
        ),
        BlocProvider<HealthBloc>(
          create: (context) => getIt<HealthBloc>(),
        ),
        BlocProvider<SocialBloc>(
          create: (context) => getIt<SocialBloc>(),
        ),
        BlocProvider<NotificationBloc>(
          create: (context) {
            final bloc = getIt<NotificationBloc>()
              ..add(const NotificationsRequested())
              ..startPolling();
            // Set bloc reference in lifecycle service
            _lifecycleService.setBlocReferences(notificationBloc: bloc);
            return bloc;
          },
        ),
        BlocProvider<AchievementBloc>(
          create: (context) => getIt<AchievementBloc>(),
        ),
      ],
      child: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, authState) {
          // Get the current user from the auth state
          final user = authState is Authenticated ? (authState as Authenticated).user : null;
          
          // Get the current theme mode
          final brightness = MediaQuery.platformBrightnessOf(context);
          final isDarkMode = brightness == Brightness.dark;
          
          // Use a key based on user gender to force rebuild when gender changes
          // This ensures the theme updates immediately after registration or profile updates
          final String genderKey = user?.gender ?? 'default';
          
          return MaterialApp(
            key: Key(genderKey), // Force rebuild when gender changes
            title: 'GRY',
            debugShowCheckedModeBanner: false,
            theme: DynamicTheme.getThemeData(user, false),
            darkTheme: DynamicTheme.getThemeData(user, true),
            themeMode: ThemeMode.system,
            home: const SplashScreen(),
            onGenerateRoute: (settings) {
              switch (settings.name) {
                case '/home':
                  return MaterialPageRoute(builder: (_) => const HomeScreen());
                case '/login':
                  return MaterialPageRoute(builder: (_) => LoginScreen());
                case '/password_reset':
                  final args = settings.arguments;
                  String? token;
                  if (args is Map<String, dynamic>) {
                    token = args['token'] as String?;
                  } else if (args is String) {
                    token = args;
                  }
                  return MaterialPageRoute(
                    builder: (_) => PasswordResetScreen(token: token),
                  );
                case '/paywall':
                  return MaterialPageRoute(builder: (_) => const PaywallScreen());
                case '/ruck_buddies':
                  return MaterialPageRoute(builder: (_) => const RuckBuddiesScreen());
                case '/achievements':
                  return MaterialPageRoute(
                    builder: (_) => const AchievementsHubScreen(),
                  );
                case '/post_session_upsell':
                  final args = settings.arguments;
                  if (args is RuckSession) {
                    return MaterialPageRoute(
                      builder: (_) => PostSessionUpsellScreen(session: args),
                    );
                  }
                  return MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('Error')),
                      body: const Center(child: Text('Missing session data for upsell.')),
                    ),
                  );
                case '/session_complete':
                  final args = settings.arguments as Map<String, dynamic>?;
                  if (args != null) {
                    return MaterialPageRoute(
                      builder: (context) => BlocProvider<HealthBloc>(
                        create: (context) => HealthBloc(
                          healthService: getIt<HealthService>(),
                          userId: context.read<AuthBloc>().state is Authenticated
                            ? (context.read<AuthBloc>().state as Authenticated).user.userId
                            : null,
                        ),
                        child: SessionCompleteScreen(
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
                          splits: args['splits'] as List<SessionSplit>?,
                        ),
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
                
                // Duels feature routes
                case '/duels':
                  return MaterialPageRoute(
                    builder: (_) => const DuelsListScreen(),
                  );
                case '/duels/create':
                  return MaterialPageRoute(
                    builder: (_) => const CreateDuelScreen(),
                  );
                case '/duel_detail':
                  final args = settings.arguments;
                  if (args is String) {
                    return MaterialPageRoute(
                      builder: (_) => DuelDetailScreen(duelId: args),
                    );
                  }
                  return MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('Error')),
                      body: const Center(child: Text('Missing duel ID')),
                    ),
                  );
                case '/duel_invitations':
                  return MaterialPageRoute(
                    builder: (_) => const DuelInvitationsScreen(),
                  );
                case '/duel_stats':
                  return MaterialPageRoute(
                    builder: (_) => const DuelStatsScreen(),
                  );
                case '/auth/callback':
                  // Parse the full URI from the route settings
                  final uri = Uri.parse('https://getrucky.com${settings.name}?${settings.arguments ?? ''}');
                  return MaterialPageRoute(
                    builder: (_) => AuthCallbackScreen(uri: uri),
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
          );
        },
      ),
    );
  }
}