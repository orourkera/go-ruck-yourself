import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../widgets/duel_ruck_sessions_list.dart';
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

class _DuelDetailScreenState extends State<DuelDetailScreen> {
  @override
  void initState() {
    super.initState();
    context.read<DuelDetailBloc>().add(LoadDuelDetail(duelId: widget.duelId));
  }

  @override
  void dispose() {
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
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.home),
          onPressed: () {
            // Navigate to home screen using named route, removing all other routes
            Navigator.of(context).pushNamedAndRemoveUntil(
              '/home',
              (route) => false,
            );
          },
        ),
        actions: [
          BlocBuilder<DuelDetailBloc, DuelDetailState>(
            builder: (context, state) {
              if (state is DuelDetailLoaded) {
                return PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    switch (value) {
                      case 'refresh':
                        context.read<DuelDetailBloc>().add(
                              RefreshDuelDetail(duelId: widget.duelId),
                            );
                        break;
                      case 'withdraw':
                        HapticFeedback.vibrate();
                        context.read<DuelDetailBloc>().add(
                              WithdrawFromDuel(duelId: widget.duelId),
                            );
                        break;
                      case 'delete':
                        _showDeleteConfirmationDialog(context, state.duel);
                        break;
                    }
                  },
                  itemBuilder: (context) {
                    final items = <PopupMenuEntry<String>>[
                      const PopupMenuItem<String>(
                        value: 'refresh',
                        child: Row(
                          children: [
                            Icon(Icons.refresh),
                            SizedBox(width: 8),
                            Text('Refresh'),
                          ],
                        ),
                      ),
                    ];

                    // Add withdraw option if user can withdraw
                    if (_canUserWithdraw(state.duel, state.participants)) {
                      items.add(
                        const PopupMenuItem<String>(
                          value: 'withdraw',
                          child: Row(
                            children: [
                              Icon(Icons.exit_to_app, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Withdraw',
                                  style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                      );
                    }

                    // Add delete option if user can delete (creator only and duel hasn't started)
                    if (_canUserDeleteDuel(state.duel)) {
                      items.add(
                        const PopupMenuItem<String>(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Delete Duel',
                                  style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                      );
                    }

                    return items;
                  },
                );
              }
              return IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => context.read<DuelDetailBloc>().add(
                      RefreshDuelDetail(duelId: widget.duelId),
                    ),
              );
            },
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
          } else if (state is DuelWithdrawn) {
            StyledSnackBar.showSuccess(
              context: context,
              message: state.message,
            );
            // Navigate back to duels list after successful withdrawal
            Navigator.of(context).pushNamedAndRemoveUntil(
              '/home',
              (route) => false,
            );
          } else if (state is DuelWithdrawError) {
            StyledSnackBar.showError(
              context: context,
              message: state.message,
            );
          } else if (state is DuelDeleted) {
            StyledSnackBar.showSuccess(
              context: context,
              message: state.message,
            );
            // Navigate back to duels list after successful deletion
            Navigator.of(context).pushNamedAndRemoveUntil(
              '/home',
              (route) => false,
            );
          } else if (state is DuelDeleteError) {
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
    final participants = state.participants;

    // Sort participants by achievement percentage
    final sortedParticipants = List<DuelParticipant>.from(participants)
      ..sort((a, b) {
        final aProgress = (a.currentValue / duel.targetValue).clamp(0.0, 1.0);
        final bProgress = (b.currentValue / duel.targetValue).clamp(0.0, 1.0);

        if (aProgress == bProgress) {
          return b.currentValue.compareTo(a.currentValue);
        }

        return bProgress.compareTo(aProgress);
      });

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
                ? () {
                    HapticFeedback.vibrate();
                    context.read<DuelDetailBloc>().add(
                          JoinDuelFromDetail(duelId: widget.duelId),
                        );
                  }
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

          // Leaderboard Section Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surface,
            child: Text(
              'Leaderboard',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),

          // Leaderboard List
          ...sortedParticipants.asMap().entries.map((entry) {
            final index = entry.key;
            final participant = entry.value;
            final progress =
                (participant.currentValue / duel.targetValue).clamp(0.0, 1.0);
            final isCompleted = progress >= 1.0;
            final isWinner = participant.id == duel.winnerId;

            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: index == 0 ? 8 : 4,
              ),
              child: Card(
                elevation: isWinner ? 4 : 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: isWinner
                      ? BorderSide(color: Colors.amber, width: 2)
                      : BorderSide.none,
                ),
                child: Container(
                  decoration: isWinner
                      ? BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.amber.withOpacity(0.1),
                              Colors.orange.withOpacity(0.05),
                            ],
                          ),
                        )
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      participant.username,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: isWinner
                                            ? FontWeight.bold
                                            : FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  if (isWinner)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.amber,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Text(
                                        'WINNER',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              Text(
                                participant.role ?? 'Participant',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: LinearProgressIndicator(
                                      value: progress,
                                      backgroundColor: Colors.grey[200],
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        isCompleted
                                            ? Colors.green
                                            : Theme.of(context)
                                                .colorScheme
                                                .primary,
                                      ),
                                      minHeight: 6,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${(progress * 100).toInt()}%',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isCompleted
                                          ? Colors.green
                                          : Theme.of(context)
                                              .colorScheme
                                              .primary,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),

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
    // Allow manual start for both auto and manual mode duels (in case auto didn't trigger)
    final bool isCreator = _isUserCreator(duel);

    final bool canStart = isCreator && duel.status == DuelStatus.pending;

    // Also ensure there are enough participants
    if (canStart) {
      final state = context.read<DuelDetailBloc>().state;
      if (state is DuelDetailLoaded) {
        // Count accepted participants
        final acceptedParticipants = state.participants
            .where((p) => p.status == DuelParticipantStatus.accepted)
            .length;
        return acceptedParticipants >= duel.minParticipants;
      }
    }

    return false;
  }

  bool _canUserDeleteDuel(Duel duel) {
    // Only the creator can delete a duel
    // The duel must not have started yet
    return _isUserCreator(duel) && duel.status == DuelStatus.pending;
  }

  bool _canUserWithdraw(Duel duel, List<DuelParticipant> participants) {
    // User can only withdraw if:
    // 1. They are a participant (not the creator)
    // 2. The duel hasn't started yet (status is pending)
    // 3. They are in accepted status

    if (!_isUserParticipant(participants) || _isUserCreator(duel)) {
      return false;
    }

    if (duel.status != DuelStatus.pending) {
      return false;
    }

    final currentUserId = _getCurrentUserId();
    if (currentUserId == null) return false;

    final userParticipant = participants.firstWhere(
      (p) => p.userId == currentUserId,
      orElse: () =>
          throw StateError('User is participant but not found in list'),
    );

    return userParticipant.status == DuelParticipantStatus.accepted;
  }

  void _showDeleteConfirmationDialog(BuildContext context, Duel duel) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Duel'),
          content: const Text('Are you sure you want to delete this duel?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                context.read<DuelDetailBloc>().add(
                      DeleteDuel(duelId: duel.id),
                    );
                Navigator.of(context).pop();
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }
}
