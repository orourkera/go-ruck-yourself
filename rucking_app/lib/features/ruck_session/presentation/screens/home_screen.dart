import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/achievements/presentation/bloc/achievement_bloc.dart';
import 'package:rucking_app/features/achievements/presentation/widgets/achievement_summary.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/auth/presentation/screens/login_screen.dart';
import 'package:rucking_app/features/premium/presentation/widgets/premium_tab_interceptor.dart';
import 'package:rucking_app/features/premium/presentation/bloc/premium_bloc.dart';
import 'package:rucking_app/features/premium/presentation/bloc/premium_event.dart';
import 'package:rucking_app/shared/widgets/styled_snackbar.dart';
import 'package:rucking_app/shared/widgets/charts/heart_rate_graph.dart';
import 'package:rucking_app/features/ruck_buddies/presentation/pages/ruck_buddies_screen.dart';
import 'package:rucking_app/features/notifications/presentation/widgets/notification_bell.dart';
import 'package:rucking_app/features/notifications/presentation/pages/notifications_screen.dart';
import 'package:rucking_app/shared/widgets/skeleton/skeleton_widgets.dart';
import 'package:rucking_app/core/services/image_cache_manager.dart';
import 'package:rucking_app/core/error_messages.dart' as error_msgs;
import 'package:rucking_app/features/profile/presentation/screens/profile_screen.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/create_session_screen.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/session_detail_screen.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/session_history_screen.dart';
import 'package:rucking_app/features/notifications/presentation/bloc/notification_bloc.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/custom_button.dart';
import 'package:rucking_app/shared/widgets/user_avatar.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:rucking_app/core/utils/measurement_utils.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_session.dart';
import 'package:rucking_app/core/services/session_cache_service.dart';
import 'package:rucking_app/core/services/app_startup_service.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/features/statistics/presentation/screens/statistics_screen.dart';
import 'package:rucking_app/features/events/presentation/screens/events_screen.dart';
import 'package:rucking_app/features/duels/presentation/screens/duels_list_screen.dart';

LatLng _getRouteCenter(List<LatLng> points) {
  if (points.isEmpty) return LatLng(40.421, -3.678); // Default center (Madrid)
  double avgLat = points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length;
  double avgLng = points.map((p) => p.longitude).reduce((a, b) => a + b) / points.length;
  return LatLng(avgLat, avgLng);
}

// Improved zoom calculation to fit all points with padding
double _getFitZoom(List<LatLng> points) {
  if (points.isEmpty) return 16.0;
  if (points.length == 1) return 17.0;

  double minLat = points.map((p) => p.latitude).reduce((a, b) => a < b ? a : b);
  double maxLat = points.map((p) => p.latitude).reduce((a, b) => a > b ? a : b);
  double minLng = points.map((p) => p.longitude).reduce((a, b) => a < b ? a : b);
  double maxLng = points.map((p) => p.longitude).reduce((a, b) => a > b ? a : b);

  // Add some padding (20% on each side)
  double latPadding = (maxLat - minLat) * 0.2;
  double lngPadding = (maxLng - minLng) * 0.2;
  
  minLat -= latPadding;
  maxLat += latPadding;
  minLng -= lngPadding;
  maxLng += lngPadding;

  // Calculate zoom levels based on the bounding box
  // These calculations are based on a map container that's approximately 220px tall
  double latDiff = maxLat - minLat;
  double lngDiff = maxLng - minLng;

  // Approximate zoom calculation based on degrees of lat/lng difference
  // These values are tuned for a small map preview
  double zoom;
  if (latDiff < 0.0005 && lngDiff < 0.0005) {
    zoom = 17.0; // Very close zoom for tiny routes
  } else if (latDiff < 0.001 && lngDiff < 0.001) {
    zoom = 16.5;
  } else if (latDiff < 0.005 && lngDiff < 0.005) {
    zoom = 15.5;
  } else if (latDiff < 0.01 && lngDiff < 0.01) {
    zoom = 14.5;
  } else if (latDiff < 0.05 && lngDiff < 0.05) {
    zoom = 13.0;
  } else if (latDiff < 0.1 && lngDiff < 0.1) {
    zoom = 12.0;
  } else if (latDiff < 0.5 && lngDiff < 0.5) {
    zoom = 10.5;
  } else if (latDiff < 1.0 && lngDiff < 1.0) {
    zoom = 9.5;
  } else {
    zoom = 8.0;
  }

  return zoom;
}

/// Main home screen that serves as the central hub of the app
class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  
  @override
  void initState() {
    super.initState();
    
    // PAYWALL DISABLED: Commenting out premium status initialization
    // Initialize premium status when home screen loads
    // context.read<PremiumBloc>().add(InitializePremiumStatus());
    
    // Add lifecycle observer to handle app state changes
    WidgetsBinding.instance.addObserver(this);
  }
  
  @override
  void dispose() {
    // Remove lifecycle observer when disposing
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // PAYWALL DISABLED: Commenting out premium status refresh
    // Refresh premium status when app resumes from background
    // This helps catch subscription status changes after purchases
    // if (state == AppLifecycleState.resumed) {
    //   context.read<PremiumBloc>().add(CheckPremiumStatus());
    // }
  }
  
  // List of screens for the bottom navigation bar
  final List<Widget> _screens = [
    const _HomeTab(),
    const SessionHistoryScreen(),
    const PremiumTabInterceptor(
      tabIndex: 2,
      featureName: 'Ruck Buddies',
      child: RuckBuddiesScreen(),
    ),
    const DuelsListScreen(),
    const EventsScreen(),
  ];
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          debugPrint('🐞 Bottom navigation tapped: $index');
          setState(() {
            _selectedIndex = index;
          });
          // Add a post-render check to verify the screen changed
          WidgetsBinding.instance.addPostFrameCallback((_) {
            debugPrint('🐞 Selected index after render: $_selectedIndex');
          });
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Theme.of(context).primaryColor,
        unselectedItemColor: AppColors.grey,
        items: [
          BottomNavigationBarItem(
            icon: Image.asset(
              'assets/images/home.png',
              width: 48,
              height: 48,
            ),
            activeIcon: Image.asset(
              'assets/images/home_active.png',
              width: 48,
              height: 48,
            ),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Image.asset(
              'assets/images/history.png',
              width: 48,
              height: 48,
            ),
            activeIcon: Image.asset(
              'assets/images/history_active.png',
              width: 48,
              height: 48,
            ),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Image.asset(
              'assets/images/ruckbuddies.png',
              width: 48,
              height: 48,
            ),
            activeIcon: Image.asset(
              'assets/images/ruckbuddies_active.png',
              width: 48,
              height: 48,
            ),
            label: 'Buddies',
          ),
          BottomNavigationBarItem(
            icon: Image.asset(
              'assets/images/duels icon.png',
              width: 48,
              height: 48,
            ),
            activeIcon: Image.asset(
              'assets/images/duels active.png',
              width: 48,
              height: 48,
            ),
            label: 'Duels',
          ),
          BottomNavigationBarItem(
            icon: Image.asset(
              'assets/images/events.png',
              width: 48,
              height: 48,
            ),
            activeIcon: Image.asset(
              'assets/images/events active.png',
              width: 48,
              height: 48,
            ),
            label: 'Events',
          ),
        ],
      ),
    );
  }

  Widget _buildProfileIcon(bool isActive) {
    // Get user gender from AuthBloc if available
    String? userGender;
    try {
      final authBloc = context.read<AuthBloc>();
      if (authBloc.state is Authenticated) {
        userGender = (authBloc.state as Authenticated).user.gender;
      }
    } catch (e) {
      // If auth bloc is not available, continue with default icon
      debugPrint('Could not get user gender for profile icon: $e');
    }
    
    // Determine which icon to use based on gender and active state
    String iconPath;
    if (userGender == 'female') {
      // Female icon based on active state
      iconPath = isActive 
          ? 'assets/images/lady rucker profile active.png'
          : 'assets/images/lady rucker profile.png';
    } else {
      // Default/male icon based on active state
      iconPath = isActive 
          ? 'assets/images/profile_active.png'
          : 'assets/images/profile.png';
    }
    
    return Image.asset(
      iconPath,
      width: 48,
      height: 48,
    );
  }
}

/// Home tab content
class _HomeTab extends StatefulWidget {
  const _HomeTab({Key? key}) : super(key: key);

  @override
  _HomeTabState createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> with RouteAware {
  List<dynamic> _recentSessions = [];
  Map<String, dynamic> _monthlySummaryStats = {};
  bool _isLoading = true;
  bool _isRefreshing = false;
  ApiClient? _apiClient;
  final SessionCacheService _cacheService = SessionCacheService();
  final RouteObserver<ModalRoute> _routeObserver = RouteObserver<ModalRoute>();
  
  @override
  void initState() {
    super.initState();
    _apiClient = GetIt.instance<ApiClient>();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
      _checkForPhotoUploadError();
      _checkForSessionRecovery();
    });
  }
  
  /// Checks route arguments for photo upload error flags and shows appropriate message
  void _checkForPhotoUploadError() {
    if (!mounted) return;
    
    try {
      final route = ModalRoute.of(context);
      if (route != null && route.settings.arguments != null) {
        final args = route.settings.arguments;
        
        // Check if we have photo upload error arguments
        if (args is Map && args.containsKey('showPhotoUploadError') && args['showPhotoUploadError'] == true) {
          // Use StyledSnackBar with our custom error message
          StyledSnackBar.showError(
            context: context, 
            message: error_msgs.sessionPhotoUploadError,
            duration: const Duration(seconds: 4),
            animationStyle: SnackBarAnimationStyle.slideUpBounce,
          );
        }
      }
    } catch (e) {
      debugPrint('Error checking for photo upload error: $e');
    }
  }
  
  /// Checks for session recovery and navigates to active session if needed
  Future<void> _checkForSessionRecovery() async {
    if (!mounted) return;
    
    try {
      final startupService = GetIt.instance<AppStartupService>();
      await startupService.checkAndRecoverSession(context);
    } catch (e) {
      debugPrint('Error checking for session recovery: $e');
    }
  }
  
  /// Loads data from cache first, then refreshes from network
  Future<void> _loadData() async {
    if (!mounted) return;
    
    // Safety check: we shouldn't fetch data before we've fully initialized
    if (_apiClient == null) {
      _apiClient = GetIt.instance<ApiClient>();
    }
    
    setState(() {
      _isLoading = true;
    });

    // Try to load from cache first
    final cachedSessions = await _cacheService.getCachedSessions();
    final cachedStats = await _cacheService.getCachedStats();
    
    if (cachedSessions != null && cachedStats != null) {
      // We have cache data, show it immediately
      setState(() {
        _recentSessions = cachedSessions;
        _monthlySummaryStats = cachedStats;
        _isLoading = false;
        _isRefreshing = true; // Mark that we're refreshing in background
      });
    }
    
    // Fetch fresh data from the network
    await _fetchFromNetwork();
  }

  /// Fetches fresh data from network and updates cache
  Future<void> _fetchFromNetwork() async {
    if (!mounted) return;
    
    try {
      // Combine both API calls into parallel execution for better performance
      final futures = await Future.wait([
        _apiClient!.get('/rucks?limit=20'),
        _apiClient!.get('/stats/monthly'),
      ]);
      
      final sessionsResponse = futures[0];
      final statsResponse = futures[1];
      
      // Process sessions
      List<dynamic> processedSessions = _processSessionResponse(sessionsResponse);
      List<dynamic> completedSessions = processedSessions
          .where((session) => session is Map && session['status'] == 'completed')
          .toList();

      // Process stats
      Map<String, dynamic> processedStats = {};
      if (statsResponse is Map && statsResponse.containsKey('data') && statsResponse['data'] is Map) {
          processedStats = statsResponse['data'] as Map<String, dynamic>;
      }

      // Cache both results in parallel
      await Future.wait([
        _cacheService.cacheRecentSessions(completedSessions),
        _cacheService.cacheMonthlyStats(processedStats),
      ]);

      if (!mounted) return;
      
      setState(() {
        _recentSessions = completedSessions;
        _monthlySummaryStats = processedStats;
        _isLoading = false;
        _isRefreshing = false;
      });

      // Preload images for better UX
      await _preloadSessionImages(completedSessions.take(5).toList());
    } catch (e, stack) {
      debugPrint('Error fetching data: $e');
      debugPrint('Stack trace: $stack');
      
      if (!mounted) return;
      
      final wasManualRefresh = _isRefreshing;
      
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
        
        if (wasManualRefresh) {
          _recentSessions = [];
        }
      });
    }
  }

  /// Legacy method for backward compatibility
  Future<void> _fetchData() async {
    return _loadData();
  }

  // Helper function to process session response
  List<dynamic> _processSessionResponse(dynamic response) {
    List<dynamic> processedSessions = [];
    if (response == null) {
      
    } else if (response is List) {
      processedSessions = response;
    } else if (response is Map && response.containsKey('data') && response['data'] is List) {
      processedSessions = response['data'] as List;
    } else if (response is Map && response.containsKey('sessions') && response['sessions'] is List) {
      processedSessions = response['sessions'] as List;
    } else if (response is Map && response.containsKey('items') && response['items'] is List) {
      processedSessions = response['items'] as List;
    } else if (response is Map && response.containsKey('results') && response['results'] is List) {
      processedSessions = response['results'] as List;
    } else if (response is Map) { 
        for (var key in response.keys) {
          if (response[key] is List) {
            processedSessions = response[key] as List;
            break;
          }
        }
     }
     
    
    return processedSessions;
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // Refresh data when returning to this screen (e.g., after deleting a session)
    if (!_isLoading && !_isRefreshing) {
      _fetchFromNetwork();
    }
    
    // Only attempt to subscribe to route if the context is still valid
    if (mounted) {
      try {
        final route = ModalRoute.of(context);
        if (route is PageRoute) {
          final routeObserver = Navigator.of(context).widget.observers.whereType<RouteObserver<PageRoute>>().firstOrNull;
          routeObserver?.subscribe(this, route);
        }
      } catch (e) {
        
      }
    }
  }

  @override
  void dispose() {
    // Only attempt to unsubscribe if mounted
    if (mounted) {
      try {
        final route = ModalRoute.of(context);
        if (route is PageRoute) {
          final routeObserver = Navigator.of(context).widget.observers.whereType<RouteObserver<PageRoute>>().firstOrNull;
          routeObserver?.unsubscribe(this);
        }
      } catch (e) {
        
      }
    }
    super.dispose();
  }

  @override
  void didPopNext() {
    super.didPopNext();
    
    // Refresh data when user returns to this screen
    _fetchFromNetwork();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is Unauthenticated) {
          Navigator.of(context).pushNamedAndRemoveUntil(
              '/login',
              (route) => false,
            );
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: () async {
              await _fetchFromNetwork();
            },
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with user greeting
                  BlocBuilder<AuthBloc, AuthState>(
                    builder: (context, state) {
                      String userName = 'Rucker'; // Default
                      if (state is Authenticated) {
                        // Use the username from the user model if available
                        if (state.user.username.isNotEmpty) {
                          userName = state.user.username; 
                        } else {
                           userName = 'Rucker'; // Fallback if username is somehow empty
                        }
                      } else {
                         // Handle non-authenticated state if necessary
                      }
                      
                      // Check for gender-specific styling
                      final isLadyMode = state is Authenticated && state.user.gender == 'female';

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  // User avatar (only show if authenticated)
                                  if (state is Authenticated) ...[
                                    UserAvatar(
                                      avatarUrl: state.user.avatarUrl,
                                      username: userName,
                                      size: 40,
                                      onTap: () {
                                        // Navigate to profile page
                                        Navigator.pushNamed(context, '/profile');
                                      },
                                    ),
                                    const SizedBox(width: 12),
                                  ],
                                  // User name only (no welcome text)
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Welcome back,',
                                        style: AppTextStyles.bodySmall.copyWith(
                                          color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : AppColors.textDarkSecondary,
                                        ),
                                      ),
                                      Text(
                                        userName,
                                        style: AppTextStyles.displayLarge.copyWith(
                                          fontSize: 24,
                                          color: Theme.of(context).brightness == Brightness.dark ? Colors.white : AppColors.textDark,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              // Top bar action icons - more compact and right-aligned
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Notifications
                                  _buildHeaderAction(
                                    icon: Image.asset('assets/images/notifications.png', width: 27, height: 27),
                                    onTap: () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                                      );
                                      if (!mounted) return;
                                      context.read<NotificationBloc>().add(const NotificationsRequested());
                                    },
                                  ),
                                  const SizedBox(width: 6),
                                  // Clubs
                                  _buildHeaderAction(
                                    icon: Image.asset('assets/images/clubs.png', width: 30, height: 30),
                                    onTap: () {
                                      Navigator.pushNamed(context, '/clubs');
                                    },
                                  ),
                                  const SizedBox(width: 6),
                                  // Profile
                                  _buildHeaderAction(
                                    icon: _buildProfileHeaderIcon(),
                                    onTap: () {
                                      Navigator.pushNamed(context, '/profile');
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 32),
                  
                  // Quick stats section (USE _monthlySummaryStats)
                  BlocBuilder<AuthBloc, AuthState>(
                    builder: (context, state) {
                      // Determine if user is in lady mode
                      bool isLadyMode = false;
                      if (state is Authenticated && state.user.gender == 'female') {
                        isLadyMode = true;
                      }
                      
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isLadyMode ? AppColors.ladyPrimaryGradient : AppColors.primaryGradient,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: isLadyMode ? AppColors.ladyPrimary.withOpacity(0.3) : Theme.of(context).primaryColor.withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _monthlySummaryStats['date_range'] ?? 'This Month',
                              style: AppTextStyles.titleMedium.copyWith(
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Builder( // Use Builder to get context with AuthBloc state
                              builder: (innerContext) {
                                bool preferMetric = true;
                                final authState = innerContext.read<AuthBloc>().state;
                                if (authState is Authenticated) {
                                  preferMetric = authState.user.preferMetric;
                                }
                                
                                // Use data from _monthlySummaryStats
                                final rucks = _monthlySummaryStats['total_sessions']?.toString() ?? '0';
                                final distanceKm = (_monthlySummaryStats['total_distance_km'] ?? 0.0).toDouble();
                                final distance = MeasurementUtils.formatDistance(distanceKm, metric: preferMetric);
                                final calories = (_monthlySummaryStats['total_calories'] ?? 0).round().toString();
                                
                                return Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                                  children: [
                                    _buildStatItem('Rucks', rucks, Icons.directions_walk),
                                    _buildStatItem('Distance', distance, Icons.straighten),
                                    _buildStatItem('Calories', calories, Icons.local_fire_department),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 32),
                  
                  // Create session button - full width and orange
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.add),
                      label: Text(
                        'START NEW RUCK', 
                        style: AppTextStyles.labelLarge.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => CreateSessionScreen()),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.secondary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        minimumSize: const Size.fromHeight(56),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Achievements summary
                  const AchievementSummary(),
                  
                  const SizedBox(height: 24),
                  
                  // Recent sessions section
                  Text(
                    'Recent Sessions',
                    style: AppTextStyles.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  
                  // Show loading indicator or sessions list
                  _isLoading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 30),
                        child: Column(
                          children: [
                            SessionCardSkeleton(),
                            SessionCardSkeleton(),
                            SessionCardSkeleton(),
                          ],
                        ),
                      ),
                    )
                  : _recentSessions.isEmpty
                    ? // Placeholder for when there are no recent sessions
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 30),
                          child: Column(
                            children: [
                              Icon(
                                Icons.history_outlined,
                                size: 48,
                                color: AppColors.grey,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No recent sessions',
                                style: AppTextStyles.bodyLarge.copyWith(
                                  color: AppColors.grey,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Your completed sessions will appear here',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.greyDark,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _recentSessions.length,
                        itemBuilder: (context, index) {
                          final session = _recentSessions[index];
                          
                          // Ensure session is a Map
                          if (session is! Map<String, dynamic>) {
                            return const SizedBox.shrink(); // Skip non-map items
                          }
                          
                          // Get session date
                          final dateString = session['started_at'] as String? ?? '';
                          final date = DateTime.tryParse(dateString);
                          final formattedDate = date != null 
                              ? DateFormat('MMM d, yyyy').format(date)
                              : 'Unknown date';
                          
                          // Get session duration directly from session map
                          final durationSecs = session['duration_seconds'] as int? ?? 0;
                          final duration = Duration(seconds: durationSecs);
                          final hours = duration.inHours;
                          final minutes = duration.inMinutes % 60;
                          final durationText = hours > 0 
                              ? '${hours}h ${minutes}m' 
                              : '${minutes}m';
                          
                          // Get distance directly from session map based on user preference
                          final distanceKmRaw = session['distance_km'];
                          final double distanceKm = distanceKmRaw is int
                              ? distanceKmRaw.toDouble()
                              : (distanceKmRaw as double? ?? 0.0);
                          bool preferMetric = true;
                          final authState = context.read<AuthBloc>().state;
                          if (authState is Authenticated) {
                            preferMetric = authState.user.preferMetric;
                          }
                          
                          final distanceValue = MeasurementUtils.formatDistance(distanceKm, metric: preferMetric);
                          
                          // Get calories directly from session map
                          final calories = session['calories_burned']?.toString() ?? '0';
                          
                          // Pace display (use exact API field name from data model)
                          final paceRaw = session['average_pace'] ?? 0.0;
                          final pace = paceRaw is int ? paceRaw.toDouble() : paceRaw;
                          final paceDisplay = (pace != null && pace > 0)
                              ? MeasurementUtils.formatPace(pace, metric: preferMetric)
                              : '--';
                          
                          // Elevation display (use exact API field names from data model)
                          final elevationGainRaw = session['elevation_gain_m'] ?? 0.0;
                          double elevationGain = elevationGainRaw is int ? elevationGainRaw.toDouble() : elevationGainRaw;
                          final elevationLossRaw = session['elevation_loss_m'] ?? 0.0;
                          double elevationLoss = elevationLossRaw is int ? elevationLossRaw.toDouble() : elevationLossRaw;
                          String elevationDisplay = (elevationGain == 0.0 && elevationLoss == 0.0)
                            ? '--'
                            : MeasurementUtils.formatElevationCompact(elevationGain, elevationLoss, metric: preferMetric);
                          
                          // Map route points – handle multiple possible key names gracefully
                          double? _parseCoord(dynamic v) {
                            if (v == null) return null;
                            if (v is num) return v.toDouble();
                            if (v is String) return double.tryParse(v);
                            return null;
                          }

                          List<LatLng> routePoints = [];
                          final dynamic rawRoute =
                              session['route'] ?? session['location_points'] ?? session['locationPoints'];

                          if (rawRoute is List && rawRoute.isNotEmpty) {
                            for (final p in rawRoute) {
                              double? lat;
                              double? lng;

                              if (p is Map) {
                                lat = _parseCoord(p['latitude']);
                                lng = _parseCoord(p['longitude']);

                                lat ??= _parseCoord(p['lat']);
                                lng ??= _parseCoord(p['lng']) ?? _parseCoord(p['lon']);
                              } else if (p is List && p.length >= 2) {
                                lat = _parseCoord(p[0]);
                                lng = _parseCoord(p[1]);
                              }

                              if (lat != null && lng != null) {
                                routePoints.add(LatLng(lat, lng));
                              }
                            }
                          }

                          if (routePoints.isEmpty) {
                            // Use default points for visual testing only (should not happen in production)
                            routePoints = [
                              LatLng(40.421, -3.678),
                              LatLng(40.422, -3.678),
                              LatLng(40.423, -3.677),
                              LatLng(40.424, -3.676),
                            ];
                          }
                          if (routePoints.isEmpty) {
                            // Use default points for visual testing
                            routePoints = [
                              LatLng(40.421, -3.678),
                              LatLng(40.422, -3.678),
                              LatLng(40.423, -3.677),
                              LatLng(40.424, -3.676),
                            ];
                          }
                          return GestureDetector(
                            onTap: () {
                              try {
                                final sessionModel = RuckSession.fromJson(session);
                                // Navigate to detail screen and handle the result
                                Navigator.of(context).push<bool>(
                                  MaterialPageRoute(
                                    builder: (context) => SessionDetailScreen(session: sessionModel),
                                  ),
                                ).then((refreshNeeded) {
                                  // If returned with true (session deleted), refresh the data
                                  if (refreshNeeded == true) {
                                    _fetchFromNetwork();
                                  }
                                });
                              } catch (e) {
                                // Ignore errors
                              }
                            },
                            child: Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            elevation: 1,
                            color: Theme.of(context).cardColor, // Use theme card color (tan in dark mode)
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // MAP PREVIEW
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: SizedBox(
                                      height: 220, // Increased size to match ruck buddies
                                      width: double.infinity,
                                      child: FlutterMap(
                                        options: MapOptions(
                                          initialCenter: routePoints.isNotEmpty ? _getRouteCenter(routePoints) : LatLng(40.421, -3.678),
                                          initialZoom: routePoints.isNotEmpty ? _getFitZoom(routePoints) : 15.0,
                                          minZoom: 3.0,
                                          maxZoom: 18.0,
                                          interactionOptions: const InteractionOptions(
                                            flags: InteractiveFlag.none, // Disable interactions for preview
                                          ),
                                        ),
                                        children: [
                                          TileLayer(
                                            urlTemplate: "https://tiles.stadiamaps.com/tiles/stamen_terrain/{z}/{x}/{y}{r}.png?api_key=${dotenv.env['STADIA_MAPS_API_KEY']}",
                                            userAgentPackageName: 'com.getrucky.gfy',
                                            retinaMode: MediaQuery.of(context).devicePixelRatio > 1.0,
                                          ),
                                          PolylineLayer(
                                            polylines: [
                                              Polyline(
                                                points: routePoints,
                                                color: AppColors.secondary,
                                                strokeWidth: 4,
                                              ),
                                            ],
                                          ),
                                          
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        formattedDate,
                                        style: AppTextStyles.titleMedium.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(context).brightness == Brightness.dark ? Color(0xFF728C69) : AppColors.textDark,
                                        ),
                                      ),
                                      Text(
                                        durationText,
                                        style: AppTextStyles.bodyMedium.copyWith(
                                          color: Theme.of(context).brightness == Brightness.dark ? Color(0xFF728C69) : AppColors.textDarkSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  const Divider(height: 24),
                                  
                                  // Stats grid (2x2) - matches Ruck Buddies layout
                                  Row(
                                    children: [
                                      // Left column
                                      Expanded(
                                        child: Column(
                                          children: [
                                            _buildSessionStat(
                                              Icons.straighten,
                                              distanceValue,
                                              label: 'Distance',
                                            ),
                                            const SizedBox(height: 16),
                                            _buildSessionStat(
                                              Icons.local_fire_department,
                                              '$calories cal',
                                              label: 'Calories',
                                            ),
                                          ],
                                        ),
                                      ),
                                      
                                      const SizedBox(width: 24),
                                      
                                      // Right column
                                      Expanded(
                                        child: Column(
                                          children: [
                                            _buildSessionStat(
                                              Icons.timer,
                                              paceDisplay,
                                              label: 'Pace',
                                            ),
                                            const SizedBox(height: 16),
                                            _buildSessionStat(
                                              Icons.landscape,
                                              elevationDisplay,
                                              label: 'Elevation',
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                
                // View all button
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed: () {
                      // Find the parent HomeScreen widget and update its state
                      final _HomeScreenState homeState = context.findAncestorStateOfType<_HomeScreenState>()!;
                      homeState.setState(() {
                        homeState._selectedIndex = 1; // Switch to history tab
                      });
                    },
                    child: Text(
                      'View All Sessions',
                      style: AppTextStyles.labelLarge.copyWith(
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ), // Closes SafeArea
    ), // Closes Scaffold
  ); // Closes BlocListener
  } // Closes build method

  /// Builds a statistics item for the quick stats section
  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(
          icon,
          color: Colors.white,
          size: 20,
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: AppTextStyles.titleLarge.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            color: Colors.white.withOpacity(0.8),
          ),
        ),
      ],
    );
  }

  /// Builds a session stat item - updated to match ruck buddies style
  Widget _buildSessionStat(IconData icon, String value, {String? label}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 20,
          color: Theme.of(context).primaryColor,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (label != null)
                Text(
                  label,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              Text(
                value,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  /// Builds a small circular header action icon
  Widget _buildHeaderAction({required Widget icon, required VoidCallback onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(child: icon),
      ),
    );
  }

  /// Returns profile icon widget for header based on user gender (lady mode)
  Widget _buildProfileHeaderIcon() {
    String? gender;
    try {
      final authBloc = context.read<AuthBloc>();
      if (authBloc.state is Authenticated) {
        gender = (authBloc.state as Authenticated).user.gender;
      }
    } catch (_) {
      // If AuthBloc not available, fall back to default icon
    }

    final String iconPath = (gender == 'female')
        ? 'assets/images/lady rucker profile.png'
        : 'assets/images/profile.png';
    return Image.asset(iconPath, width: 30, height: 30);
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return '${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds';
  }

  /// Preload images from recent sessions for better perceived performance
  Future<void> _preloadSessionImages(List<dynamic> sessions) async {
    if (sessions.isEmpty) return;
    
    try {
      // Extract profile picture URLs from session data
      final profileUrls = <String>[];
      final photoUrls = <String>[];
      
      for (final sessionData in sessions) {
        if (sessionData is Map<String, dynamic>) {
          // Check for user profile picture
          final user = sessionData['user'];
          if (user is Map<String, dynamic>) {
            final profilePic = user['profile_picture'];
            if (profilePic is String && profilePic.isNotEmpty) {
              profileUrls.add(profilePic);
            }
          }
          
          // Check for session photos
          final photos = sessionData['photos'];
          if (photos is List && photos.isNotEmpty) {
            final firstPhoto = photos.first;
            if (firstPhoto is String && firstPhoto.isNotEmpty) {
              photoUrls.add(firstPhoto);
            }
          }
        }
      }
      
      // Preload in background - don't block UI
      if (profileUrls.isNotEmpty) {
        unawaited(ImageCacheManager.preloadProfilePictures(profileUrls.toSet().toList()));
      }
      if (photoUrls.isNotEmpty) {
        unawaited(ImageCacheManager.preloadSessionPhotos(photoUrls));
      }
      
      developer.log('[HOME_DEBUG] Started preloading ${profileUrls.length} profile pics and ${photoUrls.length} session photos');
    } catch (e) {
      developer.log('[HOME_DEBUG] Error preloading images: $e');
    }
  }
} // Closes _HomeTabState class