import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/core/config/app_config.dart';
import 'package:rucking_app/core/utils/measurement_utils.dart';
import 'package:rucking_app/features/ruck_buddies/domain/entities/ruck_buddy.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/ruck_buddies/presentation/bloc/ruck_buddies_bloc.dart';
import 'package:rucking_app/features/ruck_buddies/presentation/pages/ruck_buddy_detail_screen.dart';
import 'package:rucking_app/features/ruck_buddies/presentation/widgets/filter_chip_group.dart';
import 'package:rucking_app/features/ruck_buddies/presentation/widgets/ruck_buddy_card.dart';
import 'package:rucking_app/features/social/presentation/bloc/social_bloc.dart';
import 'package:rucking_app/features/social/presentation/bloc/social_event.dart';
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
    
    // Schedule BLoC event for the first frame to avoid context access issues
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Initial fetch
      if (mounted) {
        context.read<RuckBuddiesBloc>().add(const FetchRuckBuddiesEvent());
        // Preload mock photos for demo
        _preloadDemoImages();
      }
    });
  }
  
  void _preloadDemoImages() {
    // This would be removed when real photo support is implemented
    // Preload sample images
    const sampleUrls = [
      'https://images.unsplash.com/photo-1551632811-561732d1e306',
      'https://images.unsplash.com/photo-1470071459604-3b5ec3a7fe05',
      'https://images.unsplash.com/photo-1441974231531-c6227db76b6e'
    ];
    
    for (final url in sampleUrls) {
      precacheImage(NetworkImage(url), context);
    }
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
    // Check for lady mode in AuthBloc
    bool isLadyMode = false;
    try {
      final authBloc = BlocProvider.of<AuthBloc>(context);
      if (authBloc.state is Authenticated) {
        isLadyMode = (authBloc.state as Authenticated).user.gender == 'female';
      }
    } catch (e) {
      // If we can't access the auth bloc, default to standard mode
      debugPrint('Could not determine gender for theme: $e');
    }
    
    // Use lady mode colors for female users
    final Color primaryColor = isLadyMode ? AppColors.ladyPrimary : AppColors.primary;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ruck Buddies'),
        elevation: 0,
        backgroundColor: primaryColor,
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
                  
                  final statsUrl = '${AppConfig.apiBaseUrl}/stats/monthly';
                  
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
          child: RuckBuddyCard(
            ruckBuddy: ruckBuddy,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => RuckBuddyDetailScreen(ruckBuddy: ruckBuddy),
                ),
              );
            },
            onLikeTap: () {
              // Use the actual like functionality
              try {
                debugPrint('🔍 Attempting to like ruck buddy with id: ${ruckBuddy.id}');
                
                // Parse ruckId to int since SocialBloc expects an integer
                final ruckId = int.parse(ruckBuddy.id);
                debugPrint('🔍 Parsed ruckId as int: $ruckId');
                
                // Check if SocialBloc is available
                final socialBloc = context.read<SocialBloc>();
                debugPrint('🔍 SocialBloc instance found: ${socialBloc != null}');
                
                // Use the SocialBloc to toggle like
                debugPrint('🔍 Dispatching ToggleRuckLike event to SocialBloc');
                socialBloc.add(ToggleRuckLike(ruckId));
                debugPrint('🔍 ToggleRuckLike event dispatched successfully');
              } catch (e) {
                debugPrint('❌ Error toggling like: $e');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error liking ruck: $e'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
        );
      },
    );
  }
}
