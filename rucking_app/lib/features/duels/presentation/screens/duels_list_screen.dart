import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/duel_list/duel_list_bloc.dart';
import '../bloc/duel_list/duel_list_event.dart';
import '../bloc/duel_list/duel_list_state.dart';
import '../widgets/duel_card.dart';
import '../widgets/duel_filter_sheet.dart';
import 'create_duel_screen.dart';
import 'duel_detail_screen.dart';
import 'duel_invitations_screen.dart';
import 'duel_stats_screen.dart';
import '../../../../shared/theme/app_colors.dart';

class DuelsListScreen extends StatefulWidget {
  const DuelsListScreen({super.key});

  @override
  State<DuelsListScreen> createState() => _DuelsListScreenState();
}

class _DuelsListScreenState extends State<DuelsListScreen> {
  @override
  void initState() {
    super.initState();
    context.read<DuelListBloc>().add(const LoadDuels());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Duels'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () => _showFiltersSheet(context),
          ),
          IconButton(
            icon: const Icon(Icons.notifications),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const DuelInvitationsScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const CreateDuelScreen()),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text(
          'Create Duel',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Column(
        children: [
          _buildStatusTabs(),
          Expanded(
            child: BlocConsumer<DuelListBloc, DuelListState>(
              listener: (context, state) {
                if (state is DuelJoined) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(state.message),
                      backgroundColor: Colors.green,
                    ),
                  );
                } else if (state is DuelJoinError) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(state.message),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              builder: (context, state) {
                if (state is DuelListLoading) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                } else if (state is DuelListError) {
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
                          onPressed: () => context.read<DuelListBloc>().add(RefreshDuels()),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                } else if (state is DuelListLoaded) {
                  return RefreshIndicator(
                    onRefresh: () async {
                      context.read<DuelListBloc>().add(RefreshDuels());
                    },
                    child: _buildDuelsList(state),
                  );
                }
                
                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusTabs() {
    return Container(
      color: AppColors.primary,
      child: DefaultTabController(
        length: 4,
        child: TabBar(
          indicatorColor: AppColors.accent,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          onTap: (index) {
            final statusMap = {
              0: null, // All
              1: 'pending',
              2: 'active',
              3: 'completed',
            };
            context.read<DuelListBloc>().add(
              LoadDuels(status: statusMap[index]),
            );
          },
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Pending'),
            Tab(text: 'Active'),
            Tab(text: 'Completed'),
          ],
        ),
      ),
    );
  }

  Widget _buildDuelsList(DuelListLoaded state) {
    if (state.duels.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.sports_mma,
              size: 80,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 24),
            if (state.hasFilters) ...[
              Text(
                'No duels match your filters',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Try adjusting your filters or create a new duel',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[500],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => context.read<DuelListBloc>().add(ClearFilters()),
                child: const Text('Clear Filters'),
              ),
            ] else ...[
              Text(
                'Welcome to Duels!',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.grey[700],
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Duels are your chance to connect and compete with other ruckers. Create a duel, be matched with a rucker at your level and enjoy a little healthy competition! Create your first duel today!',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.grey[600],
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: state.duels.length,
      itemBuilder: (context, index) {
        final duel = state.duels[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DuelCard(
            duel: duel,
            participants: [], // TODO: Get actual participants for this duel
            showJoinButton: true,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DuelDetailScreen(duelId: duel.id),
              ),
            ),
            onJoin: () => context.read<DuelListBloc>().add(
              JoinDuel(duelId: duel.id),
            ),
          ),
        );
      },
    );
  }

  void _showFiltersSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DuelFilterSheet(
        onApplyFilters: (status, challengeType, location) {
          context.read<DuelListBloc>().add(FilterDuels(
            status: status,
            challengeType: challengeType,
            location: location,
          ));
          Navigator.pop(context);
        },
        onClearFilters: () {
          context.read<DuelListBloc>().add(ClearFilters());
          Navigator.pop(context);
        },
      ),
    );
  }
}
