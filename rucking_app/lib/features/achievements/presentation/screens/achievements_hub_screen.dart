import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/services/auth_service.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/features/achievements/data/models/achievement_model.dart';
import 'package:rucking_app/features/achievements/presentation/bloc/achievement_bloc.dart';
import 'package:rucking_app/features/achievements/presentation/bloc/achievement_event.dart';
import 'package:rucking_app/features/achievements/presentation/bloc/achievement_state.dart';
import 'package:rucking_app/features/achievements/presentation/widgets/achievement_badge.dart';
import 'package:rucking_app/features/achievements/presentation/widgets/achievement_progress_card.dart';

class AchievementsHubScreen extends StatefulWidget {
  const AchievementsHubScreen({super.key});

  @override
  State<AchievementsHubScreen> createState() => _AchievementsHubScreenState();
}

class _AchievementsHubScreenState extends State<AchievementsHubScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedCategory = 'All';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    
    // Load achievement data
    _loadAchievementData();
  }

  void _loadAchievementData() async {
    try {
      final authService = GetIt.instance<AuthService>();
      final user = await authService.getCurrentUser();
      
      if (user != null) {
        final userId = user.userId;
        
        context.read<AchievementBloc>().add(LoadAchievements());
        context.read<AchievementBloc>().add(LoadUserAchievements(userId));
        context.read<AchievementBloc>().add(LoadUserAchievementProgress(userId));
        context.read<AchievementBloc>().add(LoadAchievementStats(userId));
      }
    } catch (e) {
      // If user retrieval fails, just load the non-user-specific data
      context.read<AchievementBloc>().add(LoadAchievements());
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Achievements',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Progress'),
            Tab(text: 'Collection'),
            Tab(text: 'Stats'),
          ],
        ),
      ),
      body: BlocBuilder<AchievementBloc, AchievementState>(
        builder: (context, state) {
          if (state is AchievementsLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is AchievementsError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Failed to load achievements',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    state.message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () async {
                      try {
                        final authService = GetIt.instance<AuthService>();
                        final user = await authService.getCurrentUser();
                        if (user != null) {
                          context.read<AchievementBloc>().add(RefreshAchievementData(user.userId));
                        }
                      } catch (e) {
                        // If user retrieval fails, retry loading basic achievements
                        context.read<AchievementBloc>().add(LoadAchievements());
                      }
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (state is! AchievementsLoaded) {
            return const SizedBox.shrink();
          }

          return TabBarView(
            controller: _tabController,
            children: [
              _buildOverviewTab(state),
              _buildProgressTab(state),
              _buildCollectionTab(state),
              _buildStatsTab(state),
            ],
          );
        },
      ),
    );
  }

  Widget _buildOverviewTab(AchievementsLoaded state) {
    final stats = state.stats;
    final recentAchievements = state.recentAchievements ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats cards
          _buildStatsSection(stats),
          
          const SizedBox(height: 24.0),
          
          // Recent achievements
          if (recentAchievements.isNotEmpty) ...[
            Text(
              'Recent Achievements',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16.0),
            SizedBox(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: recentAchievements.length,
                itemBuilder: (context, index) {
                  final userAchievement = recentAchievements[index];
                  // Extract the achievement from UserAchievement or find it in allAchievements
                  final achievement = userAchievement.achievement ?? 
                    state.allAchievements.firstWhere(
                      (a) => a.id == userAchievement.achievementId,
                      orElse: () => Achievement(
                        id: userAchievement.achievementId,
                        achievementKey: 'unknown',
                        name: 'Unknown Achievement',
                        description: 'Achievement details not available',
                        category: 'general',
                        tier: 'bronze',
                        criteria: {},
                        iconName: 'flag',
                        isActive: true,
                      ),
                    );

                  return Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: Column(
                      children: [
                        AchievementBadge(
                          achievement: achievement,
                          isEarned: true,
                          size: 70,
                        ),
                        const SizedBox(height: 8.0),
                        SizedBox(
                          width: 80,
                          child: Text(
                            achievement.name,
                            style: Theme.of(context).textTheme.bodySmall,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24.0),
          ],
          
          // Next achievements to unlock
          _buildNextAchievementsSection(state),
        ],
      ),
    );
  }

  Widget _buildStatsSection(AchievementStats? stats) {
    if (stats == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your Progress',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16.0),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Earned',
                stats.totalEarned.toString(),
                Icons.emoji_events,
                AppColors.primary,
              ),
            ),
            const SizedBox(width: 16.0),
            Expanded(
              child: _buildStatCard(
                'Total',
                stats.totalAvailable.toString(),
                Icons.flag,
                Colors.grey.shade600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16.0),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Completion',
                '${stats.completionPercentage.toStringAsFixed(1)}%',
                Icons.trending_up,
                Colors.green,
              ),
            ),
            const SizedBox(width: 16.0),
            Expanded(
              child: _buildStatCard(
                'Recent',
                '0', // Placeholder since this data isn't in stats
                Icons.schedule,
                Colors.orange,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8.0),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNextAchievementsSection(AchievementsLoaded state) {
    final nextAchievements = state.userProgress
        ?.where((p) => p.progressPercentage > 0 && p.progressPercentage < 100)
        .take(3)
        .toList() ?? [];

    if (nextAchievements.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Close to Unlocking',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16.0),
        ...nextAchievements.map((progress) {
          final achievement = state.allAchievements?.firstWhere(
            (a) => a.id == progress.achievementId,
            orElse: () => Achievement(
              id: progress.achievementId,
              achievementKey: 'unknown',
              name: 'Unknown Achievement',
              description: 'Achievement details not available',
              category: 'general',
              tier: 'bronze',
              criteria: {},
              iconName: 'flag',
              isActive: true,
            ),
          );
          
          if (achievement == null) return const SizedBox.shrink();
          
          return AchievementProgressCard(
            achievement: achievement,
            progress: progress,
            isEarned: false,
            onTap: () => _showAchievementDetails(achievement, progress: progress),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildProgressTab(AchievementsLoaded state) {
    final categories = state.categories ?? [];
    final filteredProgress = _getFilteredProgress(state);

    return Column(
      children: [
        // Category filter
        Container(
          height: 60,
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            itemCount: categories.length + 1,
            itemBuilder: (context, index) {
              final category = index == 0 ? 'All' : categories[index - 1];
              final isSelected = _selectedCategory == category;
              
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: FilterChip(
                  label: Text(category),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      _selectedCategory = category;
                    });
                  },
                  selectedColor: AppColors.primary.withOpacity(0.2),
                  checkmarkColor: AppColors.primary,
                ),
              );
            },
          ),
        ),
        
        // Progress list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            itemCount: filteredProgress.length,
            itemBuilder: (context, index) {
              final progress = filteredProgress[index];
              final achievement = state.allAchievements?.firstWhere(
                (a) => a.id == progress.achievementId,
                orElse: () => Achievement(
                  id: progress.achievementId,
                  achievementKey: 'unknown',
                  name: 'Unknown Achievement',
                  description: 'Achievement details not available',
                  category: 'general',
                  tier: 'bronze',
                  criteria: {},
                  iconName: 'flag',
                  isActive: true,
                ),
              );
              
              if (achievement == null) return const SizedBox.shrink();
              
              return AchievementProgressCard(
                achievement: achievement,
                progress: progress,
                isEarned: false,
                onTap: () => _showAchievementDetails(achievement, progress: progress),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCollectionTab(AchievementsLoaded state) {
    final earnedAchievements = state.userAchievements ?? [];
    final categories = state.categories ?? [];

    return Column(
      children: [
        // Category filter
        Container(
          height: 60,
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            itemCount: categories.length + 1,
            itemBuilder: (context, index) {
              final category = index == 0 ? 'All' : categories[index - 1];
              final isSelected = _selectedCategory == category;
              
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: FilterChip(
                  label: Text(category),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      _selectedCategory = category;
                    });
                  },
                  selectedColor: AppColors.primary.withOpacity(0.2),
                  checkmarkColor: AppColors.primary,
                ),
              );
            },
          ),
        ),
        
        // Achievement grid
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16.0),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.8,
              crossAxisSpacing: 16.0,
              mainAxisSpacing: 16.0,
            ),
            itemCount: earnedAchievements.length,
            itemBuilder: (context, index) {
              final userAchievement = earnedAchievements[index];
              final achievement = state.allAchievements?.firstWhere(
                (a) => a.id == userAchievement.achievementId,
                orElse: () => Achievement(
                  id: userAchievement.achievementId,
                  achievementKey: 'unknown',
                  name: 'Unknown Achievement',
                  description: 'Achievement details not available',
                  category: 'general',
                  tier: 'bronze',
                  criteria: {},
                  iconName: 'flag',
                  isActive: true,
                ),
              );
              
              if (achievement == null) return const SizedBox.shrink();
              
              if (_selectedCategory != 'All' && 
                  achievement.category != _selectedCategory) {
                return const SizedBox.shrink();
              }
              
              return Column(
                children: [
                  AchievementBadge(
                    achievement: achievement,
                    isEarned: true,
                    size: 70,
                    onTap: () => _showAchievementDetails(achievement, userAchievement: userAchievement),
                  ),
                  const SizedBox(height: 8.0),
                  Text(
                    achievement.name,
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatsTab(AchievementsLoaded state) {
    final stats = state.stats;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your Progress',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16.0),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Earned',
                  stats?.totalEarned.toString() ?? '0',
                  Icons.emoji_events,
                  AppColors.primary,
                ),
              ),
              const SizedBox(width: 16.0),
              Expanded(
                child: _buildStatCard(
                  'Total',
                  stats?.totalAvailable.toString() ?? '0',
                  Icons.flag,
                  Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16.0),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Completion',
                  '${stats?.completionPercentage.toStringAsFixed(1) ?? '0.0'}%',
                  Icons.trending_up,
                  Colors.green,
                ),
              ),
              const SizedBox(width: 16.0),
              Expanded(
                child: _buildStatCard(
                  'Recent',
                  state.recentAchievements.length.toString(),
                  Icons.schedule,
                  Colors.orange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<AchievementProgress> _getFilteredProgress(AchievementsLoaded state) {
    return state.userProgress;
  }

  List<Achievement> _getFilteredAchievements(AchievementsLoaded state) {
    final achievements = state.allAchievements;
    final categoryFilter = _selectedCategory?.toLowerCase();
    
    return achievements.where((achievement) {
      final categoryMatch = categoryFilter == null || 
          achievement.category.toLowerCase() == categoryFilter;
      return categoryMatch;
    }).toList();
  }

  void _showAchievementDetails(
    Achievement achievement, {
    AchievementProgress? progress,
    UserAchievement? userAchievement,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (context, scrollController) {
          return SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Handle bar
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                
                const SizedBox(height: 24.0),
                
                // Achievement badge
                AchievementBadge(
                  achievement: achievement,
                  isEarned: userAchievement != null,
                  progress: progress?.progressPercentage,
                  size: 100,
                ),
                
                const SizedBox(height: 24.0),
                
                // Achievement name
                Text(
                  achievement.name,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 8.0),
                
                // Achievement description
                Text(
                  achievement.description,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.grey.shade600,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 24.0),
                
                // Achievement details
                if (userAchievement != null) ...[
                  _buildDetailRow('Earned On', _formatDate(userAchievement.earnedAt)),
                  _buildDetailRow('Category', achievement.category),
                  _buildDetailRow('Tier', achievement.tier.toUpperCase()),
                ] else if (progress != null) ...[
                  _buildDetailRow('Progress', '${progress.progressPercentage.toStringAsFixed(1)}%'),
                  _buildDetailRow('Target', progress.targetValue.toString()),
                  _buildDetailRow('Current', progress.currentValue.toString()),
                  _buildDetailRow('Category', achievement.category),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey.shade600,
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
