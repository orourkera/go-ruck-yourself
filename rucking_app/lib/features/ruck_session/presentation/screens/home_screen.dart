import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/auth/presentation/screens/login_screen.dart';
import 'package:rucking_app/features/profile/presentation/screens/profile_screen.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/create_session_screen.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/session_history_screen.dart';
import 'package:rucking_app/features/statistics/presentation/screens/statistics_screen.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/custom_button.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:rucking_app/core/services/api_client.dart';

/// Main home screen that serves as the central hub of the app
class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  
  // List of screens for the bottom navigation bar
  final List<Widget> _screens = [
    const _HomeTab(),
    const SessionHistoryScreen(),
    const StatisticsScreen(),
    const ProfileScreen(),
  ];
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history_outlined),
            activeIcon: Icon(Icons.history),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart_outlined),
            activeIcon: Icon(Icons.bar_chart),
            label: 'Stats',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

/// Home tab content
class _HomeTab extends StatefulWidget {
  const _HomeTab({Key? key}) : super(key: key);

  @override
  _HomeTabState createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  late final ApiClient _apiClient;
  bool _isLoading = true;
  List<dynamic> _recentSessions = [];
  Map<String, dynamic> _monthlySummaryStats = {};
  
  @override
  void initState() {
    super.initState();
    _apiClient = GetIt.instance<ApiClient>();
    _fetchData();
  }
  
  /// Fetches both recent sessions and monthly stats
  Future<void> _fetchData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });
    try {
      // Fetch recent sessions
      debugPrint('Fetching recent sessions from /rucks?limit=3');
      final sessionsResponse = await _apiClient.get('/rucks?limit=3');
      List<dynamic> processedSessions = _processSessionResponse(sessionsResponse);

      // Fetch monthly stats
      debugPrint('Fetching monthly stats from /statistics/monthly');
      final statsResponse = await _apiClient.get('/statistics/monthly');
      Map<String, dynamic> processedStats = {};
      if (statsResponse is Map && statsResponse.containsKey('data') && statsResponse['data'] is Map) {
          processedStats = statsResponse['data'] as Map<String, dynamic>;
          debugPrint('Monthly stats fetched: $processedStats');
      } else {
          debugPrint('Unexpected monthly stats format: $statsResponse');
      }

      if (mounted) {
        setState(() {
          _recentSessions = processedSessions;
          _monthlySummaryStats = processedStats;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching home screen data: $e');
      if (mounted) {
        setState(() {
          _recentSessions = [];
          _monthlySummaryStats = {};
          _isLoading = false;
        });
      }
    }
  }

  // Helper function to process session response
  List<dynamic> _processSessionResponse(dynamic response) {
    List<dynamic> processedSessions = [];
    if (response == null) {
      debugPrint('Session response is null');
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
     
    debugPrint('Processed ${processedSessions.length} sessions');
    return processedSessions;
  }
  
  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is Unauthenticated) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
        }
      },
      child: Scaffold(
        body: SafeArea(
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
                      // --- Add Logging ---
                      debugPrint('HomeTab: AuthState is Authenticated. User data: ${state.user.toJson()}');
                      // --- End Logging ---
                      
                      // Use the display name from user model
                      if (state.user.displayName.isNotEmpty) {
                        userName = state.user.displayName.split(' ')[0];
                      } else if (state.user.name.isNotEmpty) { // Fallback to name
                         userName = state.user.name.split(' ')[0];
                      } else { // Fallback if both are empty
                         userName = 'Rucker'; // Or maybe state.user.email?
                      }
                    } else {
                       // --- Add Logging ---
                       debugPrint('HomeTab: AuthState is NOT Authenticated ($state)');
                       // --- End Logging ---
                    }
                    
                    // --- Add Logging ---
                    debugPrint('HomeTab: Setting userName to: $userName');
                    // --- End Logging ---
                    
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome back,',
                          style: AppTextStyles.body1.copyWith(
                            color: AppColors.textDarkSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          userName,
                          style: AppTextStyles.headline5.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 32),
                
                // Quick stats section (USE _monthlySummaryStats)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: AppColors.primaryGradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.3),
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
                        style: AppTextStyles.subtitle1.copyWith(
                          color: Colors.white.withOpacity(0.8),
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
                           final distance = preferMetric 
                               ? '${distanceKm.toStringAsFixed(1)} km'
                               : '${(distanceKm * 0.621371).toStringAsFixed(1)} mi';
                           final calories = _monthlySummaryStats['total_calories']?.toString() ?? '0';
                            
                           return Row(
                             mainAxisAlignment: MainAxisAlignment.spaceAround,
                             children: [
                               _buildStatItem('Rucks', rucks, Icons.directions_walk),
                               _buildStatItem('Distance', distance, Icons.straighten),
                               _buildStatItem('Calories', calories, Icons.local_fire_department),
                             ],
                           );
                         }
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                
                // Create session button - full width and orange
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: Text(
                      'START NEW RUCK', 
                      style: AppTextStyles.button.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      )
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.secondary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const CreateSessionScreen(),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 32),
                
                // Recent sessions section
                Text(
                  'Recent Sessions',
                  style: AppTextStyles.headline6,
                ),
                const SizedBox(height: 16),
                
                // Show loading indicator or sessions list
                _isLoading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 30),
                      child: CircularProgressIndicator(),
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
                              style: AppTextStyles.body1.copyWith(
                                color: AppColors.grey,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Your completed sessions will appear here',
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.greyDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : // List of recent sessions
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _recentSessions.length,
                      itemBuilder: (context, index) {
                        final session = _recentSessions[index];
                        
                        // Ensure session is a Map
                        if (session is! Map<String, dynamic>) {
                          debugPrint('Skipping invalid session data: $session');
                          return const SizedBox.shrink(); // Skip non-map items
                        }
                        
                        // Get session date
                        final dateString = session['created_at'] as String? ?? '';
                        final date = DateTime.tryParse(dateString) ?? DateTime.now();
                        final formattedDate = DateFormat('MMM d, yyyy').format(date);
                        
                        // Get session duration directly from session map
                        final durationSecs = session['duration_seconds'] as int? ?? 0;
                        final duration = Duration(seconds: durationSecs);
                        final hours = duration.inHours;
                        final minutes = duration.inMinutes % 60;
                        final durationText = hours > 0 
                            ? '${hours}h ${minutes}m' 
                            : '${minutes}m';
                        
                        // Get distance directly from session map based on user preference
                        final distanceKm = session['distance_km'] as double? ?? 0.0;
                        bool preferMetric = true;
                        final authState = context.read<AuthBloc>().state;
                        if (authState is Authenticated) {
                          preferMetric = authState.user.preferMetric;
                        }
                        
                        final distanceValue = preferMetric 
                            ? distanceKm.toStringAsFixed(1) 
                            : (distanceKm * 0.621371).toStringAsFixed(1);
                        final distanceUnit = preferMetric ? 'km' : 'mi';
                        
                        // Get calories directly from session map
                        final calories = session['calories_burned']?.toString() ?? '0';
                        
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: InkWell(
                            onTap: () {
                              // TODO: Navigate to session details
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        formattedDate,
                                        style: AppTextStyles.subtitle1.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        durationText,
                                        style: AppTextStyles.body2.copyWith(
                                          color: AppColors.textDarkSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      _buildSessionStat(
                                        Icons.straighten, 
                                        '$distanceValue $distanceUnit'
                                      ),
                                      const SizedBox(width: 16),
                                      _buildSessionStat(
                                        Icons.local_fire_department, 
                                        '$calories cal'
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
                      style: AppTextStyles.button.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Builds a statistics item for the quick stats section
  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(
          icon,
          color: Colors.white,
          size: 24,
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: AppTextStyles.headline6.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: Colors.white.withOpacity(0.8),
          ),
        ),
      ],
    );
  }

  /// Builds a session stat item
  Widget _buildSessionStat(IconData icon, String value) {
    return Row(
      children: [
        Icon(
          icon,
          size: 14,
          color: AppColors.textDarkSecondary,
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: AppTextStyles.caption,
        ),
      ],
    );
  }
} 