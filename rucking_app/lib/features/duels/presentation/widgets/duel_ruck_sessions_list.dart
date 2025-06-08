import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/duel.dart';
import '../../domain/entities/duel_participant.dart';
import '../../../ruck_buddies/domain/entities/ruck_buddy.dart';
import '../../../ruck_buddies/presentation/widgets/ruck_buddy_card.dart';
import '../../../ruck_buddies/presentation/bloc/ruck_buddies_bloc.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/theme/app_text_styles.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_display.dart';

class DuelRuckSessionsList extends StatefulWidget {
  final Duel duel;
  final List<DuelParticipant> participants;

  const DuelRuckSessionsList({
    Key? key,
    required this.duel,
    required this.participants,
  }) : super(key: key);

  @override
  State<DuelRuckSessionsList> createState() => _DuelRuckSessionsListState();
}

class _DuelRuckSessionsListState extends State<DuelRuckSessionsList> {
  @override
  void initState() {
    super.initState();
    // Only load ruck sessions if the duel has started
    if (_isDuelStarted()) {
      _loadDuelRuckSessions();
    }
  }

  bool _isDuelStarted() {
    // Check if duel has started based on its status or start date
    return widget.duel.status == DuelStatus.active || 
           (widget.duel.startsAt != null && 
            DateTime.now().isAfter(widget.duel.startsAt!));
  }

  void _loadDuelRuckSessions() {
    // For now, we'll fetch general ruck buddies data
    // In the future, this should be filtered by duel ID
    context.read<RuckBuddiesBloc>().add(const FetchRuckBuddiesEvent());
  }

  @override
  Widget build(BuildContext context) {
    // If duel hasn't started, show appropriate message
    if (!_isDuelStarted()) {
      return _buildNotStartedState();
    }

    return BlocBuilder<RuckBuddiesBloc, RuckBuddiesState>(
      builder: (context, state) {
        if (state is RuckBuddiesLoading) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        } else if (state is RuckBuddiesError) {
          return Center(
            child: ErrorDisplay(
              message: state.message,
              onRetry: _loadDuelRuckSessions,
            ),
          );
        } else if (state is RuckBuddiesLoaded) {
          final ruckSessions = state.ruckBuddies;
          
          if (ruckSessions.isEmpty) {
            return _buildNoSessionsState();
          }

          return _buildRuckSessionsList(ruckSessions);
        }

        return _buildNotStartedState();
      },
    );
  }

  Widget _buildNotStartedState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.schedule,
              size: 64,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(height: 16),
            Text(
              'Duel Not Started',
              style: AppTextStyles.titleLarge.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ruck sessions will appear here once the duel starts and participants begin completing their rucks.',
              style: AppTextStyles.bodyMedium.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Status: ${widget.duel.status.name.toUpperCase()}',
                style: AppTextStyles.bodySmall.copyWith(
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoSessionsState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.directions_run,
              size: 64,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(height: 16),
            Text(
              'No Ruck Sessions Yet',
              style: AppTextStyles.titleLarge.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Participants haven\'t completed any ruck sessions for this duel yet. Check back after they start rucking!',
              style: AppTextStyles.bodyMedium.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRuckSessionsList(List<RuckBuddy> ruckSessions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with count
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Icon(
                Icons.directions_run,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Ruck Sessions (${ruckSessions.length})',
                style: AppTextStyles.titleMedium.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        
        // List of ruck sessions
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            itemCount: ruckSessions.length,
            itemBuilder: (context, index) {
              final ruckSession = ruckSessions[index];
              
              return Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: RuckBuddyCard(
                  ruckBuddy: ruckSession,
                  onTap: () {
                    // Navigate to ruck buddy detail if needed
                    // You can implement navigation here
                  },
                  onLikeTap: () {
                    // Handle like functionality
                    // Implementation depends on your social bloc setup
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
