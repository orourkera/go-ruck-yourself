import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/core/utils/measurement_utils.dart';
import 'package:rucking_app/features/ruck_buddies/domain/entities/ruck_buddy.dart';
import 'package:rucking_app/features/ruck_buddies/presentation/bloc/ruck_buddies_bloc.dart';
import 'package:rucking_app/features/ruck_buddies/presentation/widgets/filter_chip_group.dart';
import 'package:rucking_app/features/ruck_buddies/presentation/widgets/ruck_buddy_card.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/empty_state.dart';
import 'package:rucking_app/shared/widgets/error_display.dart';

class RuckBuddiesScreen extends StatefulWidget {
  const RuckBuddiesScreen({Key? key}) : super(key: key);

  @override
  State<RuckBuddiesScreen> createState() => _RuckBuddiesScreenState();
}

class _RuckBuddiesScreenState extends State<RuckBuddiesScreen> {
  final ScrollController _scrollController = ScrollController();
  
  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    
    // Initial fetch
    context.read<RuckBuddiesBloc>().add(const FetchRuckBuddiesEvent());
  }
  
  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
  
  void _onScroll() {
    if (_isBottom) {
      context.read<RuckBuddiesBloc>().add(const FetchMoreRuckBuddiesEvent());
    }
  }
  
  bool get _isBottom {
    if (!_scrollController.hasClients) return false;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    // Load more when user scrolls to 80% of the list
    return currentScroll >= (maxScroll * 0.8);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ruck Buddies'),
        elevation: 0,
        backgroundColor: AppColors.primary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context.read<RuckBuddiesBloc>().add(RefreshRuckBuddiesEvent());
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          context.read<RuckBuddiesBloc>().add(RefreshRuckBuddiesEvent());
          // Wait for refresh to complete
          await Future.delayed(const Duration(seconds: 1));
        },
        child: Column(
          children: [
            // Filter chips
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: BlocBuilder<RuckBuddiesBloc, RuckBuddiesState>(
                builder: (context, state) {
                  final String currentFilter = state is RuckBuddiesLoaded 
                      ? state.filter 
                      : 'closest';
                  
                  return FilterChipGroup(
                    selectedFilter: currentFilter,
                    onFilterSelected: (filter) {
                      context.read<RuckBuddiesBloc>().add(
                        FilterRuckBuddiesEvent(filter: filter),
                      );
                    },
                  );
                },
              ),
            ),
            
            // Main content
            Expanded(
              child: BlocBuilder<RuckBuddiesBloc, RuckBuddiesState>(
                builder: (context, state) {
                  if (state is RuckBuddiesInitial || state is RuckBuddiesLoading) {
                    return const Center(child: CircularProgressIndicator());
                  } else if (state is RuckBuddiesLoaded) {
                    if (state.ruckBuddies.isEmpty) {
                      return const EmptyState(
                        title: 'No Ruck Buddies Found',
                        message: 'Enable sharing on your profile and mark your sessions as public to join the community!',
                        icon: Icons.people_outline,
                      );
                    }
                    
                    return _buildRuckBuddiesList(state.ruckBuddies, state.isLoadingMore);
                  } else if (state is RuckBuddiesError) {
                    return ErrorDisplay(
                      message: state.message,
                      onRetry: () {
                        context.read<RuckBuddiesBloc>().add(RefreshRuckBuddiesEvent());
                      },
                    );
                  }
                  
                  return const SizedBox();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildRuckBuddiesList(List<RuckBuddy> ruckBuddies, bool isLoadingMore) {
    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16.0),
      itemCount: ruckBuddies.length + (isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= ruckBuddies.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
          );
        }
        
        final ruckBuddy = ruckBuddies[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 16.0),
          child: RuckBuddyCard(ruckBuddy: ruckBuddy),
        );
      },
    );
  }
}
