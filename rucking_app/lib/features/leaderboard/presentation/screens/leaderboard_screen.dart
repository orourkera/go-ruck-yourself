import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import '../bloc/leaderboard_bloc.dart';
import '../bloc/leaderboard_event.dart';
import '../bloc/leaderboard_state.dart';
import '../widgets/power_points_modal.dart';
import '../widgets/leaderboard_table.dart';
import '../widgets/leaderboard_header.dart';
import '../widgets/live_rucking_indicator.dart';
import '../widgets/leaderboard_skeleton.dart';
import '../../data/models/leaderboard_user_model.dart';
import '../../../../shared/widgets/styled_snackbar.dart';

/// Well I'll be jiggered! This here's the main leaderboard screen, fancier than a county fair
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({Key? key}) : super(key: key);

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen>
    with TickerProviderStateMixin {
  late final ScrollController _scrollController;
  late final ScrollController _horizontalScrollController; // For header
  late final ScrollController _tableHorizontalScrollController; // For table rows
  late final TextEditingController _searchController;
  late final AnimationController _refreshAnimationController;
  late final AnimationController _updateAnimationController;
  late final AnimationController _explosionAnimationController;
  Timer? _realTimeUpdateTimer;

  String _currentSortBy = 'distanceKm'; // Default sort by distance
  bool _currentAscending = false;
  bool _isSearching = false;
  bool _isUpdatingScroll = false; // Prevent infinite loops
  String _currentTimePeriod = 'all_time'; // Default time period
  
  // Shared horizontal scroll offset using ValueNotifier
  late ValueNotifier<double> _horizontalScrollNotifier;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _horizontalScrollController = ScrollController();
    _horizontalScrollNotifier = ValueNotifier(0.0);
    _searchController = TextEditingController();
    
    // Set up horizontal scroll sync listeners
    _setupScrollSync();
    _refreshAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _updateAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _explosionAnimationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    // Listen for scroll to load more users
    _scrollController.addListener(_onScroll);

    // Set up real-time updates every 15 seconds
    _realTimeUpdateTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      // Only update if not currently loading to avoid conflicts
      final currentState = context.read<LeaderboardBloc>().state;
      if (currentState is! LeaderboardLoading && 
          currentState is! LeaderboardLoadingMore) {
        context.read<LeaderboardBloc>().add(const RefreshLeaderboard());
      }
    });

    // Load initial data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LeaderboardBloc>().add(const LoadLeaderboard());
    });
  }

  /// Set up bidirectional scroll sync using ValueNotifier
  void _setupScrollSync() {
    // Header scrolls → update shared offset
    _horizontalScrollController.addListener(() {
      if (!_isUpdatingScroll) {
        _horizontalScrollNotifier.value = _horizontalScrollController.offset;
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _horizontalScrollController.dispose();
    _horizontalScrollNotifier.dispose();
    _searchController.dispose();
    _refreshAnimationController.dispose();
    _updateAnimationController.dispose();
    _explosionAnimationController.dispose();
    _realTimeUpdateTimer?.cancel(); // Cancel the timer
    super.dispose();
  }

  /// Listen for scroll events like a hawk watching for mice
  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      // Load more when near bottom
      context.read<LeaderboardBloc>().add(const LoadMoreUsers());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: Stack(
            children: [
              // Main content
              Column(
                children: [
                  // Header with search and controls
                  _buildHeader(),
                  
                  // Main leaderboard content
                  Expanded(
                    child: BlocConsumer<LeaderboardBloc, LeaderboardState>(
                      listener: _handleStateChanges,
                      builder: (context, state) {
                        return RefreshIndicator(
                          onRefresh: () async {
                            context.read<LeaderboardBloc>().add(const RefreshLeaderboard());
                            _refreshAnimationController.forward().then((_) {
                              _refreshAnimationController.reset();
                            });
                          },
                          child: _buildContent(state),
                        );
                      },
                    ),
                  ),
                ],
              ),
              
              // Floating live rucking indicator - positioned over nav bar
              Positioned(
                bottom: 60, // Much closer to nav bar
                left: 0,
                right: 0,
                child: Center(
                  child: BlocBuilder<LeaderboardBloc, LeaderboardState>(
                    builder: (context, state) {
                      int activeCount = 0;
                      if (state is LeaderboardLoaded) {
                        // Use backend-provided activeRuckersCount
                        activeCount = state.activeRuckersCount;
                      }
                      return activeCount > 0 
                        ? Transform.scale(
                            scale: 1.5, // Make it 50% bigger
                            child: LiveRuckingIndicator(activeRuckersCount: activeCount),
                          )
                        : const SizedBox.shrink(); // Hide when no active ruckers
                    },
                  ),
                ),
              ),
              
              // Explosion animation overlay
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _explosionAnimationController,
                  builder: (context, child) {
                    if (_explosionAnimationController.value == 0) {
                      return const SizedBox.shrink();
                    }
                    return _buildExplosionAnimation();
                  },
                ),
              ),
            ],
          ),
        ),
    );
  }

  /// Build that header prettier than a church steeple
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white.withOpacity(0.05)
                : Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Title row
          Row(
            children: [
              const Text('🏆', style: TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'RUCK LEADERBOARD',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
              ),
              // Manual scroll to user button
              BlocBuilder<LeaderboardBloc, LeaderboardState>(
                builder: (context, state) {
                  List<LeaderboardUserModel> users = [];
                  if (state is LeaderboardLoaded) {
                    users = state.users;
                  } else if (state is LeaderboardUpdating) {
                    users = state.users;
                  }
                  
                  final hasCurrentUser = users.any((user) => user.isCurrentUser);
                  
                  return hasCurrentUser ? IconButton(
                    onPressed: () => _scrollToCurrentUser(users),
                    icon: const Icon(Icons.my_location),
                    tooltip: 'Find My Position',
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                    ),
                  ) : const SizedBox.shrink();
                },
              ),
              // Search toggle button
              IconButton(
                onPressed: () {
                  setState(() {
                    _isSearching = !_isSearching;
                    if (!_isSearching) {
                      _searchController.clear();
                      context.read<LeaderboardBloc>().add(
                        const SearchLeaderboard(query: ''),
                      );
                    }
                  });
                },
                icon: Icon(_isSearching ? Icons.close : Icons.search),
                style: IconButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                ),
              ),
            ],
          ),
          
          // Time period filter chips
          const SizedBox(height: 16),
          _buildTimePeriodFilters(),
          
          // Search bar (if searching)
          if (_isSearching) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search for ruckers...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onChanged: (query) {
                // Debounce search
                Future.delayed(const Duration(milliseconds: 500), () {
                  if (_searchController.text == query) {
                    context.read<LeaderboardBloc>().add(
                      SearchLeaderboard(query: query),
                    );
                  }
                });
              },
            ),
          ],
        ],
      ),
    );
  }

  /// Build content based on state, slicker than a greased pig
  Widget _buildContent(LeaderboardState state) {
    if (state is LeaderboardInitial || state is LeaderboardLoading) {
      return _buildLoadingState();
    } else if (state is LeaderboardError) {
      return _buildErrorState(state);
    } else if (state is LeaderboardLoaded || 
               state is LeaderboardLoadingMore || 
               state is LeaderboardRefreshing ||
               state is LeaderboardUpdating) {
      return _buildLoadedState(state);
    }
    
    return const SizedBox.shrink();
  }

  /// Loading state prettier than morning dew - now with fancy skeleton loading!
  Widget _buildLoadingState() {
    return const LeaderboardSkeleton();
  }

  /// Error state that won't make you madder than a wet hen
  Widget _buildErrorState(LeaderboardError state) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              'Aw Shucks!',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              state.message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                context.read<LeaderboardBloc>().add(const LoadLeaderboard());
              },
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  /// Loaded state with all the bells and whistles
  Widget _buildLoadedState(LeaderboardState state) {
    List<LeaderboardUserModel> users = [];
    bool hasMore = false;
    bool isLoadingMore = false;
    bool isUpdating = false;

    if (state is LeaderboardLoaded) {
      users = state.users;
      hasMore = state.hasMore;
    } else if (state is LeaderboardLoadingMore) {
      users = state.currentUsers;
      isLoadingMore = true;
    } else if (state is LeaderboardRefreshing) {
      users = state.currentUsers;
    } else if (state is LeaderboardUpdating) {
      users = state.users;
      isUpdating = true;
    }

    if (users.isEmpty) {
      return _buildEmptyState();
    }

    return SingleChildScrollView(
      controller: _scrollController,
      child: Row(
        children: [
          // FIXED LEFT TABLE - Header + Rank + User columns
          SizedBox(
            width: 212, // 180px content (40px rank + 140px user) + 32px horizontal padding
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Fixed header
                Container(
                  height: 56, // Increased header height
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    border: Border(
                      bottom: BorderSide(
                        color: Theme.of(context).dividerColor.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 40,
                        child: Text('#', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                      const SizedBox(
                        width: 140, // Fixed 140px for rucker column (-20px smaller)
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text('RUCKER', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ),
                    ],
                  ),
                ),
                // Fixed data rows
                ...users.asMap().entries.map((entry) {
                  final index = entry.key;
                  final user = entry.value;
                  final rank = index + 1;
                  
                  return Container(
                    height: 80, // Increased 1px more
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    decoration: BoxDecoration(
                      color: _getRowColor(context, user, rank, isUpdating && user.isCurrentlyRucking),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(8),
                        bottomLeft: Radius.circular(8),
                      ),
                      border: user.isCurrentUser 
                          ? Border.all(color: Theme.of(context).primaryColor, width: 2)
                          : null,
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(8),
                          bottomLeft: Radius.circular(8),
                        ),
                        onTap: () => _navigateToProfile(context, user),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Row(
                            children: [
                              _buildRankColumn(rank),
                              _buildUserColumn(context, user),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
                
                // Loading indicator
                if (isLoadingMore)
                  Container(
                    height: 80, // Match row height
                    child: const Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
          
          // SCROLLABLE RIGHT TABLE - Header + Stats columns
          Expanded(
            child: SingleChildScrollView(
              controller: _horizontalScrollController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 532, // Updated: 500px columns (80+100+100+100+120) + 32px padding
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Scrollable header
                    Container(
                      height: 56, // Match left header height
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        border: Border(
                          bottom: BorderSide(
                            color: Theme.of(context).dividerColor.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          _buildPowerPointsHeader(120), // Moved to first position
                          _buildHeaderColumn('RUCKS', 'totalRucks', 80),
                          _buildHeaderColumn('DISTANCE', 'distanceKm', 100),
                          _buildHeaderColumn('ELEVATION', 'elevationGainMeters', 100),
                          _buildHeaderColumn('CALORIES', 'caloriesBurned', 100),
                        ],
                      ),
                    ),
                    // Scrollable data rows
                    ...users.asMap().entries.map((entry) {
                      final index = entry.key;
                      final user = entry.value;
                      
                      return Container(
                        height: 80, // Match left row height
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        decoration: BoxDecoration(
                          color: _getRowColor(context, user, index + 1, isUpdating && user.isCurrentlyRucking),
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(8),
                            bottomRight: Radius.circular(8),
                          ),
                          border: user.isCurrentUser 
                              ? Border.all(color: Theme.of(context).primaryColor, width: 2)
                              : null,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Row(
                            children: [
                              _buildStatColumn(_formatPowerPoints(user.stats.powerPoints), width: 120, isPowerPoints: true), // Moved to first position
                              _buildStatColumn(user.stats.totalRucks.toString(), width: 80),
                              _buildStatColumn(_formatDistance(user.stats.distanceKm), width: 100),
                              _buildStatColumn(_formatElevation(user.stats.elevationGainMeters), width: 100),
                              _buildStatColumn(_formatCalories(user.stats.caloriesBurned.round()), width: 100),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                    
                    // Loading indicator
                    if (isLoadingMore)
                      Container(
                        height: 80, // Match row height
                        child: const Center(child: Text('Loading...', style: TextStyle(fontSize: 12))),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Empty state when no users found
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🤠', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            Text(
              'No Ruckers Found',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Be the first to complete a public ruck!',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Handle sorting like organizing a barn
  void _sort(String sortBy, bool ascending) {
    // Dispatch event to BLoC to handle sorting
    context.read<LeaderboardBloc>().add(SortLeaderboard(sortBy: sortBy, ascending: ascending));
  }

  /// Build sortable header column
  Widget _buildHeaderColumn(String title, String sortBy, double width) {
    final isCurrentSort = _currentSortBy == sortBy;
    final color = isCurrentSort 
      ? Theme.of(context).primaryColor 
      : Theme.of(context).brightness == Brightness.dark
          ? Colors.grey.shade300
          : Colors.grey.shade600;

    return SizedBox(
      width: width,
      child: GestureDetector(
        onTap: () {
          // If same column, toggle direction; otherwise, default to descending
          final newAscending = isCurrentSort ? !_currentAscending : false;
          _sort(sortBy, newAscending);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: color,
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isCurrentSort) ...[
                const SizedBox(width: 4),
                Icon(
                  _currentAscending ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 12,
                  color: color,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Build power points header with special styling
  Widget _buildPowerPointsHeader(double width) {
    final isCurrentSort = _currentSortBy == 'powerPoints';
    final color = isCurrentSort 
        ? Colors.amber.shade700 
        : Colors.amber.shade700;

    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.amber.withOpacity(0.1),
              Colors.amber.withOpacity(0.05),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // PP text - tappable for sorting
            GestureDetector(
              onTap: () {
                // Sort by power points 
                final newAscending = isCurrentSort ? !_currentAscending : false;
                _sort('powerPoints', newAscending);
              },
              child: Text(
                'PP',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: color,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            if (isCurrentSort) ...[
              const SizedBox(width: 4),
              Icon(
                _currentAscending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 12,
                color: color,
              ),
            ],
            const SizedBox(width: 4),
            // Question mark - separate tap for modal
            GestureDetector(
              onTap: () {
                PowerPointsModal.show(context);
              },
              child: Icon(
                Icons.help_outline, // Question mark icon
                size: 14,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build explosion animation when ruck completes
  Widget _buildExplosionAnimation() {
    final animation = _explosionAnimationController;
    final screenSize = MediaQuery.of(context).size;
    
    return IgnorePointer(
      child: Container(
        color: Colors.transparent,
        child: Stack(
          children: List.generate(20, (index) {
            final angle = (index / 20) * 2 * 3.14159;
            final distance = animation.value * 200;
            final x = screenSize.width / 2 + distance * (index % 2 == 0 ? 1 : -1) * 0.5;
            final y = screenSize.height / 2 + distance * (index % 3 == 0 ? 1 : -1) * 0.5;
            
            return Positioned(
              left: x,
              top: y,
              child: Transform.scale(
                scale: (1 - animation.value) * 2,
                child: Opacity(
                  opacity: 1 - animation.value,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: [Colors.orange, Colors.red, Colors.yellow, Colors.blue][index % 4],
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  /// Trigger explosion animation
  void _triggerExplosion() {
    _explosionAnimationController.reset();
    _explosionAnimationController.forward();
  }

  /// Build time period filter chips
  Widget _buildTimePeriodFilters() {
    final timePeriods = [
      {'key': 'rucking_now', 'label': 'Rucking Now'},
      {'key': 'last_7_days', 'label': 'Last 7 Days'},
      {'key': 'last_30_days', 'label': 'Last 30 Days'},
      {'key': 'all_time', 'label': 'All Time'},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: timePeriods.map((period) {
          final isSelected = _currentTimePeriod == period['key'];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(
                period['label']!,
                style: TextStyle(
                  color: isSelected 
                      ? Theme.of(context).primaryColor 
                      : Theme.of(context).textTheme.bodyMedium?.color,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              selected: isSelected,
              onSelected: (selected) {
                if (selected && !isSelected) {
                  setState(() {
                    _currentTimePeriod = period['key']!;
                  });
                  context.read<LeaderboardBloc>().add(
                    FilterLeaderboardByTimePeriod(timePeriod: period['key']!),
                  );
                }
              },
              selectedColor: Theme.of(context).primaryColor.withOpacity(0.2),
              checkmarkColor: Theme.of(context).primaryColor,
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Handle state changes like a good ranch hand
  void _handleStateChanges(BuildContext context, LeaderboardState state) {
    // Sync sort state with bloc state and trigger auto-scroll
    if (state is LeaderboardLoaded) {
      _currentSortBy = state.sortBy;
      _currentAscending = state.ascending;
      _currentTimePeriod = state.timePeriod;
      
      // Auto-scroll to current user position
      _scrollToCurrentUser(state.users);
    } else if (state is LeaderboardUpdating) {
      // Also scroll on updates in case user position changed
      _scrollToCurrentUser(state.users);
      
      // Show subtle update animation
      _updateAnimationController.forward().then((_) {
        _updateAnimationController.reset();
      });
    }
    
    if (state is LeaderboardError) {
      StyledSnackBar.show(
        context: context,
        message: state.message,
        type: SnackBarType.error,
      );
    }
  }

  /// Auto-scroll to current user's position in the leaderboard
  void _scrollToCurrentUser(List<LeaderboardUserModel> users) {
    // Find current user's index first
    final currentUserIndex = users.indexWhere((user) => user.isCurrentUser);
    if (currentUserIndex == -1) {
      print('[LEADERBOARD] Current user not found in leaderboard');
      return; // Current user not found
    }
    
    print('[LEADERBOARD] Found current user at index $currentUserIndex');
    
    // Use a longer delay to ensure layout is complete
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted || !_scrollController.hasClients) {
        print('[LEADERBOARD] Scroll controller not ready or widget disposed');
        return;
      }
      
      // Calculate scroll position 
      // Each row is 80px + 4px margin (2px top + 2px bottom) = 84px total
      const rowHeight = 84.0;
      
      // Target position: center the current user's row in the viewport
      final targetPosition = (currentUserIndex * rowHeight) - (MediaQuery.of(context).size.height * 0.3);
      
      // Ensure we don't scroll past bounds
      final maxScrollExtent = _scrollController.position.maxScrollExtent;
      final clampedPosition = targetPosition.clamp(0.0, maxScrollExtent);
      
      print('[LEADERBOARD] Scrolling to position: $clampedPosition (target: $targetPosition, max: $maxScrollExtent)');
      
      // Animate to position
      _scrollController.animateTo(
        clampedPosition,
        duration: const Duration(milliseconds: 1000),
        curve: Curves.easeInOut,
      ).then((_) {
        print('[LEADERBOARD] Scroll animation completed');
      }).catchError((error) {
        print('[LEADERBOARD] Scroll animation failed: $error');
      });
    });
  }

  /// Build rank column with fancy medals for top 3
  Widget _buildRankColumn(int rank) {
    return SizedBox(
      width: 40,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center, // Center vertically in the row
        children: [
          if (rank <= 3)
            Text(
              _getRankEmoji(rank),
              style: const TextStyle(fontSize: 20),
            ),
          Text(
            rank.toString(),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: rank <= 3 ? _getMedalColor(rank) : null,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// Build user column with avatar and username
  Widget _buildUserColumn(BuildContext context, LeaderboardUserModel user) {
    return SizedBox(
      width: 140, // Fixed 140px for rucker column (-20px smaller)
      child: ClipRect( // Clip any overflow
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Avatar with live indicator
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: user.avatarUrl?.isNotEmpty == true
                          ? Image.network(
                              user.avatarUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Image.asset(
                                  user.gender == 'female' 
                                      ? 'assets/images/lady rucker profile.png'
                                      : 'assets/images/profile.png',
                                  fit: BoxFit.cover,
                                );
                              },
                            )
                          : Image.asset(
                              user.gender == 'female' 
                                  ? 'assets/images/lady rucker profile.png'
                                  : 'assets/images/profile.png',
                              fit: BoxFit.cover,
                            ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: user.isCurrentlyRucking
                        ? Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              // Username and rucking status in column
              Flexible(
                child: Container(
                  width: 80, // Much smaller to prevent overflow
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Username with FORCED truncation
                      Text(
                        user.username,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        softWrap: false,
                      ),
                      // "Rucking now!" text for currently rucking users
                      if (user.isCurrentlyRucking)
                        Text(
                          'Rucking now!',
                          style: TextStyle(
                            fontFamily: 'Bangers',
                            fontSize: 10,
                            color: Theme.of(context).brightness == Brightness.dark 
                                ? Colors.lightGreen.shade300 
                                : Colors.green.shade700,
                            height: 0.8, // Reduce line height to save space
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build stat column
  Widget _buildStatColumn(String value, {required double width, bool isPowerPoints = false}) {
    return SizedBox(
      width: width,
      child: Text(
        value,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isPowerPoints ? FontWeight.bold : FontWeight.normal,
          color: isPowerPoints ? Colors.amber.shade700 : null,
        ),
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// Helper methods for medals and formatting
  String _getRankEmoji(int rank) {
    switch (rank) {
      case 1:
        return '🥇';
      case 2:
        return '🥈';
      case 3:
        return '🥉';
      default:
        return '';
    }
  }

  Color? _getMedalColor(int rank) {
    switch (rank) {
      case 1:
        return Colors.amber;
      case 2:
        return Colors.grey.shade400;
      case 3:
        return Colors.brown.shade400;
      default:
        return null;
    }
  }

  String _formatDistance(double distanceKm) {
    if (distanceKm >= 1000) {
      return '${(distanceKm / 1000).toStringAsFixed(1)}k';
    }
    return distanceKm.toStringAsFixed(1);
  }

  String _formatElevation(double elevationM) {
    if (elevationM >= 1000) {
      return '${(elevationM / 1000).toStringAsFixed(1)}k';
    }
    return elevationM.round().toString();
  }

  String _formatCalories(int calories) {
    if (calories >= 1000) {
      return '${(calories / 1000).toStringAsFixed(1)}k';
    }
    return calories.toString();
  }

  String _formatPowerPoints(double powerPoints) {
    if (powerPoints >= 1000000) {
      return '${(powerPoints / 1000000).toStringAsFixed(1)}M';
    } else if (powerPoints >= 1000) {
      return '${(powerPoints / 1000).toStringAsFixed(1)}k';
    } else {
      return powerPoints.toStringAsFixed(0);
    }
  }

  /// Get row background color
  Color _getRowColor(BuildContext context, LeaderboardUserModel user, int rank, bool isUpdating) {
    if (user.isCurrentlyRucking) {
      // HIGHEST PRIORITY: Always highlight currently rucking users with prominent green
      return isUpdating 
        ? Colors.green.withOpacity(0.35) // Very strong green during updates
        : Colors.green.withOpacity(0.25); // Much more visible green always
    } else if (user.isCurrentUser) {
      return Theme.of(context).primaryColor.withOpacity(0.05);
    } else if (rank <= 3) {
      final medalColor = _getMedalColor(rank);
      return medalColor != null ? medalColor.withOpacity(0.05) : Theme.of(context).cardColor;
    } else if (isUpdating) {
      return Colors.blue.withOpacity(0.08); // Subtle blue highlight for general updates
    }
    return Theme.of(context).cardColor;
  }

  /// Build avatar with clean display
  Widget _buildAvatar(LeaderboardUserModel user) {
    final hasAvatar = user.avatarUrl != null && user.avatarUrl!.isNotEmpty;

    Widget avatarWidget;
    if (hasAvatar) {
      avatarWidget = ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image.network(
          user.avatarUrl!,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
        ),
      );
    } else {
      String assetPath = (user.gender == 'female')
          ? 'assets/images/lady rucker profile.png'
          : 'assets/images/profile.png';
      avatarWidget = ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image.asset(
          assetPath,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
        ),
      );
    }

    return Stack(
      children: [
        avatarWidget,
        Positioned(
          right: 0,
          bottom: 0,
          child: user.isCurrentlyRucking
              ? Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Theme.of(context).scaffoldBackgroundColor
                          : Colors.white, 
                      width: 2
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  /// Navigate to user's public profile
  void _navigateToProfile(BuildContext context, LeaderboardUserModel user) {
    Navigator.pushNamed(context, '/profile/${user.userId}');
  }
}
