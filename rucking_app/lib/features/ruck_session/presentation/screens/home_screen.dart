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
  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is Unauthenticated) {
          // Navigate to login screen if logged out
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
                    String userName = 'Rucker';
                    if (state is Authenticated) {
                      userName = state.user.name.split(' ')[0];
                    }
                    
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
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
                        ),
                        CircleAvatar(
                          backgroundColor: AppColors.primary,
                          radius: 24,
                          child: const Icon(
                            Icons.person,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 32),
                
                // Quick stats section
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
                        'This Month',
                        style: AppTextStyles.subtitle1.copyWith(
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatItem('Rucks', '5', Icons.directions_walk),
                          _buildStatItem('Distance', '32.4 km', Icons.straighten),
                          _buildStatItem('Calories', '1540', Icons.local_fire_department),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                
                // Create session button
                CustomButton(
                  text: 'Start New Ruck',
                  icon: Icons.add,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CreateSessionScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 32),
                
                // Recent sessions section
                Text(
                  'Recent Sessions',
                  style: AppTextStyles.headline6,
                ),
                const SizedBox(height: 16),
                
                // Test data for recent sessions
                _buildRecentSessionCard(
                  date: 'April 5, 2025',
                  distance: '5.2 km',
                  duration: '1h 10m',
                  calories: '650',
                ),
                const SizedBox(height: 16),
                _buildRecentSessionCard(
                  date: 'April 2, 2025',
                  distance: '4.8 km',
                  duration: '1h 05m',
                  calories: '610',
                ),
                const SizedBox(height: 16),
                _buildRecentSessionCard(
                  date: 'March 29, 2025',
                  distance: '6.5 km',
                  duration: '1h 30m',
                  calories: '820',
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
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const CreateSessionScreen(),
              ),
            );
          },
          backgroundColor: AppColors.primary,
          child: const Icon(Icons.add),
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

  /// Builds a card for displaying a recent ruck session
  Widget _buildRecentSessionCard({
    required String date,
    required String distance,
    required String duration,
    required String calories,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Session icon
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.directions_walk,
                color: AppColors.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            
            // Session details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    date,
                    style: AppTextStyles.subtitle2.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _buildSessionStat(Icons.straighten, distance),
                      const SizedBox(width: 16),
                      _buildSessionStat(Icons.timer, duration),
                      const SizedBox(width: 16),
                      _buildSessionStat(Icons.local_fire_department, calories),
                    ],
                  ),
                ],
              ),
            ),
            
            // View details button
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () {
                // TODO: Navigate to session details screen
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Builds a stat item for the session card
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