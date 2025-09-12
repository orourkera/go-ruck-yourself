import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:rucking_app/features/duels/domain/entities/duel.dart';
import 'package:rucking_app/features/duels/domain/entities/duel_participant.dart';
import 'package:rucking_app/features/duels/domain/repositories/duels_repository.dart';
import 'package:rucking_app/core/services/notification_service.dart';
import 'package:rucking_app/core/services/api_service.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

/// Service responsible for checking and handling duel completion logic
class DuelCompletionService {
  final DuelsRepository _duelsRepository;
  final NotificationService _notificationService;
  final ApiService _apiService;
  Timer? _completionCheckTimer;

  DuelCompletionService(
    this._duelsRepository,
    this._notificationService,
    this._apiService,
  );

  /// Start periodic checking for duel completion (every 30 seconds)
  void startCompletionChecking() {
    _completionCheckTimer?.cancel();
    _completionCheckTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkForCompletedDuels(),
    );
    AppLogger.info('Duel completion checking started');
  }

  /// Stop periodic checking
  void stopCompletionChecking() {
    _completionCheckTimer?.cancel();
    _completionCheckTimer = null;
    AppLogger.info('Duel completion checking stopped');
  }

  /// Check all active duels for completion
  Future<void> _checkForCompletedDuels() async {
    try {
      final result = await _apiService.checkDuelsForCompletion();

      result.fold(
        (failure) => AppLogger.error(
            'Failed to check duels for completion: ${failure.message}'),
        (duels) async {
          for (final duel in duels) {
            await _checkDuelForCompletion(duel);
          }
        },
      );
    } catch (e) {
      AppLogger.error('Error checking for completed duels: $e');
    }
  }

  /// Check a specific duel for completion
  Future<void> _checkDuelForCompletion(Duel duel) async {
    try {
      // Check if duel has ended by time
      final hasExpired = duel.hasEnded;

      // Get participants to check for early completion
      final leaderboardResult =
          await _duelsRepository.getDuelLeaderboard(duel.id);

      leaderboardResult.fold(
        (failure) => AppLogger.error(
            'Failed to get leaderboard for duel ${duel.id}: ${failure.message}'),
        (participants) async {
          final completionResult =
              _evaluateDuelCompletion(duel, participants, hasExpired);

          if (completionResult.shouldComplete) {
            await _completeDuel(
                duel, completionResult.winnerId, completionResult.reason);
          }
        },
      );
    } catch (e) {
      AppLogger.error('Error checking duel ${duel.id} for completion: $e');
    }
  }

  /// Evaluate if a duel should be completed and determine winner
  DuelCompletionResult _evaluateDuelCompletion(
    Duel duel,
    List<DuelParticipant> participants,
    bool hasExpired,
  ) {
    // Sort participants by progress (highest first)
    participants.sort((a, b) => b.currentValue.compareTo(a.currentValue));

    // Check for early completion (someone reached target)
    final targetReached =
        participants.any((p) => p.currentValue >= duel.targetValue);

    if (targetReached) {
      // Find winner - first person to reach target (by timestamp)
      final winners = participants
          .where((p) => p.currentValue >= duel.targetValue)
          .toList();

      // If multiple people reached target, winner is first to reach it
      // Note: This would require session timestamps to determine order
      final winner = winners.first;

      return DuelCompletionResult(
        shouldComplete: true,
        winnerId: winner.id,
        reason: DuelCompletionReason.targetReached,
      );
    }

    // Check if time has expired
    if (hasExpired) {
      if (participants.isEmpty || participants.first.currentValue == 0) {
        // No progress made by anyone
        return DuelCompletionResult(
          shouldComplete: true,
          winnerId: null,
          reason: DuelCompletionReason.timeExpiredNoWinner,
        );
      }

      // Time expired, winner is person with highest progress
      final winner = participants.first;
      final hasTie = participants.length > 1 &&
          participants[1].currentValue == winner.currentValue;

      return DuelCompletionResult(
        shouldComplete: true,
        winnerId: hasTie ? null : winner.id,
        reason: hasTie
            ? DuelCompletionReason.timeExpiredTie
            : DuelCompletionReason.timeExpiredWithWinner,
      );
    }

    return DuelCompletionResult(
      shouldComplete: false,
      winnerId: null,
      reason: DuelCompletionReason.stillActive,
    );
  }

  /// Complete a duel with the given winner
  Future<void> _completeDuel(
      Duel duel, String? winnerId, DuelCompletionReason reason) async {
    try {
      AppLogger.info(
          'Completing duel ${duel.id} with winner: $winnerId, reason: ${reason.name}');

      // Update duel status to completed
      final updateResult =
          await _apiService.completeDuel(duel.id, winnerId, reason);

      updateResult.fold(
        (failure) => AppLogger.error(
            'Failed to complete duel ${duel.id}: ${failure.message}'),
        (updatedDuel) async {
          // Send completion notifications
          await _sendCompletionNotifications(updatedDuel, reason);

          AppLogger.info('Successfully completed duel ${duel.id}');
        },
      );
    } catch (e) {
      AppLogger.error('Error completing duel ${duel.id}: $e');
    }
  }

  /// Send notifications when duel completes
  Future<void> _sendCompletionNotifications(
      Duel duel, DuelCompletionReason reason) async {
    try {
      String title;
      String body;

      switch (reason) {
        case DuelCompletionReason.targetReached:
          title = '🏆 Duel Completed!';
          body = 'Someone reached the target in "${duel.title}"';
          break;
        case DuelCompletionReason.timeExpiredWithWinner:
          title = '⏰ Duel Time Up!';
          body = 'Time\'s up for "${duel.title}" - we have a winner!';
          break;
        case DuelCompletionReason.timeExpiredTie:
          title = '⏰ Duel Time Up!';
          body = 'Time\'s up for "${duel.title}" - it\'s a tie!';
          break;
        case DuelCompletionReason.timeExpiredNoWinner:
          title = '⏰ Duel Time Up!';
          body =
              '${duel.title} has finished, but no one completed it. In this Duel there are no winners.';
          break;
        case DuelCompletionReason.stillActive:
          return; // No notification needed
      }

      // Get participants to send targeted notifications
      final leaderboardResult =
          await _duelsRepository.getDuelLeaderboard(duel.id);

      leaderboardResult.fold(
        (failure) => AppLogger.error(
            'Failed to get participants for notifications: ${failure.message}'),
        (participants) async {
          for (final participant in participants) {
            final isWinner = participant.id == duel.winnerId;
            final personalizedBody = isWinner
                ? 'Congratulations! You won "${duel.title}"! 🎉'
                : body;

            await _notificationService.sendLocalNotification(
              title: title,
              body: personalizedBody,
              data: {
                'type': 'duel_completed',
                'duel_id': duel.id,
                'is_winner': isWinner.toString(),
              },
            );
          }
        },
      );
    } catch (e) {
      AppLogger.error(
          'Error sending completion notifications for duel ${duel.id}: $e');
    }
  }

  /// Manually check and complete a specific duel (for testing or immediate completion)
  Future<void> checkDuelCompletion(String duelId) async {
    try {
      final duelResult = await _duelsRepository.getDuel(duelId);

      duelResult.fold(
        (failure) =>
            AppLogger.error('Failed to fetch duel $duelId: ${failure.message}'),
        (duel) async {
          if (duel.isActive) {
            await _checkDuelForCompletion(duel);
          }
        },
      );
    } catch (e) {
      AppLogger.error('Error manually checking duel $duelId: $e');
    }
  }

  void dispose() {
    stopCompletionChecking();
  }
}

/// Result of evaluating whether a duel should be completed
class DuelCompletionResult {
  final bool shouldComplete;
  final String? winnerId;
  final DuelCompletionReason reason;

  const DuelCompletionResult({
    required this.shouldComplete,
    required this.winnerId,
    required this.reason,
  });
}

/// Reasons why a duel might be completed
enum DuelCompletionReason {
  targetReached, // Someone reached the target value
  timeExpiredWithWinner, // Time ran out but there's a clear winner
  timeExpiredTie, // Time ran out with a tie
  timeExpiredNoWinner, // Time ran out with no progress
  stillActive, // Duel is still ongoing
}
