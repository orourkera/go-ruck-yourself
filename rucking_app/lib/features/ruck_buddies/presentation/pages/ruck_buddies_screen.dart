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
    debugPrint('🐞 RuckBuddiesScreen.build called');
    
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
        },
        child: BlocBuilder<RuckBuddiesBloc, RuckBuddiesState>(
          builder: (context, state) {
            debugPrint('🐞 RuckBuddiesScreen BlocBuilder - Current state: ${state.runtimeType}');
            if (state is RuckBuddiesLoading) {
              debugPrint('🐞 RuckBuddiesScreen BlocBuilder - State: RuckBuddiesLoading (initial load)');
              return const Center(child: CircularProgressIndicator());
            } else if (state is RuckBuddiesError) {
              debugPrint('🐞 RuckBuddiesScreen BlocBuilder - State: RuckBuddiesError, Message: ${state.message}');
              return ErrorDisplay(
                message: state.message,
                onRetry: () {
                  context.read<RuckBuddiesBloc>().add(RefreshRuckBuddiesEvent());
                },
              );
            } else if (state is RuckBuddiesLoaded) {
              final ruckBuddies = state.ruckBuddies;
              final isLoadingMore = state.isLoadingMore;
              
              debugPrint('🐞 RuckBuddiesScreen BlocBuilder - State: RuckBuddiesLoaded or LoadingMore, Count: ${ruckBuddies.length}, IsLoadingMore: $isLoadingMore');

              if (ruckBuddies.isEmpty) {
                debugPrint('🐞 RuckBuddiesScreen BlocBuilder - RuckBuddies list is empty, showing EmptyState.');
                return const EmptyState(
                  title: 'No Ruck Buddies',
                  message: 'No ruck buddies found yet. Be the first to share!',
                  icon: Icons.people_outline,
                );
              }
              return _buildRuckBuddiesList(ruckBuddies, isLoadingMore);
            } else {
              // Default to empty state if initial or unknown state
              debugPrint('🐞 RuckBuddiesScreen BlocBuilder - State: Initial or Unknown, showing EmptyState.');
              return const EmptyState(
                title: 'No Ruck Buddies',
                message: 'No ruck buddies found yet. Be the first to share!',
                icon: Icons.people_outline,
              );
            }
          },
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
        
        // Wrap each card in an error boundary to prevent entire list from failing if one card fails
        try {
          final ruckBuddy = ruckBuddies[index];
          debugPrint('🐞 Building card for buddy ${index+1}/${ruckBuddies.length} with ID: ${ruckBuddy.id}');
          
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
