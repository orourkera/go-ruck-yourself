import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/duel_detail/duel_detail_bloc.dart';
import '../bloc/duel_detail/duel_detail_event.dart';
import '../bloc/duel_detail/duel_detail_state.dart';
import '../widgets/duel_info_card.dart';
import '../widgets/duel_progress_chart.dart';
import '../widgets/duel_leaderboard_widget.dart';
import '../widgets/duel_participants_list.dart';
import '../widgets/duel_comments_section.dart';
import '../../../../shared/theme/app_colors.dart';

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
        backgroundColor: AppColors.primary,
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
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.green,
              ),
            );
          } else if (state is DuelJoinErrorFromDetail) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.red,
              ),
            );
          } else if (state is DuelProgressUpdated) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.green,
              ),
            );
          } else if (state is DuelProgressUpdateError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.red,
              ),
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
    
    return Column(
      children: [
        // Duel Info Header
        DuelInfoCard(
          duel: duel,
          participants: participants,
          currentUserId: 'current_user_id', // TODO: Get actual current user ID
          showJoinButton: _canUserJoin(duel),
          onJoin: _canUserJoin(duel) 
              ? () => context.read<DuelDetailBloc>().add(
                  JoinDuelFromDetail(duelId: widget.duelId),
                )
              : null,
          isJoining: state is DuelJoiningFromDetail,
        ),
        
        // Tabs
        Container(
          color: Colors.grey[100],
          child: TabBar(
            controller: _tabController,
            labelColor: AppColors.primary,
            unselectedLabelColor: Colors.grey[600],
            indicatorColor: AppColors.accent,
            tabs: const [
              Tab(text: 'Progress'),
              Tab(text: 'Leaderboard'),
              Tab(text: 'Participants'),
            ],
          ),
        ),
        
        // Tab Content
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: TabBarView(
                  controller: _tabController,
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
              DuelCommentsSection(duelId: duel.id),
            ],
          ),
        ),
      ],
    );
  }

  bool _canUserJoin(duel) {
    // TODO: Add logic to check if current user can join
    // - Check if user is already a participant
    // - Check if duel is still accepting participants
    // - Check if max participants reached
    return duel.status == 'pending' || duel.status == 'active';
  }
}
