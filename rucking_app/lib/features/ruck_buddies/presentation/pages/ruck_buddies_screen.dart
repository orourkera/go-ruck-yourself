import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/core/config/app_config.dart';
import 'package:rucking_app/core/utils/measurement_utils.dart';
import 'package:rucking_app/features/ruck_buddies/data/repositories/ruck_buddies_repository_impl.dart';
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
import 'package:rucking_app/shared/widgets/skeleton/skeleton_widgets.dart';

enum RuckBuddiesFilter { ALL, FOLLOWING_ONLY, RECENT, NEARBY }

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
    debugPrint(
        '🐞 [_RuckBuddiesScreenState.initState] Initializing RuckBuddiesScreen.');
    _scrollController.addListener(_onScroll);

    // Schedule BLoC event for the first frame to avoid context access issues
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Initial fetch
      if (mounted) {
        debugPrint(
            '🐞 [_RuckBuddiesScreenState.initState] Dispatching FetchRuckBuddiesEvent.');

        // Clear social cache to ensure fresh like/comment data
        context.read<SocialBloc>().add(ClearSocialCache());

        context
            .read<RuckBuddiesBloc>()
            .add(const FetchRuckBuddiesEvent(limit: 10));
      }
    });
  }

  /// Handle pull-to-refresh action
  Future<void> _onRefresh() async {
    debugPrint(
        '🔄 [_RuckBuddiesScreenState._onRefresh] Pull-to-refresh triggered');

    // Clear the cache to force fresh data
    RuckBuddiesRepositoryImpl.clearRuckBuddiesCache();

    // Clear social cache to get fresh like/comment data
    context.read<SocialBloc>().add(ClearSocialCache());

    // Fetch fresh data
    context.read<RuckBuddiesBloc>().add(const FetchRuckBuddiesEvent(limit: 10));

    // Wait for the data to load
    final completer = Completer<void>();
    late StreamSubscription subscription;

    subscription = context.read<RuckBuddiesBloc>().stream.listen((state) {
      if (state is RuckBuddiesLoaded || state is RuckBuddiesError) {
        subscription.cancel();
        completer.complete();
      }
    });

    return completer.future;
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
      debugPrint(
          '🐞 [_RuckBuddiesScreenState._onScroll] Scroll isBottom. Current state: ${state.runtimeType}');
      if (state is RuckBuddiesLoaded) {
        if (!state.isLoadingMore && !state.hasReachedMax) {
          debugPrint(
              '🐞 [_RuckBuddiesScreenState._onScroll] Dispatching FetchMoreRuckBuddiesEvent.');
          context
              .read<RuckBuddiesBloc>()
              .add(const FetchMoreRuckBuddiesEvent());
        } else {
          debugPrint(
              '🐞 [_RuckBuddiesScreenState._onScroll] Not fetching more. isLoadingMore: ${state.isLoadingMore}, hasReachedMax: ${state.hasReachedMax}');
        }
      } else {
        debugPrint(
            '🐞 [_RuckBuddiesScreenState._onScroll] Not fetching more. State is not RuckBuddiesLoaded.');
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

  RuckBuddiesFilter _selectedFilter = RuckBuddiesFilter.ALL;

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
        authStateInfo =
            'Authenticated, User gender: ${(authBloc.state as Authenticated).user.gender}';
      } else {
        authStateInfo =
            'Not Authenticated or AuthBloc state is ${authBloc.state.runtimeType}';
      }
    } catch (e) {
      // If we can't access the auth bloc, default to standard mode
      authStateInfo = 'Error accessing AuthBloc: $e';
      debugPrint(
          '🐞 [_RuckBuddiesScreenState.build] Could not determine gender for theme: $e');
    }
    debugPrint(
        '🐞 [_RuckBuddiesScreenState.build] AuthState: $authStateInfo, isLadyMode: $isLadyMode');

    // Lady mode support is handled by the theme system, so we don't need manual color selection

    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? Colors.black
          : AppColors.backgroundLight,
      appBar: AppBar(
        title: const Text('Ruck Buddies'),
        iconTheme: const IconThemeData(color: Colors.white),
        // Info icon removed per request
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Added padding between header and filter chips
            const SizedBox(height: 12),

            // Filter chips for sorting
            BlocBuilder<RuckBuddiesBloc, RuckBuddiesState>(
              builder: (context, state) {
                // Default filter is 'closest'
                String currentFilter = 'closest';

                // Extract current filter from state if available
                if (state is RuckBuddiesLoaded) {
                  currentFilter = state.filter;
                }

                return FilterChipGroup(
                  selectedFilter: currentFilter,
                  onFilterSelected: (filter) {
                    // Clear existing data and load with new filter
                    context
                        .read<RuckBuddiesBloc>()
                        .add(FilterRuckBuddiesEvent(filter: filter));
                  },
                );
              },
            ),

            const SizedBox(height: 8),

            // Main content area with pull-to-refresh
            Expanded(
              child: RefreshIndicator(
                onRefresh: _onRefresh,
                child: BlocConsumer<RuckBuddiesBloc, RuckBuddiesState>(
                  listenWhen: (previous, current) {
                    // Only trigger batch check when new data is loaded (not on loading states)
                    return (current is RuckBuddiesLoaded &&
                        (previous is! RuckBuddiesLoaded ||
                            current.ruckBuddies.length !=
                                (previous as RuckBuddiesLoaded)
                                    .ruckBuddies
                                    .length));
                  },
                  listener: (context, state) {
                    if (state is RuckBuddiesError) {
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(content: Text(state.message)),
                        );
                    }
                  },
                  builder: (context, state) {
                    debugPrint(
                        '🐞 [_RuckBuddiesScreenState.build] BlocBuilder state: ${state.runtimeType}');

                    // Handle initial and loading states
                    if (state is RuckBuddiesInitial ||
                        state is RuckBuddiesLoading) {
                      return SingleChildScrollView(
                        child: Column(
                          children: List.generate(
                              3, (index) => const RuckBuddyCardSkeleton()),
                        ),
                      );
                    }
                    // Handle loaded state with data
                    else if (state is RuckBuddiesLoaded) {
                      final ruckBuddies = state.ruckBuddies;
                      final isLoadingMore = state.isLoadingMore;

                      if (ruckBuddies.isEmpty) {
                        // Show different empty state based on current filter
                        if (state.filter == 'following') {
                          return EmptyState(
                            title: 'No Buddy Rucks Yet',
                            message:
                                'Start following other ruckers to see their recent activities here!',
                            action: ElevatedButton(
                              onPressed: () {
                                // Switch to "Closest" filter to discover people to follow
                                context.read<RuckBuddiesBloc>().add(
                                    const FetchRuckBuddiesEvent(
                                        filter: 'closest'));
                              },
                              child: const Text('Discover Ruckers'),
                            ),
                          );
                        } else {
                          return EmptyState(
                            title: 'No Ruck Buddies Yet',
                            message:
                                'Be the first to share your rucks with the community!',
                            action: ElevatedButton(
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Sharing feature coming soon!')));
                              },
                              child: const Text('Share Your Rucks'),
                            ),
                          );
                        }
                      }

                      return _buildRuckBuddiesList(ruckBuddies, isLoadingMore);
                    } else if (state is RuckBuddiesError) {
                      return ErrorDisplay(
                        message: state.message,
                        onRetry: () {
                          context
                              .read<RuckBuddiesBloc>()
                              .add(const FetchRuckBuddiesEvent());
                        },
                      );
                    }

                    // Fallback
                    return Column(
                      children: List.generate(
                          3, (index) => const RuckBuddyCardSkeleton()),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRuckBuddiesList(
      List<RuckBuddy> ruckBuddies, bool isLoadingMore) {
    debugPrint(
        '🐞 [_RuckBuddiesScreenState._buildRuckBuddiesList] Called with ${ruckBuddies.length} buddies. isLoadingMore: $isLoadingMore');
    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16.0),
      // Critical optimizations to prevent widget disposal during scroll
      addAutomaticKeepAlives: true, // Preserve widget state during scroll
      addRepaintBoundaries: true, // Better rendering performance
      cacheExtent: 1000, // Cache widgets 1000 pixels outside viewport
      itemCount: isLoadingMore ? ruckBuddies.length + 1 : ruckBuddies.length,
      itemBuilder: (context, index) {
        // debugPrint('🐞 [_RuckBuddiesScreenState._buildRuckBuddiesList itemBuilder] Index: $index, Total items including loader: ${isLoadingMore ? ruckBuddies.length + 1 : ruckBuddies.length}');
        if (isLoadingMore && index == ruckBuddies.length) {
          debugPrint(
              '🐞 [_RuckBuddiesScreenState._buildRuckBuddiesList itemBuilder] Showing loading more indicator at index $index.');
          return const RuckBuddyCardSkeleton();
        }

        // Wrap each card in an error boundary to prevent entire list from failing if one card fails
        try {
          final ruckBuddy = ruckBuddies[index];
          debugPrint(
              '🐞 [_RuckBuddiesScreenState._buildRuckBuddiesList itemBuilder] Building card for buddy ${index + 1}/${ruckBuddies.length} with ID: ${ruckBuddy.id}');

          return Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: Builder(builder: (context) {
              try {
                return RuckBuddyCard(
                  key: ValueKey(
                      ruckBuddy.id), // Unique key for stable widget identity
                  ruckBuddy: ruckBuddy,
                  onTap: () async {
                    // Navigate to detail screen and await return
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) =>
                            RuckBuddyDetailScreen(ruckBuddy: ruckBuddy),
                      ),
                    );

                    // When we return, explicitly trigger a batch check for updated like status and comment counts
                    // This ensures our cards reflect the latest state even if they missed updates while off-screen
                    if (mounted) {
                      debugPrint(
                          '🔄 Returned to RuckBuddiesScreen from detail view - refreshing social states');
                      final ruckId = int.tryParse(ruckBuddy.id);
                      if (ruckId != null) {
                        // Only refresh social data for this specific ruck to avoid image reloads
                        context
                            .read<SocialBloc>()
                            .add(CheckRuckLikeStatus(ruckId));
                        context
                            .read<SocialBloc>()
                            .add(LoadRuckComments(ruckBuddy.id));
                      }
                    }
                  },
                  onLikeTap: () {
                    // Use the actual like functionality
                    try {
                      debugPrint(
                          '🔍 Attempting to like ruck buddy with id: ${ruckBuddy.id}');

                      // Parse ruckId to int since SocialBloc expects an integer
                      final ruckId = int.tryParse(ruckBuddy.id);
                      if (ruckId != null) {
                        debugPrint('🔍 Parsed ruckId as int: $ruckId');

                        // Check if SocialBloc is available
                        final socialBloc = context.read<SocialBloc>();
                        debugPrint(
                            '🔍 SocialBloc instance found: ${socialBloc != null}');

                        // Use the SocialBloc to toggle like
                        debugPrint(
                            '🔍 Dispatching ToggleRuckLike event to SocialBloc');
                        socialBloc.add(ToggleRuckLike(ruckId));
                        debugPrint(
                            '🔍 ToggleRuckLike event dispatched successfully');
                      } else {
                        debugPrint(
                            '🔍 Failed to parse ruckId "${ruckBuddy.id}" as integer - cannot toggle like');
                      }
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
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
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
          debugPrint(
              '❌ Critical error rendering ruck buddy at index $index: $e');
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
