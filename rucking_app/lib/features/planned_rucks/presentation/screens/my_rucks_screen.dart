import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/core/models/planned_ruck.dart';
import 'package:rucking_app/features/planned_rucks/presentation/bloc/planned_ruck_bloc.dart';
import 'package:rucking_app/features/planned_rucks/presentation/bloc/planned_ruck_event.dart';
import 'package:rucking_app/features/planned_rucks/presentation/bloc/planned_ruck_state.dart';
import 'package:rucking_app/features/planned_rucks/presentation/widgets/planned_ruck_card.dart';
import 'package:rucking_app/features/planned_rucks/presentation/widgets/my_rucks_app_bar.dart';
import 'package:rucking_app/features/planned_rucks/presentation/widgets/status_filter_chips.dart';
import 'package:rucking_app/features/planned_rucks/presentation/widgets/urgent_rucks_banner.dart';
import 'package:rucking_app/features/planned_rucks/presentation/widgets/empty_rucks_state.dart';
import 'package:rucking_app/features/planned_rucks/presentation/screens/route_import_screen.dart';
import 'package:rucking_app/features/planned_rucks/presentation/screens/planned_ruck_detail_screen.dart';
import 'package:rucking_app/core/widgets/error_widget.dart';
import 'package:rucking_app/shared/widgets/loading_indicator.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';


/// Main screen for displaying and managing planned rucks
class MyRucksScreen extends StatefulWidget {
  const MyRucksScreen({super.key});

  @override
  State<MyRucksScreen> createState() => _MyRucksScreenState();
}

class _MyRucksScreenState extends State<MyRucksScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    
    // Load initial data
    context.read<PlannedRuckBloc>().add(const LoadPlannedRucks(forceRefresh: true));
    context.read<PlannedRuckBloc>().add(const LoadTodaysPlannedRucks());
    context.read<PlannedRuckBloc>().add(const LoadUpcomingPlannedRucks());
    context.read<PlannedRuckBloc>().add(const LoadOverduePlannedRucks());

    // Setup infinite scroll
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_isBottom) {
      context.read<PlannedRuckBloc>().add(const LoadMorePlannedRucks());
    }
  }

  bool get _isBottom {
    if (!_scrollController.hasClients) return false;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    return currentScroll >= (maxScroll * 0.9);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: MyRucksAppBar(
        searchController: _searchController,
        onSearchChanged: (query) {
          context.read<PlannedRuckBloc>().add(SearchPlannedRucks(query: query));
        },
        onImportPressed: () => _navigateToImport(),
      ),
      body: BlocConsumer<PlannedRuckBloc, PlannedRuckState>(
        listener: (context, state) {
          if (state is PlannedRuckActionSuccess) {
            _showActionSnackBar(state);
          } else if (state is PlannedRuckActionError) {
            _showErrorSnackBar(state);
          }
        },
        builder: (context, state) {
          return RefreshIndicator(
            onRefresh: () async {
              context.read<PlannedRuckBloc>().add(const RefreshAllPlannedRucks());
            },
            child: Column(
              children: [
                // Urgent rucks banner
                if (state is PlannedRuckLoaded && state.hasUrgentRucks)
                  UrgentRucksBanner(
                    overdueCount: state.overdueRucks.length,
                    todayCount: state.todaysRucks.where((r) => r.status == PlannedRuckStatus.planned).length,
                    onTap: () => _tabController.animateTo(0), // Go to Today tab
                  ),

                // Status filter chips
                if (state is PlannedRuckLoaded)
                  StatusFilterChips(
                    selectedStatus: state.statusFilter,
                    onStatusSelected: (status) {
                      context.read<PlannedRuckBloc>().add(
                        FilterPlannedRucksByStatus(status: status),
                      );
                    },
                  ),

                // Tabs
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TabBar(
                    controller: _tabController,
                    labelColor: AppColors.primary,
                    unselectedLabelColor: AppColors.textDarkSecondary,
                    indicatorColor: AppColors.primary,
                    tabs: const [
                      Tab(text: 'Today'),
                      Tab(text: 'Upcoming'),
                      Tab(text: 'All'),
                      Tab(text: 'Completed'),
                    ],
                  ),
                ),

                // Tab content
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildTodayTab(state),
                      _buildUpcomingTab(state),
                      _buildAllTab(state),
                      _buildCompletedTab(state),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _navigateToImport(),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Plan Ruck'),
      ),
    );
  }

  /// Build today's rucks tab
  Widget _buildTodayTab(PlannedRuckState state) {
    if (state is PlannedRuckLoading) {
      return const Center(child: LoadingIndicator());
    }

    if (state is PlannedRuckError) {
      return Center(
        child: AppErrorWidget(
          message: state.message,
          onRetry: state.canRetry
              ? () => context.read<PlannedRuckBloc>().add(const LoadTodaysPlannedRucks())
              : null,
        ),
      );
    }

    if (state is PlannedRuckLoaded) {
      final todaysRucks = state.todaysRucks;

      if (todaysRucks.isEmpty) {
        return EmptyRucksState(
          title: 'No rucks planned for today',
          subtitle: 'Start planning your next adventure!',
          actionText: 'Plan a Ruck',
          onActionPressed: () => _navigateToImport(),
        );
      }

      return ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: todaysRucks.length,
        itemBuilder: (context, index) {
          final ruck = todaysRucks[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: PlannedRuckCard(
              plannedRuck: ruck,
              onTap: () => _navigateToDetail(ruck),
              onStartPressed: () => _startRuck(ruck),
              onEditPressed: () => _editRuck(ruck),
              onDeletePressed: () => _deleteRuck(ruck),
            ),
          );
        },
      );
    }

    return const SizedBox.shrink();
  }

  /// Build upcoming rucks tab
  Widget _buildUpcomingTab(PlannedRuckState state) {
    if (state is PlannedRuckLoaded) {
      final upcomingRucks = state.upcomingRucks;

      if (upcomingRucks.isEmpty) {
        return EmptyRucksState(
          title: 'No upcoming rucks',
          subtitle: 'Plan some rucks for the coming days!',
          actionText: 'Plan a Ruck',
          onActionPressed: () => _navigateToImport(),
        );
      }

      return ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: upcomingRucks.length,
        itemBuilder: (context, index) {
          final ruck = upcomingRucks[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: PlannedRuckCard(
              plannedRuck: ruck,
              onTap: () => _navigateToDetail(ruck),
              onEditPressed: () => _editRuck(ruck),
              onDeletePressed: () => _deleteRuck(ruck),
            ),
          );
        },
      );
    }

    return _buildLoadingOrError(state);
  }

  /// Build all rucks tab
  Widget _buildAllTab(PlannedRuckState state) {
    if (state is PlannedRuckLoaded) {
      final filteredRucks = state.filteredPlannedRucks;

      if (filteredRucks.isEmpty) {
        if (state.searchQuery?.isNotEmpty == true) {
          return EmptyRucksState(
            title: 'No rucks found',
            subtitle: 'Try adjusting your search or filters',
            actionText: 'Clear Search',
            onActionPressed: () {
              _searchController.clear();
              context.read<PlannedRuckBloc>().add(const SearchPlannedRucks(query: ''));
            },
          );
        }

        return EmptyRucksState(
          title: 'No planned rucks',
          subtitle: 'Import a route or create your first planned ruck!',
          actionText: 'Plan a Ruck',
          onActionPressed: () => _navigateToImport(),
        );
      }

      return ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: filteredRucks.length + (state.hasReachedMax ? 0 : 1),
        itemBuilder: (context, index) {
          if (index >= filteredRucks.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: LoadingIndicator()),
            );
          }

          final ruck = filteredRucks[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: PlannedRuckCard(
              plannedRuck: ruck,
              onTap: () => _navigateToDetail(ruck),
              onStartPressed: ruck.canStart ? () => _startRuck(ruck) : null,
              onEditPressed: () => _editRuck(ruck),
              onDeletePressed: () => _deleteRuck(ruck),
            ),
          );
        },
      );
    }

    return _buildLoadingOrError(state);
  }

  /// Build completed rucks tab
  Widget _buildCompletedTab(PlannedRuckState state) {
    if (state is PlannedRuckLoaded) {
      final completedRucks = state.completedRucks;

      if (completedRucks.isEmpty) {
        return EmptyRucksState(
          title: 'No completed rucks',
          subtitle: 'Complete some rucks to see them here!',
          actionText: 'Plan a Ruck',
          onActionPressed: () => _navigateToImport(),
        );
      }

      return ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: completedRucks.length,
        itemBuilder: (context, index) {
          final ruck = completedRucks[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: PlannedRuckCard(
              plannedRuck: ruck,
              onTap: () => _navigateToDetail(ruck),
              isCompleted: true,
            ),
          );
        },
      );
    }

    return _buildLoadingOrError(state);
  }

  /// Build loading or error state
  Widget _buildLoadingOrError(PlannedRuckState state) {
    if (state is PlannedRuckLoading) {
      return const Center(child: LoadingIndicator());
    }

    if (state is PlannedRuckError) {
      return Center(
        child: AppErrorWidget(
          message: state.message,
          onRetry: state.canRetry
              ? () => context.read<PlannedRuckBloc>().add(const LoadPlannedRucks(forceRefresh: true))
              : null,
        ),
      );
    }

    return const SizedBox.shrink();
  }

  // Navigation methods

  void _navigateToImport() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const RouteImportScreen(),
      ),
    );
  }

  void _navigateToDetail(PlannedRuck ruck) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PlannedRuckDetailScreen(plannedRuckId: ruck.id!),
      ),
    );
  }

  // Action methods

  void _startRuck(PlannedRuck ruck) {
    context.read<PlannedRuckBloc>().add(StartPlannedRuck(plannedRuckId: ruck.id!));
  }

  void _editRuck(PlannedRuck ruck) {
    // TODO: Navigate to edit screen
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Edit functionality coming soon!')),
    );
  }

  void _deleteRuck(PlannedRuck ruck) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Planned Ruck'),
        content: Text('Are you sure you want to delete "${ruck.route?.name ?? 'this ruck'}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.read<PlannedRuckBloc>().add(DeletePlannedRuck(plannedRuckId: ruck.id!));
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // Feedback methods

  void _showActionSnackBar(PlannedRuckActionSuccess state) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(state.message ?? '${state.action.pastTense.capitalize()} successfully'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  void _showErrorSnackBar(PlannedRuckActionError state) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(state.message),
        backgroundColor: AppColors.error,
        action: state.canRetry
            ? SnackBarAction(
                label: 'Retry',
                textColor: Colors.white,
                onPressed: () {
                  // TODO: Implement retry logic based on action type
                },
              )
            : null,
      ),
    );
  }
}

// Extension for string capitalization
extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return this[0].toUpperCase() + substring(1);
  }
}
