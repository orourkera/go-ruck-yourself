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
    debugPrint('🐞 [_RuckBuddiesScreenState.initState] Initializing RuckBuddiesScreen.');
    _scrollController.addListener(_onScroll);
    
    // Schedule BLoC event for the first frame to avoid context access issues
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Initial fetch
      if (mounted) {
        debugPrint('🐞 [_RuckBuddiesScreenState.initState] Dispatching FetchRuckBuddiesEvent.');
        context.read<RuckBuddiesBloc>().add(const FetchRuckBuddiesEvent());
      }
    });
  }
  
  // Batch check likes for all displayed ruck buddies to avoid rate limiting
  void _batchCheckLikes(List<RuckBuddy> ruckBuddies) {
    if (ruckBuddies.isEmpty) return;
    
    // Extract all ruck IDs
    final List<int> ruckIds = [];
    for (final buddy in ruckBuddies) {
      final id = int.tryParse(buddy.id);
      if (id != null) ruckIds.add(id);
    }
    
    if (ruckIds.isNotEmpty) {
      debugPrint('🐞 [_RuckBuddiesScreenState._batchCheckLikes] Batch checking ${ruckIds.length} rucks');
      try {
        // Use the batch checking method instead of individual checks
        // This reduces API calls and avoids rate limiting
        context.read<SocialBloc>().add(BatchCheckUserLikeStatus(ruckIds));
      } catch (e) {
        debugPrint('❌ Error batch checking likes: $e');
        // We don't need to show an error to the user for this background operation
      }
    }
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
      final state = context.read<RuckBuddiesBloc>().state;
      debugPrint('🐞 [_RuckBuddiesScreenState._onScroll] Scroll isBottom. Current state: ${state.runtimeType}');
      if (state is RuckBuddiesLoaded) {
        if (!state.isLoadingMore && !state.hasReachedMax) {
          debugPrint('🐞 [_RuckBuddiesScreenState._onScroll] Dispatching FetchMoreRuckBuddiesEvent.');
          context.read<RuckBuddiesBloc>().add(const FetchMoreRuckBuddiesEvent());
        } else {
          debugPrint('🐞 [_RuckBuddiesScreenState._onScroll] Not fetching more. isLoadingMore: ${state.isLoadingMore}, hasReachedMax: ${state.hasReachedMax}');
        }
      } else {
        debugPrint('🐞 [_RuckBuddiesScreenState._onScroll] Not fetching more. State is not RuckBuddiesLoaded.');
      }
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
    debugPrint('🐞 [_RuckBuddiesScreenState.build] Called.');
    
    // Check for lady mode in AuthBloc
    bool isLadyMode = false;
    String authStateInfo = 'Unknown';
    try {
      final authBloc = BlocProvider.of<AuthBloc>(context);
      if (authBloc.state is Authenticated) {
        isLadyMode = (authBloc.state as Authenticated).user.gender == 'female';
        authStateInfo = 'Authenticated, User gender: ${(authBloc.state as Authenticated).user.gender}';
      } else {
        authStateInfo = 'Not Authenticated or AuthBloc state is ${authBloc.state.runtimeType}';
      }
    } catch (e) {
      // If we can't access the auth bloc, default to standard mode
      authStateInfo = 'Error accessing AuthBloc: $e';
      debugPrint('🐞 [_RuckBuddiesScreenState.build] Could not determine gender for theme: $e');
    }
    debugPrint('🐞 [_RuckBuddiesScreenState.build] AuthState: $authStateInfo, isLadyMode: $isLadyMode');
    
    // Use lady mode colors for female users
    final Color primaryColor = isLadyMode ? AppColors.ladyPrimary : AppColors.primary;
    
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        title: const Text('Ruck Buddies'),
        elevation: 0,
        actions: [
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context.read<RuckBuddiesBloc>().add(const FetchRuckBuddiesEvent());
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          debugPrint('🐞 [_RuckBuddiesScreenState.build] RefreshIndicator onRefresh triggered');
          context.read<RuckBuddiesBloc>().add(RefreshRuckBuddiesEvent());
        },
        child: BlocBuilder<RuckBuddiesBloc, RuckBuddiesState>(
          builder: (context, state) {
            debugPrint('🐞 [_RuckBuddiesScreenState.build] Current state: ${state.runtimeType}');
            if (state is RuckBuddiesInitial) {
              debugPrint('🐞 [_RuckBuddiesScreenState.build] State is Initial. Dispatch fetch.');
              context.read<RuckBuddiesBloc>().add(const FetchRuckBuddiesEvent());
              return const Center(child: CircularProgressIndicator());
            } else if (state is RuckBuddiesLoading) {
              debugPrint('🐞 [_RuckBuddiesScreenState.build] State is Loading');
              return const Center(child: CircularProgressIndicator());
            } else if (state is RuckBuddiesLoaded) {
              debugPrint('🐞 [_RuckBuddiesScreenState.build] State is Loaded. ${state.ruckBuddies.length} buddies');
              
              // IMPORTANT: Batch check likes for all ruck buddies to prevent duplicate API calls
              if (state.ruckBuddies.isNotEmpty) {
                // Schedule this for after the current build cycle to avoid triggering another rebuild
                Future.delayed(Duration.zero, () {
                  if (mounted) {
                    _batchCheckLikes(state.ruckBuddies);
                  }
                });
              }
              
              // Don't show empty state if we're still loading
              if (state.ruckBuddies.isEmpty && !state.isLoadingMore) {
                return EmptyState(
                  icon: Icons.group_off,
                  title: 'No Ruck Buddies Yet',
                  message: 'Looks like there are no ruck buddies to show right now.',
                  action: ElevatedButton(
                    onPressed: () {
                      context.read<RuckBuddiesBloc>().add(const FetchRuckBuddiesEvent());
                    },
                    child: const Text('Refresh'),
                  ),
                );
              }
              
              return _buildRuckBuddiesList(state.ruckBuddies, state.isLoadingMore);
            } else if (state is RuckBuddiesError) {
              debugPrint('🐞 [_RuckBuddiesScreenState.build] State is Error: ${state.message}');
              return ErrorDisplay(
                message: state.message,
                onRetry: () {
                  debugPrint('🐞 [_RuckBuddiesScreenState.build] Error retry button pressed');
                  context.read<RuckBuddiesBloc>().add(const FetchRuckBuddiesEvent());
                },
              );
            }
            
            debugPrint('🐞 [_RuckBuddiesScreenState.build] State is unknown: ${state.runtimeType}');
            return const Center(child: CircularProgressIndicator());
          },
        ),
      ),
    );
  }

  Widget _buildRuckBuddiesList(List<RuckBuddy> ruckBuddies, bool isLoadingMore) {
    debugPrint('🐞 [_RuckBuddiesScreenState._buildRuckBuddiesList] Called with ${ruckBuddies.length} buddies. isLoadingMore: $isLoadingMore');
    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16.0),
      itemCount: isLoadingMore ? ruckBuddies.length + 1 : ruckBuddies.length,
      itemBuilder: (context, index) {
        // debugPrint('🐞 [_RuckBuddiesScreenState._buildRuckBuddiesList itemBuilder] Index: $index, Total items including loader: ${isLoadingMore ? ruckBuddies.length + 1 : ruckBuddies.length}');
        if (isLoadingMore && index == ruckBuddies.length) {
          debugPrint('🐞 [_RuckBuddiesScreenState._buildRuckBuddiesList itemBuilder] Showing loading more indicator at index $index.');
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
          );
        }
        
        // Wrap each card in an error boundary to prevent entire list from failing if one card fails
        try {
          final ruckBuddy = ruckBuddies[index];
          debugPrint('🐞 [_RuckBuddiesScreenState._buildRuckBuddiesList itemBuilder] Building card for buddy ${index+1}/${ruckBuddies.length} with ID: ${ruckBuddy.id}');
          
          return Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: Builder(builder: (context) {
              try {
                return RuckBuddyCard(
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
                );
              } catch (e, stackTrace) {
                debugPrint('❌ Error rendering RuckBuddyCard: $e');
                debugPrint('❌ Stack trace: $stackTrace');
                return Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ruck Session #${ruckBuddy.id}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text('Error rendering this ruck session'),
                        Text('Distance: ${ruckBuddy.distanceKm}km'),
                        Text('Duration: ${ruckBuddy.durationSeconds}s'),
                      ],
                    ),
                  ),
                );
              }
            }),
          );
        } catch (e) {
          debugPrint('❌ Critical error rendering ruck buddy at index $index: $e');
          return const Padding(
            padding: EdgeInsets.only(bottom: 16.0),
            child: Card(
              child: ListTile(
                title: Text('Error loading this ruck session'),
                subtitle: Text('There was a problem displaying this data'),
              ),
            ),
          );
        }
      },
    );
  }
}
