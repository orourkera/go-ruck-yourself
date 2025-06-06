import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/duel_invitations/duel_invitations_bloc.dart';
import '../bloc/duel_invitations/duel_invitations_event.dart';
import '../bloc/duel_invitations/duel_invitations_state.dart';
import '../widgets/duel_invitation_card.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/styled_snackbar.dart';

class DuelInvitationsScreen extends StatefulWidget {
  const DuelInvitationsScreen({super.key});

  @override
  State<DuelInvitationsScreen> createState() => _DuelInvitationsScreenState();
}

class _DuelInvitationsScreenState extends State<DuelInvitationsScreen> with TickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    context.read<DuelInvitationsBloc>().add(const LoadDuelInvitations());
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
        title: const Text('Duel Invitations'),
        elevation: 0,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context.read<DuelInvitationsBloc>().add(RefreshDuelInvitations()),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.accent,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          onTap: (index) {
            final statusMap = {
              0: null, // All
              1: 'pending',
              2: 'accepted',
              3: 'declined',
            };
            context.read<DuelInvitationsBloc>().add(
              FilterInvitationsByStatus(status: statusMap[index]),
            );
          },
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Pending'),
            Tab(text: 'Accepted'),
            Tab(text: 'Declined'),
          ],
        ),
      ),
      body: BlocConsumer<DuelInvitationsBloc, DuelInvitationsState>(
        listener: (context, state) {
          if (state is InvitationResponseSuccess) {
            StyledSnackBar.showSuccess(
              context: context,
              message: state.message,
            );
          } else if (state is InvitationResponseError) {
            StyledSnackBar.showError(
              context: context,
              message: state.message,
            );
          }
        },
        builder: (context, state) {
          if (state is DuelInvitationsLoading) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          } else if (state is DuelInvitationsError) {
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
                    onPressed: () => context.read<DuelInvitationsBloc>().add(
                      const LoadDuelInvitations(),
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          } else if (state is DuelInvitationsLoaded) {
            return RefreshIndicator(
              onRefresh: () async {
                context.read<DuelInvitationsBloc>().add(RefreshDuelInvitations());
              },
              child: _buildInvitationsList(state),
            );
          }
          
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildInvitationsList(DuelInvitationsLoaded state) {
    if (state.invitations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.mail_outline,
              size: 80,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 16),
            Text(
              state.hasFilters 
                  ? 'No invitations match your filter'
                  : 'No duel invitations',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              state.hasFilters
                  ? 'Try changing the filter or check back later'
                  : 'You\'ll see duel invitations here when you receive them',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (state.hasFilters)
              TextButton(
                onPressed: () => context.read<DuelInvitationsBloc>().add(ClearInvitationFilters()),
                child: const Text('Clear Filters'),
              ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: state.invitations.length,
      itemBuilder: (context, index) {
        final invitation = state.invitations[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DuelInvitationCard(
            invitation: invitation,
            onAccept: invitation.status == 'pending'
                ? () => context.read<DuelInvitationsBloc>().add(
                    RespondToInvitation(
                      invitationId: invitation.id,
                      response: 'accept',
                    ),
                  )
                : null,
            onDecline: invitation.status == 'pending'
                ? () => context.read<DuelInvitationsBloc>().add(
                    RespondToInvitation(
                      invitationId: invitation.id,
                      response: 'decline',
                    ),
                  )
                : null,
            onViewDuel: () {
              // Navigate to duel detail - for now just show snackbar
              StyledSnackBar.showInfo(
                context: context,
                message: 'Navigate to duel ${invitation.duelId}',
              );
            },
            isResponding: state is InvitationResponding && 
                         (state as InvitationResponding).invitationId == invitation.id,
          ),
        );
      },
    );
  }
}
