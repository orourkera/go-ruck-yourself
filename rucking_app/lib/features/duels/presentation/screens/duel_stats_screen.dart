import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/duel_stats/duel_stats_bloc.dart';
import '../bloc/duel_stats/duel_stats_event.dart';
import '../bloc/duel_stats/duel_stats_state.dart';
import '../widgets/user_stats_card.dart';
import '../widgets/stats_leaderboard_widget.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../core/utils/app_logger.dart';

class DuelStatsScreen extends StatefulWidget {
  const DuelStatsScreen({super.key});

  @override
  State<DuelStatsScreen> createState() => _DuelStatsScreenState();
}

class _DuelStatsScreenState extends State<DuelStatsScreen> with TickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    AppLogger.info('[DUEL_STATS_SCREEN] Initializing DuelStatsScreen');
    _tabController = TabController(length: 4, vsync: this);
    AppLogger.info('[DUEL_STATS_SCREEN] Triggering LoadUserDuelStats event');
    context.read<DuelStatsBloc>().add(const LoadUserDuelStats());
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
        title: const Text('Duel Statistics'),
        elevation: 0,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context.read<DuelStatsBloc>().add(
              const RefreshUserDuelStats(),
            ),
          ),
        ],
      ),
      body: BlocBuilder<DuelStatsBloc, DuelStatsState>(
        builder: (context, state) {
          AppLogger.info('[DUEL_STATS_SCREEN] BlocBuilder state: ${state.runtimeType}');
          
          if (state is DuelStatsLoading) {
            AppLogger.info('[DUEL_STATS_SCREEN] Showing loading indicator');
            return const Center(
              child: CircularProgressIndicator(),
            );
          } else if (state is DuelStatsError) {
            AppLogger.error('[DUEL_STATS_SCREEN] Showing error state: ${state.message}');
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    state.message,
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.read<DuelStatsBloc>().add(
                      const LoadUserDuelStats(),
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          } else if (state is UserDuelStatsLoaded) {
            AppLogger.info('[DUEL_STATS_SCREEN] Showing loaded stats content');
            return _buildStatsContent(state);
          } else if (state is DuelStatsLeaderboardLoaded) {
            AppLogger.info('[DUEL_STATS_SCREEN] Got leaderboard-only state');
            return const Center(
              child: Text('Leaderboard loaded but no user stats'),
            );
          } else if (state is DuelStatsLeaderboardError) {
            AppLogger.error('[DUEL_STATS_SCREEN] Leaderboard error: ${state.message}');
            return Center(
              child: Text('Leaderboard error: ${state.message}'),
            );
          }
          
          AppLogger.warning('[DUEL_STATS_SCREEN] Unknown state: ${state.runtimeType}');
          return const Center(
            child: Text('Unknown state'),
          );
        },
      ),
    );
  }

  Widget _buildStatsContent(UserDuelStatsLoaded state) {
    return Column(
      children: [
        // User Stats Header
        Container(
          color: Colors.grey[50],
          padding: const EdgeInsets.all(16),
          child: UserStatsCard(userStats: state.userStats),
        ),
        
        // Leaderboard Tabs
        Container(
          color: Colors.grey[100],
          child: TabBar(
            controller: _tabController,
            labelColor: AppColors.primary,
            unselectedLabelColor: Colors.grey[600],
            indicatorColor: AppColors.accent,
            onTap: (index) {
              final statTypeMap = {
                0: 'wins',
                1: 'total_duels',
                2: 'win_rate',
                3: 'longest_streak',
              };
              context.read<DuelStatsBloc>().add(
                LoadDuelStatsLeaderboard(statType: statTypeMap[index]!),
              );
            },
            tabs: const [
              Tab(text: 'Wins'),
              Tab(text: 'Total'),
              Tab(text: 'Win Rate'),
              Tab(text: 'Streak'),
            ],
          ),
        ),
        
        // Leaderboard Content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildLeaderboardTab(state, 'wins'),
              _buildLeaderboardTab(state, 'total_duels'),
              _buildLeaderboardTab(state, 'win_rate'),
              _buildLeaderboardTab(state, 'longest_streak'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLeaderboardTab(UserDuelStatsLoaded state, String statType) {
    if (state.currentLeaderboardType != statType) {
      // This tab hasn't been loaded yet
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        context.read<DuelStatsBloc>().add(
          RefreshDuelStatsLeaderboard(statType: statType),
        );
      },
      child: StatsLeaderboardWidget(
        leaderboard: state.leaderboard,
        statType: statType,
        isLoading: state.isLeaderboardLoading,
        currentUserStats: state.userStats,
      ),
    );
  }
}
