import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import '../bloc/leaderboard_bloc.dart';
import '../bloc/leaderboard_event.dart';
import '../bloc/leaderboard_state.dart';
import '../widgets/power_points_modal.dart';
import '../widgets/leaderboard_table.dart';
import '../widgets/leaderboard_header.dart';
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
  late final TextEditingController _searchController;
  late final AnimationController _refreshAnimationController;
  late final AnimationController _updateAnimationController;

  String _currentSortBy = 'powerPoints';
  bool _currentAscending = false;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _searchController = TextEditingController();
    _refreshAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _updateAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    // Listen for scroll to load more users
    _scrollController.addListener(_onScroll);

    // Load initial data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LeaderboardBloc>().add(const LoadLeaderboard());
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _refreshAnimationController.dispose();
    _updateAnimationController.dispose();
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
    return BlocProvider(
      create: (context) => GetIt.instance<LeaderboardBloc>(),
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: Column(
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
            color: Colors.black.withOpacity(0.05),
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

  /// Loading state prettier than morning dew
  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading leaderboard...'),
        ],
      ),
    );
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

    return Column(
      children: [
        // Table header
        LeaderboardHeader(
          sortBy: _currentSortBy,
          ascending: _currentAscending,
          onSort: _handleSort,
          onPowerPointsTap: () => PowerPointsModal.show(context),
        ),
        
        // User list
        Expanded(
          child: LeaderboardTable(
            users: users,
            scrollController: _scrollController,
            isLoadingMore: isLoadingMore,
            hasMore: hasMore,
            isUpdating: isUpdating,
          ),
        ),
      ],
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
  void _handleSort(String sortBy, bool ascending) {
    setState(() {
      _currentSortBy = sortBy;
      _currentAscending = ascending;
    });
    
    context.read<LeaderboardBloc>().add(
      SortLeaderboard(sortBy: sortBy, ascending: ascending),
    );
  }

  /// Handle state changes like a good ranch hand
  void _handleStateChanges(BuildContext context, LeaderboardState state) {
    if (state is LeaderboardError) {
      StyledSnackBar.show(
        context: context,
        message: state.message,
        type: SnackBarType.error,
      );
    } else if (state is LeaderboardUpdating) {
      // Show subtle update animation
      _updateAnimationController.forward().then((_) {
        _updateAnimationController.reset();
      });
    }
  }
}
