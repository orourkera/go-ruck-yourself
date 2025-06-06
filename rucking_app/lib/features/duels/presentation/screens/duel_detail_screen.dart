import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/duel.dart';
import '../../domain/entities/duel_participant.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../bloc/duel_detail/duel_detail_bloc.dart';
import '../bloc/duel_detail/duel_detail_event.dart';
import '../bloc/duel_detail/duel_detail_state.dart';
import '../widgets/duel_info_card.dart';
import '../widgets/duel_progress_chart.dart';
import '../widgets/duel_leaderboard_widget.dart';
import '../widgets/duel_participants_list.dart';
import '../widgets/duel_comments_section.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/styled_snackbar.dart';

class DuelDetailScreen extends StatefulWidget {
  final String duelId;

  const DuelDetailScreen({
    super.key,
    required this.duelId,
  });

  @override
  State<DuelDetailScreen> createState() => _DuelDetailScreenState();
}

class _DuelDetailScreenState extends State<DuelDetailScreen> with TickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    context.read<DuelDetailBloc>().add(LoadDuelDetail(duelId: widget.duelId));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Duel Details'),
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context.read<DuelDetailBloc>().add(
              RefreshDuelDetail(duelId: widget.duelId),
            ),
          ),
        ],
      ),
      body: BlocConsumer<DuelDetailBloc, DuelDetailState>(
        listener: (context, state) {
          if (state is DuelJoinedFromDetail) {
            StyledSnackBar.showSuccess(
              context: context,
              message: state.message,
            );
          } else if (state is DuelJoinErrorFromDetail) {
            StyledSnackBar.showError(
              context: context,
              message: state.message,
            );
          } else if (state is DuelProgressUpdated) {
            StyledSnackBar.showSuccess(
              context: context,
              message: state.message,
            );
          } else if (state is DuelProgressUpdateError) {
            StyledSnackBar.showError(
              context: context,
              message: state.message,
            );
          } else if (state is DuelStartedManually) {
            StyledSnackBar.showSuccess(
              context: context,
              message: 'Duel started successfully!',
            );
          } else if (state is DuelStartError) {
            StyledSnackBar.showError(
              context: context,
              message: state.message,
            );
          }
        },
        builder: (context, state) {
          if (state is DuelDetailLoading) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          } else if (state is DuelDetailError) {
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
                    onPressed: () => context.read<DuelDetailBloc>().add(
                      LoadDuelDetail(duelId: widget.duelId),
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          } else if (state is DuelDetailLoaded) {
            return _buildDuelDetailContent(state);
          }
          
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildDuelDetailContent(DuelDetailLoaded state) {
    final duel = state.duel;
    final participants = state.leaderboard; // Use leaderboard as participants list
    
    return SingleChildScrollView(
      child: Column(
        children: [
          // Duel Info Header
          DuelInfoCard(
            duel: duel,
            participants: participants,
            currentUserId: _getCurrentUserId() ?? '',
            showJoinButton: _canUserJoin(duel),
            onJoin: _canUserJoin(duel) 
                ? () => context.read<DuelDetailBloc>().add(
                    JoinDuelFromDetail(duelId: widget.duelId),
                  )
                : null,
            showStartButton: _canUserStartDuel(duel),
            onStartDuel: _canUserStartDuel(duel)
                ? () => context.read<DuelDetailBloc>().add(
                    StartDuelManually(duelId: widget.duelId),
                  )
                : null,
            isJoining: state is DuelJoiningFromDetail,
            isStarting: state is DuelStartingManually,
          ),
          
          // Tabs
          Container(
            color: Theme.of(context).colorScheme.surface,
            child: TabBar(
              controller: _tabController,
              labelColor: Theme.of(context).colorScheme.primary,
              unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
              indicatorColor: Theme.of(context).colorScheme.secondary,
              tabs: const [
                Tab(text: 'Progress'),
                Tab(text: 'Leaderboard'),
                Tab(text: 'Participants'),
              ],
            ),
          ),
          
          // Tab Content
          SizedBox(
            height: 280, // Reduced height for TabBarView when content is minimal
            child: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(), // Prevent vertical scrolling inside tabs
              children: [
                // Progress Tab
                DuelProgressChart(
                  duel: duel,
                  participants: participants,
                ),
                
                // Leaderboard Tab
                DuelLeaderboardWidget(
                  duel: duel,
                  participants: participants,
                  showAllParticipants: true,
                ),
                
                // Participants Tab
                DuelParticipantsList(
                  duel: duel,
                  participants: participants,
                ),
              ],
            ),
          ),
          // Comments section
          DuelCommentsSection(duelId: duel.id),
        ],
      ),
    );
  }

  bool _canUserJoin(duel) {
    // TODO: Add logic to check if current user can join
    // - Check if user is already a participant
    // - Check if duel is still accepting participants
    // - Check if max participants reached
    return duel.status == 'pending' || duel.status == 'active';
  }
  
  String? _getCurrentUserId() {
    try {
      final authState = context.read<AuthBloc>().state;
      if (authState is Authenticated) {
        return authState.user.userId;
      }
      return null;
    } catch (e) {
      debugPrint('Error getting current user ID: $e');
      return null;
    }
  }
  
  bool _isUserParticipant(List<DuelParticipant> participants) {
    final currentUserId = _getCurrentUserId();
    if (currentUserId == null) return false;
    
    return participants.any((p) => p.userId == currentUserId);
  }
  
  bool _isUserCreator(Duel duel) {
    final currentUserId = _getCurrentUserId();
    if (currentUserId == null) return false;
    
    return duel.creatorId == currentUserId;
  }
  
  bool _canUserStartDuel(Duel duel) {
    // Only the creator can manually start a duel
    // The duel must be in pending status
    // The duel must have manual start mode
    final bool isCreator = _isUserCreator(duel);
    
    final bool canStart = isCreator && 
                        duel.status == DuelStatus.pending &&
                        duel.startMode == DuelStartMode.manual;
                        
    // Also ensure there are enough participants
    if (canStart) {
      final state = context.read<DuelDetailBloc>().state;
      if (state is DuelDetailLoaded) {
        // Count accepted participants
        final acceptedParticipants = state.leaderboard
            .where((p) => p.status == 'accepted')
            .length;
        return acceptedParticipants >= 2; // Minimum 2 participants required
      }
    }
    
    return false;
  }
}
