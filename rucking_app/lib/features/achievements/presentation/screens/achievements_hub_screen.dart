import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/animated_counter.dart';
import 'package:rucking_app/features/achievements/presentation/bloc/achievement_bloc.dart';
import 'package:rucking_app/features/achievements/presentation/bloc/achievement_event.dart';
import 'package:rucking_app/features/achievements/presentation/bloc/achievement_state.dart';
import 'package:rucking_app/features/achievements/data/models/achievement_model.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';

/// Achievements Hub Screen - Main screen for viewing and tracking achievements
class AchievementsHubScreen extends StatefulWidget {
  final String? initialAchievementId;
  
  const AchievementsHubScreen({
    Key? key,
    this.initialAchievementId,
  }) : super(key: key);

  @override
  State<AchievementsHubScreen> createState() => _AchievementsHubScreenState();
}

class _AchievementsHubScreenState extends State<AchievementsHubScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final GlobalKey _achievementsListKey = GlobalKey();
  String? _targetAchievementId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _targetAchievementId = widget.initialAchievementId;
    
    // If an initial achievement ID is provided, select the Collection tab
    if (_targetAchievementId != null) {
      _tabController.animateTo(2); // Collection tab index
    }
    
    // Get user ID from auth
    final authState = context.read<AuthBloc>().state;
    final userId = authState is Authenticated ? authState.user.userId : '';
    
    // Load achievement data
    context.read<AchievementBloc>().add(const LoadAchievements());
    context.read<AchievementBloc>().add(LoadUserAchievements(userId)); // Load user's earned achievements
    context.read<AchievementBloc>().add(LoadAchievementStats(userId));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Achievements',
          style: AppTextStyles.headlineMedium.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppColors.primary,
        elevation: 0,
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Progress'),
            Tab(text: 'Collection'),
          ],
        ),
      ),
      body: BlocBuilder<AchievementBloc, AchievementState>(
        builder: (context, state) {
          return TabBarView(
            controller: _tabController,
            children: [
              _buildOverviewTab(state),
              _buildProgressTab(state),
              _buildCollectionTab(state),
            ],
          );
        },
      ),
    );
  }

  Widget _buildOverviewTab(AchievementState state) {
    // Handle different states
    if (state is AchievementsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (state is AchievementsError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Error loading achievements',
              style: AppTextStyles.titleMedium.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              state.message,
              style: AppTextStyles.bodySmall.copyWith(color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // Default to empty state for initial or other states
    final stats = state is AchievementsLoaded ? state.stats : null;
    final recentAchievements = state is AchievementsLoaded ? state.userAchievements : <UserAchievement>[];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats summary card
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.secondary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    'Your Achievement Progress',
                    style: AppTextStyles.titleLarge.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildStatColumn(
                        stats?.totalEarned.toString() ?? '0', 
                        'Earned', 
                        Icons.emoji_events
                      ),
                      _buildStatColumn(
                        ((stats?.totalAvailable ?? 0) - (stats?.totalEarned ?? 0)).toString(),
                        'In Progress', 
                        Icons.trending_up
                      ),
                      _buildStatColumn(
                        '', // Empty string since we'll use valueWidget
                        'Power Points', 
                        Icons.bolt,
                        valueWidget: AnimatedCounter(
                          targetValue: stats?.powerPoints ?? 0,
                          textStyle: AppTextStyles.titleMedium.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Bangers',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Recent achievements
          Text(
            'Recent Achievements',
            style: AppTextStyles.titleLarge.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          
          // Show recent achievements or placeholder
          if (recentAchievements.isNotEmpty)
            ...recentAchievements.map((achievement) => Card(
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(
                  Icons.emoji_events,
                  color: AppColors.primary,
                ),
                title: Text(achievement.achievement?.name ?? 'Achievement'),
                subtitle: Text(achievement.achievement?.description ?? ''),
                trailing: Text(
                  '${achievement.earnedAt.day}/${achievement.earnedAt.month}',
                  style: AppTextStyles.bodySmall,
                ),
              ),
            )).toList()
          else
            _buildPlaceholderCard('No recent achievements yet'),
          
          const SizedBox(height: 24),
          
          // Categories preview
          Text(
            'Categories',
            style: AppTextStyles.titleLarge.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          
          _buildCategoryGrid(state),
        ],
      ),
    );
  }

  Widget _buildProgressTab(AchievementState state) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Active Progress',
            style: AppTextStyles.titleLarge.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          
          _buildPlaceholderCard('Achievement progress will be shown here'),
        ],
      ),
    );
  }

  Widget _buildCollectionTab(AchievementState state) {
    // Handle different states
    if (state is AchievementsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (state is AchievementsError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Error loading achievements',
              style: AppTextStyles.titleMedium.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              state.message,
              style: AppTextStyles.bodySmall.copyWith(color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final achievements = state is AchievementsLoaded ? state.allAchievements : <Achievement>[];
    final userAchievements = state is AchievementsLoaded ? state.userAchievements : <UserAchievement>[];
    
    // Create a map of earned achievement IDs for quick lookup
    final earnedAchievementIds = userAchievements.map((ua) => ua.achievementId).toSet();

    if (achievements.isEmpty) {
      return Center(
        child: _buildPlaceholderCard('No achievements available'),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'All Achievements (${achievements.length})',
            style: AppTextStyles.titleLarge.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          
          // Achievement list
          ListView.builder(
            key: _achievementsListKey,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: achievements.length,
            itemBuilder: (context, index) {
              // If this is the target achievement, scroll to it after build
              if (_targetAchievementId != null && achievements[index].id == _targetAchievementId) {
                // Use a post frame callback to scroll to this item after rendering
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _scrollToAchievement(index);
                  // Clear the target ID after scrolling to prevent repeat scrolling
                  setState(() {
                    _targetAchievementId = null;
                  });
                });
              }
              final achievement = achievements[index];
              final isEarned = earnedAchievementIds.contains(achievement.id);
              
              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      // Achievement icon/badge
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isEarned 
                            ? _getCategoryColor(achievement.category).withOpacity(0.2)
                            : Colors.grey[200],
                        ),
                        child: Icon(
                          _getCategoryIcon(achievement.category),
                          size: 28,
                          color: isEarned 
                            ? _getCategoryColor(achievement.category)
                            : Colors.grey[400],
                        ),
                      ),
                      const SizedBox(width: 16),
                      
                      // Achievement details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    achievement.name,
                                    style: AppTextStyles.titleMedium.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: isEarned ? Colors.black : Colors.grey[600],
                                    ),
                                  ),
                                ),
                                if (isEarned)
                                  Icon(
                                    Icons.check_circle,
                                    color: Colors.green,
                                    size: 20,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              achievement.description,
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: isEarned ? Colors.grey[700] : Colors.grey[500],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                // Category badge
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _getCategoryColor(achievement.category).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    achievement.category.toUpperCase(),
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: _getCategoryColor(achievement.category),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Tier badge
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _getTierColor(achievement.tier).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    achievement.tier.toUpperCase(),
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: _getTierColor(achievement.tier),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String value, String label, IconData icon, {Widget? valueWidget}) {
    return Column(
      children: [
        Icon(
          icon,
          color: Colors.white,
          size: 24,
        ),
        const SizedBox(height: 8),
        valueWidget ?? Text(
          value,
          style: AppTextStyles.titleMedium.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontFamily: 'Bangers',
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryGrid(AchievementState state) {
    final categories = [
      {'name': 'Distance', 'icon': Icons.directions_run, 'color': Colors.blue},
      {'name': 'Weight', 'icon': Icons.fitness_center, 'color': Colors.red},
      {'name': 'Power', 'icon': Icons.flash_on, 'color': Colors.orange},
      {'name': 'Pace', 'icon': Icons.speed, 'color': Colors.green},
      {'name': 'Time', 'icon': Icons.access_time, 'color': Colors.purple},
      {'name': 'Special', 'icon': Icons.star, 'color': Colors.pink},
    ];

    // Get category stats from state
    final stats = state is AchievementsLoaded ? state.stats : null;
    final categoryStats = stats?.byCategory ?? <String, int>{};

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.0, // Changed from 1.2 to 1.0 for more height
      ),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];
        final categoryName = category['name'] as String;
        final earned = categoryStats[categoryName.toLowerCase()] ?? 0;
        final total = 12; // Default total per category, you can make this dynamic
        
        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Container(
            padding: const EdgeInsets.all(12), // Reduced from 16 to 12
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: (category['color'] as Color).withOpacity(0.1),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  category['icon'] as IconData,
                  size: 28, // Reduced from 32 to 28
                  color: category['color'] as Color,
                ),
                const SizedBox(height: 6), // Reduced from 8 to 6
                Flexible( // Wrap text in Flexible to prevent overflow
                  child: Text(
                    categoryName,
                    style: AppTextStyles.titleMedium.copyWith(
                      fontWeight: FontWeight.bold,
                      color: category['color'] as Color,
                      fontSize: 14, // Slightly smaller font
                    ),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 2), // Reduced from 4 to 2
                Flexible( // Wrap progress text in Flexible
                  child: Text(
                    '$earned/$total',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlaceholderCard(String message) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.emoji_events_outlined,
              size: 48,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: AppTextStyles.bodyLarge.copyWith(
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // Helper methods for category and tier styling
  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'distance':
        return Colors.blue;
      case 'weight':
        return Colors.red;
      case 'power':
        return Colors.orange;
      case 'pace':
        return Colors.green;
      case 'time':
        return Colors.purple;
      case 'special':
        return Colors.pink;
      default:
        return Colors.grey;
    }
  }
  
  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'distance':
        return Icons.directions_run;
      case 'weight':
        return Icons.fitness_center;
      case 'power':
        return Icons.flash_on;
      case 'pace':
        return Icons.speed;
      case 'time':
        return Icons.access_time;
      case 'special':
        return Icons.star;
      default:
        return Icons.emoji_events;
    }
  }
  
  Color _getTierColor(String tier) {
    switch (tier.toLowerCase()) {
      case 'bronze':
        return const Color(0xFFCD7F32);
      case 'silver':
        return const Color(0xFFC0C0C0);
      case 'gold':
        return const Color(0xFFFFD700);
      case 'platinum':
        return const Color(0xFFE5E4E2);
      default:
        return Colors.grey;
    }
  }
  
  // Helper method to scroll to a specific achievement in the list
  void _scrollToAchievement(int index) {
    // Find the render object for the list
    final RenderObject? renderObject = _achievementsListKey.currentContext?.findRenderObject();
    if (renderObject != null) {
      // Calculate position of item and scroll to it
      final RenderBox box = renderObject as RenderBox;
      final position = box.localToGlobal(Offset.zero);
      final scrollPosition = position.dy;
      
      // Determine amount to scroll
      final double itemHeight = 150; // Approximate height of each card
      final double offset = index * itemHeight;
      
      // Scroll to the position
      Scrollable.ensureVisible(
        _achievementsListKey.currentContext!,
        alignment: 0.0,
        duration: const Duration(milliseconds: 400),
      );
    }
  }
}
