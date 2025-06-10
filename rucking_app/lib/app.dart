import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:app_links/app_links.dart';

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
  late AppLinks _appLinks;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    
    // Initialize the lifecycle service
    _lifecycleService = getIt<AppLifecycleService>();
    _lifecycleService.initialize();
    WidgetsBinding.instance?.addObserver(this);
    
    // Initialize deep links
    _appLinks = AppLinks();
    _initDeepLinks();
  }

  void _initDeepLinks() {
    // Listen for incoming deep links when app is already running
    _appLinks.uriLinkStream.listen((Uri uri) {
      _handleDeepLink(uri);
    }, onError: (err) {
      print('Deep link error: $err');
    });
    
    // Handle initial URL when app is launched cold from a link
    _appLinks.getInitialLink().then((Uri? uri) {
      if (uri != null) {
        print('🚀 App launched with initial URL: $uri');
        _handleDeepLink(uri);
      }
    }).catchError((err) {
      print('Initial link error: $err');
    });
  }

  void _handleDeepLink(Uri uri) {
    print('Received deep link: $uri');
    print('Deep link scheme: ${uri.scheme}');
    print('Deep link host: ${uri.host}');
    print('Deep link path: ${uri.path}');
    print('Deep link query: ${uri.query}');
    
    // Clean up potentially duplicated URL
    String uriString = uri.toString();
    print('🔍 Original URL: $uriString');
    
    // Handle extremely malformed URLs by extracting essential parts
    if (uriString.contains('com.getrucky.app') && 
        (uriString.contains('auth/callback') || uriString.contains('/callback'))) {
      try {
        // Extract the essential parameters from the malformed URL
        String? accessToken;
        String? refreshToken;
        String? type;
        String? error;
        String? errorDescription;
        String? errorCode;
        
        // Handle both query parameters (?) and hash fragments (#)
        String paramString = '';
        if (uriString.contains('?')) {
          paramString = uriString.split('?').last;
        } else if (uriString.contains('#')) {
          paramString = uriString.split('#').last;
        }
        
        // Use regex to extract parameters from the mess
        final accessTokenMatch = RegExp(r'access_token=([^&]+)').firstMatch(paramString);
        final refreshTokenMatch = RegExp(r'refresh_token=([^&]+)').firstMatch(paramString);
        final typeMatch = RegExp(r'type=([^&]+)').firstMatch(paramString);
        final errorMatch = RegExp(r'error=([^&]+)').firstMatch(paramString);
        final errorDescMatch = RegExp(r'error_description=([^&]+)').firstMatch(paramString);
        final errorCodeMatch = RegExp(r'error_code=([^&]+)').firstMatch(paramString);
        
        if (accessTokenMatch != null) accessToken = Uri.decodeComponent(accessTokenMatch.group(1)!);
        if (refreshTokenMatch != null) refreshToken = Uri.decodeComponent(refreshTokenMatch.group(1)!);
        if (typeMatch != null) type = Uri.decodeComponent(typeMatch.group(1)!);
        if (errorMatch != null) error = Uri.decodeComponent(errorMatch.group(1)!);
        if (errorDescMatch != null) errorDescription = Uri.decodeComponent(errorDescMatch.group(1)!);
        if (errorCodeMatch != null) errorCode = Uri.decodeComponent(errorCodeMatch.group(1)!);
        
        // Rebuild a clean URL
        String cleanUrl = 'com.getrucky.app://auth/callback';
        List<String> params = [];
        
        if (accessToken != null) params.add('access_token=$accessToken');
        if (refreshToken != null) params.add('refresh_token=$refreshToken');
        if (type != null) params.add('type=$type');
        if (error != null) params.add('error=$error');
        if (errorDescription != null) params.add('error_description=$errorDescription');
        if (errorCode != null) params.add('error_code=$errorCode');
        
        if (params.isNotEmpty) {
          cleanUrl += '?' + params.join('&');
        }
        
        uriString = cleanUrl;
        uri = Uri.parse(uriString);
        print('🔧 Rebuilt clean URL: $uri');
        
      } catch (e) {
        print('❌ Failed to clean malformed URL: $e');
        return; // Skip processing this malformed URL
      }
    }
    
    // Handle various malformed URL patterns
    if (uriString.contains('com.getrucky.app://auth/callbackcom.getrucky.app://auth/callback') ||
        uriString.contains('/callbackcom.getrucky.app://auth/callback') ||
        uriString.contains('callbackcom.getrucky.app://auth/callback')) {
      
      // Fix duplicated URL by finding the last valid occurrence
      const targetScheme = 'com.getrucky.app://auth/callback';
      final lastIndex = uriString.lastIndexOf(targetScheme);
      
      if (lastIndex >= 0) {
        // Extract from the last valid occurrence
        uriString = uriString.substring(lastIndex);
        uri = Uri.parse(uriString);
        print('🔧 Fixed malformed URL: $uri');
      }
    }
    
    // Determine if this is an auth callback (login, signup, password recovery)
    bool isAuthCallback = false;
    if ((uri.scheme == 'com.getrucky.app' &&
            (uri.path == '/auth/callback' || uri.path == '/callback')) ||
        (uri.scheme == 'https' &&
            uri.host == 'getrucky.com' &&
            uri.path == '/auth/callback')) {
      isAuthCallback = true;
    }

    // Supabase may send parameters in the URI fragment (after '#').
    // Convert fragment to query parameters so they can be read by Uri.queryParameters.
    if (isAuthCallback && uri.fragment.isNotEmpty && uri.query.isEmpty) {
      try {
        final rebuilt = Uri(
          scheme: uri.scheme,
          host: uri.host,
          path: uri.path,
          query: uri.fragment, // treat fragment as query
        );
        uri = rebuilt;
        print('🔄 Converted fragment to query: $uri');
      } catch (e) {
        print('❌ Failed to convert fragment to query: $e');
      }
    }

    if (isAuthCallback) {
      print('🔗 Processing auth callback with URI: $uri');
      _navigatorKey.currentState?.pushNamed('/auth_callback', arguments: uri);
      return;
    }
    
    // Check if this is an auth callback (custom scheme OR universal link)
    bool isAuthCallbackOld = false;
    
    if (uri.scheme == 'com.getrucky.app' && uri.path == '/auth/callback') {
      isAuthCallbackOld = true;
      print('✅ Custom scheme auth callback detected');
    } else if (uri.scheme == 'https' && 
               uri.host == 'getrucky.com' && 
               uri.path == '/auth/callback') {
      isAuthCallbackOld = true;
      print('✅ Universal Link auth callback detected');
    }
    
    if (isAuthCallbackOld) {
      print('🔗 Processing auth callback with URI: $uri');
      // Navigate to auth callback screen
      _navigatorKey.currentState?.pushNamed(
        '/auth_callback',
        arguments: uri,
      );
    } else {
      print('❌ Not an auth callback:');
      print('  Expected scheme: com.getrucky.app, got: ${uri.scheme}');
      print('  Expected path: /auth/callback, got: ${uri.path}');
    }
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
          
          return MaterialApp(
            title: 'GRY',
            debugShowCheckedModeBanner: false,
            theme: DynamicTheme.getThemeData(user, false),
            darkTheme: DynamicTheme.getThemeData(user, true),
            themeMode: ThemeMode.system,
            home: const SplashScreen(),
            navigatorKey: _navigatorKey,
            onGenerateRoute: (settings) {
              switch (settings.name) {
                case '/home':
                  return MaterialPageRoute(builder: (_) => const HomeScreen());
                case '/login':
                  return MaterialPageRoute(builder: (_) => LoginScreen());
                case '/auth_callback':
                  final uri = settings.arguments as Uri?;
                  if (uri != null) {
                    return MaterialPageRoute(
                      builder: (_) => AuthCallbackScreen(uri: uri),
                    );
                  }
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