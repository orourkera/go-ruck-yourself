import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/service_locator.dart';
import '../../data/models/duel_model.dart';
import '../../domain/entities/duel.dart';
import '../bloc/duel_list/duel_list_bloc.dart';
import '../bloc/duel_list/duel_list_event.dart';
import '../bloc/duel_list/duel_list_state.dart';
import '../widgets/duel_card.dart';
import '../widgets/duel_filter_sheet.dart';
import '../widgets/how_duels_work.dart';
import 'create_duel_screen.dart';
import 'duel_detail_screen.dart';
import 'duel_invitations_screen.dart';
import 'duel_stats_screen.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/styled_snackbar.dart';

class DuelsListScreen extends StatefulWidget {
  const DuelsListScreen({super.key});

  @override
  State<DuelsListScreen> createState() => _DuelsListScreenState();
}

class _DuelsListScreenState extends State<DuelsListScreen> {
  final AuthService _authService = getIt<AuthService>();
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    context.read<DuelListBloc>().add(const LoadMyDuels());
  }

  Future<void> _loadCurrentUser() async {
    final user = await _authService.getCurrentUser();
    if (mounted) {
      setState(() {
        _currentUserId = user?.userId;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Duels'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.primary,
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
        backgroundColor: Theme.of(context).colorScheme.primary,
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
      body: DefaultTabController(
        length: 3,
        child: Column(
          children: [
            _buildStatusTabs(),
            Expanded(
              child: TabBarView(
                children: [
                  // My Duels Tab
                  _buildDuelsView(isMyDuels: true),
                  // Discover Tab  
                  _buildDuelsView(isMyDuels: false),
                  // How Duels Work Tab
                  const HowDuelsWork(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusTabs() {
    return Container(
      color: Theme.of(context).colorScheme.primary,
      child: TabBar(
        indicatorColor: Theme.of(context).colorScheme.secondary,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
        onTap: (index) {
          if (index == 0) {
            // My Duels - show duels user is participating in
            context.read<DuelListBloc>().add(const LoadMyDuels());
          } else if (index == 1) {
            // Discover - show duels available to join
            context.read<DuelListBloc>().add(const LoadDiscoverDuels());
          }
        },
        tabs: const [
          Tab(text: 'My Duels'),
          Tab(text: 'Discover'),
          Tab(text: 'How Duels Work'),
        ],
      ),
    );
  }

  Widget _buildDuelsView({required bool isMyDuels}) {
    return BlocConsumer<DuelListBloc, DuelListState>(
      listener: (context, state) {
        if (state is DuelJoined) {
          StyledSnackBar.showSuccess(
            context: context,
            message: state.message,
          );
        } else if (state is DuelJoinError) {
          StyledSnackBar.showError(
            context: context,
            message: state.message,
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
                  onPressed: () => context.read<DuelListBloc>().add(const RefreshDuels()),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        } else if (state is DuelListLoaded) {
          return RefreshIndicator(
            onRefresh: () async {
              context.read<DuelListBloc>().add(const RefreshDuels());
            },
            child: _buildDuelsList(state, isMyDuels: isMyDuels),
          );
        }
        
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildDuelsList(DuelListLoaded state, {required bool isMyDuels}) {
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
                onPressed: () => context.read<DuelListBloc>().add(const ClearFilters()),
                child: const Text('Clear Filters'),
              ),
            ] else ...[
              Text(
                isMyDuels ? 'No Duels Yet!' : 'No Duels to Discover!',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.grey[700],
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  isMyDuels 
                    ? 'You haven\'t joined or created any duels yet. Get started by creating your first duel or browsing available duels to join!'
                    : 'No duels are currently available to join. Create a new duel to get started!',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[500],
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
        final isCurrentUserCreator = _currentUserId != null && duel.creatorId == _currentUserId;
        final isCurrentUserParticipant = _isCurrentUserParticipant(duel);
        
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DuelCard(
            duel: duel,
            participants: duel is DuelModel ? duel.participants : [],
            showJoinButton: !isCurrentUserCreator && !isCurrentUserParticipant,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DuelDetailScreen(duelId: duel.id),
              ),
            ),
            onJoin: (!isCurrentUserCreator && !isCurrentUserParticipant) ? () => context.read<DuelListBloc>().add(
              JoinDuel(duelId: duel.id),
            ) : null,
          ),
        );
      },
    );
  }

  bool _isCurrentUserParticipant(Duel duel) {
    if (duel is DuelModel) {
      return duel.participants.any((participant) => participant.userId == _currentUserId);
    }
    return false;
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
          context.read<DuelListBloc>().add(const ClearFilters());
          Navigator.pop(context);
        },
      ),
    );
  }
}
