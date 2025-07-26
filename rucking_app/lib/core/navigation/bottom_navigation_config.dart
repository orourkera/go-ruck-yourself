import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/core/navigation/alltrails_router.dart';
import 'package:rucking_app/features/planned_rucks/presentation/bloc/planned_ruck_bloc.dart';
import 'package:rucking_app/features/planned_rucks/presentation/bloc/planned_ruck_state.dart';

/// Enhanced bottom navigation configuration with AllTrails integration
class BottomNavigationConfig {
  static const int homeIndex = 0;
  static const int myRucksIndex = 1;
  static const int exploreIndex = 2;
  static const int profileIndex = 3;

  /// Get navigation items with dynamic badges and states
  static List<BottomNavigationItem> getNavigationItems(BuildContext? context) {
    return [
      // Home/Dashboard
      BottomNavigationItem(
        index: homeIndex,
        icon: Icons.home_outlined,
        activeIcon: Icons.home,
        label: 'Home',
        route: '/home',
        badgeCount: null,
      ),
      
      // My Rucks (AllTrails Integration)
      BottomNavigationItem(
        index: myRucksIndex,
        icon: Icons.route_outlined,
        activeIcon: Icons.route,
        label: 'My Rucks',
        route: AllTrailsRouter.myRucks,
        badgeCount: context != null ? _getPlannedRucksBadgeCount(context) : null,
      ),
      
      // Explore/Import Routes
      BottomNavigationItem(
        index: exploreIndex,
        icon: Icons.explore_outlined,
        activeIcon: Icons.explore,
        label: 'Explore',
        route: AllTrailsRouter.routeImport,
        badgeCount: null,
      ),
      
      // Profile
      BottomNavigationItem(
        index: profileIndex,
        icon: Icons.person_outline,
        activeIcon: Icons.person,
        label: 'Profile',
        route: '/profile',
        badgeCount: null,
      ),
    ];
  }

  /// Custom bottom navigation bar with AllTrails integration
  static Widget buildBottomNavigationBar({
    required BuildContext context,
    required int currentIndex,
    required ValueChanged<int> onTap,
    bool showLabels = true,
    bool showBadges = true,
  }) {
    final items = getNavigationItems(context);
    
    return Container(
      decoration: BoxDecoration(
        color: AppColors.backgroundLight,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: items.map((item) {
              final isActive = currentIndex == item.index;
              
              return Expanded(
                child: _buildNavigationItem(
                  context: context,
                  item: item,
                  isActive: isActive,
                  onTap: () => onTap(item.index),
                  showLabel: showLabels,
                  showBadge: showBadges,
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  static Widget _buildNavigationItem({
    required BuildContext context,
    required BottomNavigationItem item,
    required bool isActive,
    required VoidCallback onTap,
    required bool showLabel,
    required bool showBadge,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon with badge
            Stack(
              clipBehavior: Clip.none,
              children: [
                // Main icon
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: isActive 
                        ? AppColors.primary.withOpacity(0.1)
                        : Colors.transparent,
                  ),
                  child: Icon(
                    isActive ? item.activeIcon : item.icon,
                    color: isActive 
                        ? AppColors.primary 
                        : AppColors.textDarkSecondary,
                    size: 24,
                  ),
                ),
                
                // Badge
                if (showBadge && item.badgeCount != null && item.badgeCount! > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: _buildBadge(item.badgeCount!),
                  ),
              ],
            ),
            
            const SizedBox(height: 4),
            
            // Label
            if (showLabel)
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: AppTextStyles.bodySmall.copyWith(
                  color: isActive 
                      ? AppColors.primary 
                      : AppColors.textDarkSecondary,
                  fontWeight: isActive 
                      ? FontWeight.w600 
                      : FontWeight.normal,
                ),
                child: Text(
                  item.label,
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }

  static Widget _buildBadge(int count) {
    return Container(
      width: 16,
      height: 16,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: AppColors.error,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.backgroundLight,
          width: 2,
        ),
      ),
      child: Center(
        child: Text(
          count > 99 ? '99+' : count.toString(),
          style: AppTextStyles.bodySmall.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 10,
          ),
        ),
      ),
    );
  }

  /// Navigation helpers with proper BLoC integration
  static void navigateToTab(BuildContext context, int index) {
    final items = getNavigationItems(context);
    if (index >= 0 && index < items.length) {
      final route = items[index].route;
      
      // Special handling for AllTrails routes
      switch (index) {
        case myRucksIndex:
          AllTrailsRouter.navigateToMyRucks(context);
          break;
        case exploreIndex:
          AllTrailsRouter.navigateToRouteImport(context);
          break;
        default:
          // Use standard navigation for other tabs
          Navigator.of(context).pushNamedAndRemoveUntil(
            route,
            (route) => false,
          );
      }
    }
  }

  /// Dynamic badge count calculations
  static int? _getPlannedRucksBadgeCount(BuildContext context) {
    try {
      final plannedRuckBloc = context.read<PlannedRuckBloc>();
      final state = plannedRuckBloc.state;
      
      if (state is PlannedRuckLoaded) {
        // Count today's rucks and overdue rucks
        final urgentCount = state.todaysRucks.length + state.overdueRucks.length;
        return urgentCount > 0 ? urgentCount : null;
      }
    } catch (e) {
      // BLoC not available, return null
    }
    
    return null;
  }

  /// Floating Action Button integration for quick actions
  static Widget? buildFloatingActionButton(
    BuildContext context, 
    int currentIndex,
  ) {
    switch (currentIndex) {
      case myRucksIndex:
        return _buildMyRucksFloatingActionButton(context);
      case exploreIndex:
        return _buildExploreFloatingActionButton(context);
      default:
        return null;
    }
  }

  static Widget _buildMyRucksFloatingActionButton(BuildContext context) {
    return FloatingActionButton(
      onPressed: () {
        AllTrailsRouter.navigateToRouteImport(context);
      },
      backgroundColor: AppColors.primary,
      child: const Icon(
        Icons.add,
        color: Colors.white,
      ),
    );
  }

  static Widget _buildExploreFloatingActionButton(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: () {
        AllTrailsRouter.navigateToRouteSearch(context);
      },
      backgroundColor: AppColors.primary,
      icon: const Icon(
        Icons.search,
        color: Colors.white,
      ),
      label: const Text(
        'Search Routes',
        style: TextStyle(color: Colors.white),
      ),
    );
  }

  /// Tab persistence helpers
  static void saveLastActiveTab(int index) {
    // This would typically save to SharedPreferences or secure storage
    // Implementation depends on your preferences service
  }

  static int getLastActiveTab() {
    // This would typically load from SharedPreferences
    // Return home as default
    return homeIndex;
  }

  /// Deep link handling for bottom navigation
  static int getTabIndexForRoute(String route) {
    final items = getNavigationItems(null); // Context not needed for route matching
    
    for (final item in items) {
      if (route.startsWith(item.route)) {
        return item.index;
      }
    }
    
    return homeIndex; // Default to home
  }

  /// Handle notification taps that should highlight specific tabs
  static void handleNotificationNavigation(
    BuildContext context,
    String notificationType,
    Map<String, dynamic> data,
  ) {
    switch (notificationType) {
      case 'planned_ruck_reminder':
        final ruckId = data['ruckId'] as String?;
        if (ruckId != null) {
          // Navigate to My Rucks tab and then to specific ruck
          navigateToTab(context, myRucksIndex);
          Future.delayed(const Duration(milliseconds: 300), () {
            // This would navigate to the specific ruck detail
            // Implementation depends on having the PlannedRuck object
          });
        }
        break;
        
      case 'route_import_complete':
        navigateToTab(context, myRucksIndex);
        break;
        
      case 'session_milestone':
        final sessionId = data['sessionId'] as String?;
        if (sessionId != null) {
          AllTrailsRouter.navigateToActiveSession(context, sessionId);
        }
        break;
        
      default:
        // Navigate to home for unknown notification types
        navigateToTab(context, homeIndex);
    }
  }
}

/// Bottom navigation item data class
class BottomNavigationItem {
  final int index;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String route;
  final int? badgeCount;

  const BottomNavigationItem({
    required this.index,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.route,
    this.badgeCount,
  });
}

/// Custom bottom navigation bar widget with enhanced features
class EnhancedBottomNavigationBar extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool showLabels;
  final bool showBadges;
  final bool enableHapticFeedback;

  const EnhancedBottomNavigationBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.showLabels = true,
    this.showBadges = true,
    this.enableHapticFeedback = true,
  });

  @override
  State<EnhancedBottomNavigationBar> createState() => _EnhancedBottomNavigationBarState();
}

class _EnhancedBottomNavigationBarState extends State<EnhancedBottomNavigationBar>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    
    final items = BottomNavigationConfig.getNavigationItems(context);
    _controllers = List.generate(
      items.length,
      (index) => AnimationController(
        duration: const Duration(milliseconds: 200),
        vsync: this,
      ),
    );
    
    _animations = _controllers.map((controller) {
      return Tween<double>(begin: 1.0, end: 0.8).animate(
        CurvedAnimation(parent: controller, curve: Curves.easeInOut),
      );
    }).toList();
    
    // Initialize the current tab as active
    if (widget.currentIndex < _controllers.length) {
      _controllers[widget.currentIndex].forward();
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(EnhancedBottomNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (oldWidget.currentIndex != widget.currentIndex) {
      // Animate tab change
      if (oldWidget.currentIndex < _controllers.length) {
        _controllers[oldWidget.currentIndex].reverse();
      }
      if (widget.currentIndex < _controllers.length) {
        _controllers[widget.currentIndex].forward();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BottomNavigationConfig.buildBottomNavigationBar(
      context: context,
      currentIndex: widget.currentIndex,
      onTap: _handleTap,
      showLabels: widget.showLabels,
      showBadges: widget.showBadges,
    );
  }

  void _handleTap(int index) {
    if (widget.enableHapticFeedback) {
      // Add haptic feedback
      // HapticFeedback.lightImpact();
    }
    
    // Animate the tapped item
    if (index < _controllers.length) {
      _controllers[index].forward().then((_) {
        _controllers[index].reverse();
      });
    }
    
    widget.onTap(index);
  }
}
