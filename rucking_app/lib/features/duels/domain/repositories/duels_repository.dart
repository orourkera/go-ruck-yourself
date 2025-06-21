import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../entities/duel.dart';
import '../entities/duel_participant.dart';
import '../entities/duel_stats.dart';
import '../entities/duel_invitation.dart';
import '../entities/duel_comment.dart';
import '../entities/duel_session.dart';

abstract class DuelsRepository {
  // Duel management
  Future<Either<Failure, List<Duel>>> getDuels({
    String? status,
    String? challengeType,
    String? location,
    int? limit,
    bool? userParticipating, // true for "My Duels", false for "Discover", null for all
  });

  Future<Either<Failure, Duel>> createDuel({
    required String title,
    required String challengeType,
    required double targetValue,
    required int timeframeHours,
    required int maxParticipants,
    required int minParticipants,
    required String startMode,
    required bool isPublic,
    // String? description, // Removed - not supported by backend yet
    // String? creatorCity, // Removed - backend uses user profile location
    // String? creatorState, // Removed - backend uses user profile location
    List<String>? inviteeEmails,
  });

  Future<Either<Failure, Duel>> getDuel(String duelId);

  Future<Either<Failure, Duel>> updateDuel({
    required String duelId,
    String? title,
    String? description,
    String? status,
  });

  Future<Either<Failure, void>> deleteDuel(String duelId);

  Future<Either<Failure, void>> joinDuel(String duelId);

  // Participant management
  Future<Either<Failure, void>> updateParticipantStatus({
    required String duelId,
    required String participantId,
    required String status,
  });

  Future<Either<Failure, void>> withdrawFromDuel(String duelId);

  Future<Either<Failure, void>> updateParticipantProgress({
    required String duelId,
    required String participantId,
    required String sessionId,
    required double contributionValue,
  });

  Future<Either<Failure, DuelParticipant>> getParticipantProgress({
    required String duelId,
    required String participantId,
  });

  Future<Either<Failure, List<DuelParticipant>>> getDuelLeaderboard(String duelId);

  // Statistics
  Future<Either<Failure, DuelStats>> getUserDuelStats([String? userId]);

  Future<Either<Failure, List<DuelStats>>> getDuelStatsLeaderboard({
    String statType = 'wins',
    int limit = 50,
  });

  Future<Either<Failure, Map<String, dynamic>>> getDuelAnalytics({
    int days = 30,
  });

  // Invitations
  Future<Either<Failure, List<DuelInvitation>>> getDuelInvitations({
    String status = 'pending',
  });

  Future<Either<Failure, void>> respondToInvitation({
    required String invitationId,
    required String action, // 'accept' or 'decline'
  });

  Future<Either<Failure, void>> cancelInvitation(String invitationId);

  Future<Either<Failure, List<DuelInvitation>>> getSentInvitations();

  // Comments
  Future<Either<Failure, List<DuelComment>>> getDuelComments(String duelId);

  Future<Either<Failure, DuelComment>> addDuelComment({
    required String duelId,
    required String content,
  });

  Future<Either<Failure, DuelComment>> updateDuelComment({
    required String duelId,
    required String commentId,
    required String content,
  });

  Future<Either<Failure, void>> deleteDuelComment({
    required String duelId,
    required String commentId,
  });
  
  // Sessions
  Future<Either<Failure, List<DuelSession>>> getDuelSessions(String duelId);
  
  // Manual duel start
  Future<Either<Failure, void>> startDuel({
    required String duelId,
  });
}
