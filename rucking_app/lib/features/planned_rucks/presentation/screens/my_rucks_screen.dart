import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/core/models/planned_ruck.dart';
import 'package:rucking_app/features/planned_rucks/presentation/bloc/planned_ruck_bloc.dart';
import 'package:rucking_app/features/planned_rucks/presentation/bloc/planned_ruck_event.dart';
import 'package:rucking_app/features/planned_rucks/presentation/bloc/planned_ruck_state.dart';
import 'package:rucking_app/features/planned_rucks/presentation/widgets/planned_ruck_card.dart';
import 'package:rucking_app/features/planned_rucks/presentation/widgets/my_rucks_app_bar.dart';
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

class _MyRucksScreenState extends State<MyRucksScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    
    // Load all rucks data - no status filter to get ALL rucks regardless of status
    context.read<PlannedRuckBloc>().add(const LoadPlannedRucks(
      forceRefresh: true,
      limit: 100, // Increase limit to show more rucks
    ));

    // Setup infinite scroll
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
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
              context.read<PlannedRuckBloc>().add(const LoadPlannedRucks(
                forceRefresh: true,
                limit: 100, // Same as initial load
              ));
            },
            child: _buildAllRucksView(state),
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

  /// Build all rucks view - simplified single view showing all routes
  Widget _buildAllRucksView(PlannedRuckState state) {
    if (state is PlannedRuckLoaded) {
      final allRucks = state.plannedRucks;

      if (allRucks.isEmpty) {
        return EmptyRucksState(
          title: 'No rucks available',
          subtitle: 'Import or plan your first ruck to get started!',
          actionText: 'Plan a Ruck',
          onActionPressed: () => _navigateToImport(),
        );
      }

      return ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: allRucks.length,
        itemBuilder: (context, index) {
          final ruck = allRucks[index];
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
              ? () => context.read<PlannedRuckBloc>().add(const LoadPlannedRucks(
                  forceRefresh: true,
                  limit: 100, // Same as initial load
                ))
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
