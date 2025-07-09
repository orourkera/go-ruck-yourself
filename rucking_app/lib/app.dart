import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:app_links/app_links.dart';

import 'package:rucking_app/core/services/app_lifecycle_service.dart';
import 'package:rucking_app/core/services/service_locator.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
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
import 'package:rucking_app/core/models/terrain_segment.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_session.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/active_session_page.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/create_session_screen.dart';
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
import 'package:rucking_app/features/clubs/presentation/screens/clubs_screen.dart';
import 'package:rucking_app/features/clubs/presentation/screens/club_detail_screen.dart';
import 'package:rucking_app/features/clubs/presentation/screens/create_club_screen.dart';
import 'package:rucking_app/features/clubs/domain/models/club.dart';
import 'package:rucking_app/features/events/presentation/screens/event_detail_screen.dart';
import 'package:rucking_app/features/events/presentation/screens/create_event_screen.dart';
import 'package:rucking_app/features/profile/presentation/screens/profile_screen.dart';
import 'package:rucking_app/features/profile/presentation/screens/notification_settings_screen.dart';

/// Main application widget
class RuckingApp extends StatefulWidget {
  const RuckingApp({Key? key}) : super(key: key);

  @override
  State<RuckingApp> createState() => _RuckingAppState();
}

class _RuckingAppState extends State<RuckingApp> with WidgetsBindingObserver {
  late AppLifecycleService _lifecycleService;
  late AppLinks _appLinks;
  // Create a unique key with explicit identifier
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>(debugLabel: 'main_navigator');

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
        final typeMatch = RegExp(r'(?<!token_)type=([^&]+)').firstMatch(paramString); // Exclude token_type
        final errorMatch = RegExp(r'error=([^&]+)').firstMatch(paramString);
        final errorDescMatch = RegExp(r'error_description=([^&]+)').firstMatch(paramString);
        final errorCodeMatch = RegExp(r'error_code=([^&]+)').firstMatch(paramString);
        
        if (accessTokenMatch != null) accessToken = Uri.decodeComponent(accessTokenMatch.group(1)!);
        if (refreshTokenMatch != null) refreshToken = Uri.decodeComponent(refreshTokenMatch.group(1)!);
        if (typeMatch != null) type = Uri.decodeComponent(typeMatch.group(1)!);
        if (errorMatch != null) error = Uri.decodeComponent(errorMatch.group(1)!);
        if (errorDescMatch != null) errorDescription = Uri.decodeComponent(errorDescMatch.group(1)!);
        if (errorCodeMatch != null) errorCode = Uri.decodeComponent(errorCodeMatch.group(1)!);
        
        // Keep the original com.getrucky.app scheme since that's what Supabase is configured for
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
    
    // Handle various malformed URL patterns for both Android and iOS schemes
    if (uriString.contains('com.ruck.app://auth/callbackcom.ruck.app://auth/callback') ||
        uriString.contains('/callbackcom.ruck.app://auth/callback') ||
        uriString.contains('callbackcom.ruck.app://auth/callback') ||
        uriString.contains('com.goruckyourself.app://auth/callbackcom.goruckyourself.app://auth/callback') ||
        uriString.contains('/callbackcom.goruckyourself.app://auth/callback') ||
        uriString.contains('callbackcom.goruckyourself.app://auth/callback')) {
      
      // Fix duplicated URL by finding the last valid occurrence
      String targetScheme = '';
      if (uriString.contains('com.ruck.app')) {
        targetScheme = 'com.ruck.app://auth/callback';
      } else {
        targetScheme = 'com.goruckyourself.app://auth/callback';
      }
      final lastIndex = uriString.lastIndexOf(targetScheme);
      
      if (lastIndex >= 0) {
        // Extract from the last valid occurrence
        uriString = uriString.substring(lastIndex);
        uri = Uri.parse(uriString);
        print('🔧 Fixed malformed URL: $uri');
      }
    }
    
    // Check if this is an auth callback (custom scheme OR universal link)
    bool isAuthCallbackOld = false;
    
    // Handle both URI parsing formats:
    // Legacy: com.getrucky.app://auth/callback (path == '/auth/callback')
    // Current: com.getrucky.app://auth/callback (host == 'auth', path == '/callback')
    if ((uri.scheme == 'com.ruck.app' || uri.scheme == 'com.goruckyourself.app' || uri.scheme == 'com.getrucky.app') && 
        (uri.path == '/auth/callback' || (uri.host == 'auth' && uri.path == '/callback'))) {
      isAuthCallbackOld = true;
      print('✅ Custom scheme auth callback detected for ${uri.scheme}');
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
      return; // Exit early after handling auth callback
    }
    
    // Check if this is an event deeplink
    bool isEventDeeplink = false;
    String? eventId;
    
    // Handle event deeplinks: https://getrucky.com/events/123 or com.ruck.app://event/123 or com.goruckyourself.app://event/123
    if ((uri.scheme == 'https' && uri.host == 'getrucky.com' && uri.pathSegments.length >= 2 && uri.pathSegments[0] == 'events') ||
        ((uri.scheme == 'com.ruck.app' || uri.scheme == 'com.goruckyourself.app') && uri.pathSegments.length >= 2 && uri.pathSegments[0] == 'event')) {
      isEventDeeplink = true;
      eventId = uri.pathSegments[1];
    }
    
    if (isEventDeeplink && eventId != null) {
      print('🎯 Processing event deeplink for event ID: $eventId');
      // Navigate to event detail screen
      _navigatorKey.currentState?.pushNamed(
        '/event_detail',
        arguments: eventId,
      );
      return;
    }
    
    // Check if this is a club deeplink
    bool isClubDeeplink = false;
    String? clubId;
    
    // Handle club deeplinks: https://getrucky.com/clubs/123 or com.ruck.app://club/123 or com.goruckyourself.app://club/123
    if ((uri.scheme == 'https' && uri.host == 'getrucky.com' && uri.pathSegments.length >= 2 && uri.pathSegments[0] == 'clubs') ||
        ((uri.scheme == 'com.ruck.app' || uri.scheme == 'com.goruckyourself.app') && uri.pathSegments.length >= 2 && uri.pathSegments[0] == 'club')) {
      isClubDeeplink = true;
      clubId = uri.pathSegments[1];
    }
    
    if (isClubDeeplink && clubId != null) {
      print('🔗 Processing club deeplink for club ID: $clubId');
      // Navigate to club detail screen
      _navigatorKey.currentState?.pushNamed(
        '/club_detail',
        arguments: clubId,
      );
      return;
    }
    
    // If we get here, it's an unknown deeplink format
    print('❌ Unknown deeplink format:');
    print('  URI: $uri');
    print('  Scheme: ${uri.scheme}');
    print('  Host: ${uri.host}');
    print('  Path: ${uri.path}');
    print('  Path segments: ${uri.pathSegments}');
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
  void didHaveMemoryPressure() {
    super.didHaveMemoryPressure();
    _handleMemoryPressure();
  }
  
  /// Handle memory pressure events (Flutter equivalent of Android's onTrimMemory)
  void _handleMemoryPressure() {
    try {
      print('🚨 System memory pressure detected - triggering emergency cleanup');
      
      // Get the active session bloc if it exists
      final activeSessionBloc = getIt.isRegistered<ActiveSessionBloc>() 
          ? getIt<ActiveSessionBloc>() 
          : null;
      
      if (activeSessionBloc != null) {
        // Trigger emergency upload to preserve data
        activeSessionBloc.add(const MemoryPressureDetected());
        
        print('✅ Memory pressure event sent to ActiveSessionBloc');
      } else {
        print('ℹ️ No active session - memory pressure handled by system');
      }
      
      // Log memory pressure event for monitoring
      AppLogger.critical('System memory pressure detected', exception: {
        'platform': Platform.isAndroid ? 'android' : 'ios',
        'has_active_session': activeSessionBloc != null,
        'timestamp': DateTime.now().toIso8601String(),
      }.toString());
      
    } catch (e) {
      print('❌ Error handling memory pressure: $e');
      AppLogger.error('Memory pressure handling failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>(
          create: (context) {
            final bloc = getIt<AuthBloc>();
            // Set bloc reference in lifecycle service
            _lifecycleService.setBlocReferences(authBloc: bloc);
            return bloc;
          },
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
              ..startPolling(interval: const Duration(seconds: 30)); // More frequent polling
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
          
          return BlocListener<AuthBloc, AuthState>(
            listener: (context, state) {
              debugPrint('🔄 AuthBloc state changed: ${state.runtimeType}');
              if (state is Unauthenticated) {
                // Use WidgetsBinding.instance.addPostFrameCallback to avoid conflicts during rebuild
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final navigator = _navigatorKey.currentState;
                  if (navigator != null && navigator.mounted) {
                    // Clear any existing routes completely to prevent widget conflicts
                    navigator.pushNamedAndRemoveUntil('/login', (route) => false);
                  }
                });
              }
            },
            child: AnimatedBuilder(
              animation: Listenable.merge([]),
              builder: (context, child) {
                return MaterialApp(
                  title: 'GRY',
                  debugShowCheckedModeBanner: false,
                  theme: DynamicTheme.getThemeData(user, false),
                  darkTheme: DynamicTheme.getThemeData(user, true),
                  themeMode: ThemeMode.system,
                  home: const SplashScreen(),
                  navigatorKey: _navigatorKey,
                  // Add builder to handle theme transitions more gracefully
                  builder: (context, child) {
                    return MediaQuery(
                      data: MediaQuery.of(context).copyWith(textScaleFactor: 1.0),
                      child: child ?? const SizedBox.shrink(),
                    );
                  },
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
                        String? accessToken;
                        String? refreshToken;
                        
                        if (args is Map<String, dynamic>) {
                          // New format with both tokens
                          accessToken = args['access_token'] as String?;
                          refreshToken = args['refresh_token'] as String?;
                          token = accessToken; // For backward compatibility
                        } else if (args is String) {
                          // Legacy format with just token
                          token = args;
                          accessToken = args;
                        }
                        
                        return MaterialPageRoute(
                          builder: (_) => PasswordResetScreen(
                            token: token,
                            accessToken: accessToken,
                            refreshToken: refreshToken,
                          ),
                        );
                      case '/paywall':
                        return MaterialPageRoute(builder: (_) => const PaywallScreen());
                      case '/ruck_buddies':
                        return MaterialPageRoute(builder: (_) => const RuckBuddiesScreen());
                      case '/achievements':
                        return MaterialPageRoute(
                          builder: (_) => const AchievementsHubScreen(),
                        );
                      case '/profile':
                        return MaterialPageRoute(
                          builder: (_) => const ProfileScreen(),
                        );
                      case '/notification_settings':
                        return MaterialPageRoute(
                          builder: (_) => const NotificationSettingsScreen(),
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
                                terrainSegments: args['terrainSegments'] as List<TerrainSegment>?,
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
                      case '/callback':
                        // Debug logging to see what we're receiving
                        print('🔍 /callback route - settings.name: ${settings.name}');
                        print('🔍 /callback route - settings.arguments: ${settings.arguments}');
                        
                        String fullUrl = settings.name ?? '/callback';
                        if (settings.arguments != null) {
                          fullUrl += '?${settings.arguments}';
                        }
                        
                        print('🔍 /callback route - fullUrl: $fullUrl');
                        
                        // Handle Supabase redirects that come to /callback instead of /auth/callback
                        // Parse the URL properly, including fragment parameters
                        Uri uri;
                        try {
                          // If this is a fragment-based URL, we need to parse it manually
                          if (fullUrl.contains('#')) {
                            final parts = fullUrl.split('#');
                            if (parts.length > 1) {
                              // Convert fragment to query parameters
                              uri = Uri(
                                scheme: 'https',
                                host: 'getrucky.com',
                                path: '/auth/callback',
                                query: parts[1], // Use fragment as query
                              );
                            } else {
                              uri = Uri.parse('https://getrucky.com$fullUrl');
                            }
                          } else {
                            uri = Uri.parse('https://getrucky.com$fullUrl');
                          }
                        } catch (e) {
                          // Fallback if parsing fails
                          uri = Uri.parse('https://getrucky.com/auth/callback');
                        }
                        
                        return MaterialPageRoute(
                          builder: (_) => AuthCallbackScreen(uri: uri),
                        );
                      case '/clubs':
                        return MaterialPageRoute(builder: (_) => const ClubsScreen());
                      case '/club_detail':
                        final clubId = settings.arguments as String?;
                        if (clubId != null) {
                          return MaterialPageRoute(
                            builder: (_) => ClubDetailScreen(clubId: clubId),
                          );
                        }
                        return MaterialPageRoute(
                          builder: (_) => Scaffold(
                            appBar: AppBar(title: const Text('Error')),
                            body: const Center(child: Text('Missing club ID')),
                          ),
                        );
                      case '/create_club':
                        return MaterialPageRoute(builder: (_) => const CreateClubScreen());
                      case '/edit_club':
                        final clubDetails = settings.arguments as ClubDetails?;
                        if (clubDetails != null) {
                          return MaterialPageRoute(
                            builder: (_) => CreateClubScreen(clubToEdit: clubDetails),
                          );
                        }
                        return MaterialPageRoute(
                          builder: (_) => Scaffold(
                            appBar: AppBar(title: const Text('Error')),
                            body: const Center(child: Text('Missing club details')),
                          ),
                        );
                      
                      // Ruck Session routes
                      case '/create_session':
                        final args = settings.arguments as Map<String, dynamic>?;
                        String? eventId;
                        String? eventTitle;
                        
                        if (args != null) {
                          eventId = args['event_id'] as String?;
                          eventTitle = args['event_title'] as String?;
                        }
                        
                        return MaterialPageRoute(
                          builder: (_) => CreateSessionScreen(
                            eventId: eventId,
                            eventTitle: eventTitle,
                          ),
                        );
                      
                      // Events feature routes
                      case '/event_detail':
                        final eventId = settings.arguments as String?;
                        if (eventId != null) {
                          return MaterialPageRoute(
                            builder: (_) => EventDetailScreen(eventId: eventId),
                          );
                        }
                        return MaterialPageRoute(
                          builder: (_) => Scaffold(
                            appBar: AppBar(title: const Text('Error')),
                            body: const Center(child: Text('Missing event ID')),
                          ),
                        );
                      case '/create_event':
                        return MaterialPageRoute(
                          builder: (_) => const CreateEventScreen(),
                        );
                      case '/edit_event':
                        final eventId = settings.arguments as String?;
                        if (eventId != null) {
                          return MaterialPageRoute(
                            builder: (_) => CreateEventScreen(eventId: eventId),
                          );
                        }
                        return MaterialPageRoute(
                          builder: (_) => Scaffold(
                            appBar: AppBar(title: const Text('Error')),
                            body: const Center(child: Text('Missing event ID')),
                          ),
                        );
                      default:
                        return MaterialPageRoute(
                          builder: (_) => Scaffold(
                            appBar: AppBar(title: Text('Error')),
                            body: Center(child: Text('Route not found: ${settings.name}')),
                          ),
                        );
                    }
                  },
                ); 
              },          // ← closes AnimatedBuilder's builder function
            ),           // ← closes AnimatedBuilder widget
          );          // ← closes BlocListener
        },          // ← closes BlocBuilder's builder function
      ),             // ← closes BlocBuilder widget
    );             // ← closes MultiBlocProvider
  }
}