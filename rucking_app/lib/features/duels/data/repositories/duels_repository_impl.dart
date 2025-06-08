import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/error/exceptions.dart';
import '../../domain/entities/duel.dart';
import '../../domain/entities/duel_participant.dart';
import '../../domain/entities/duel_stats.dart';
import '../../domain/entities/duel_invitation.dart';
import '../../domain/entities/duel_comment.dart';
import '../../domain/entities/duel_session.dart';
import '../../domain/repositories/duels_repository.dart';
import '../datasources/duels_remote_datasource.dart';
import '../models/duel_comment_model.dart';

class DuelsRepositoryImpl implements DuelsRepository {
  final DuelsRemoteDataSource remoteDataSource;

  DuelsRepositoryImpl({
    required this.remoteDataSource,
  });

  @override
  Future<Either<Failure, List<Duel>>> getDuels({
    String? status,
    String? challengeType,
    String? location,
    int? limit,
    bool? userParticipating,
  }) async {
    print('[DEBUG] DuelsRepositoryImpl.getDuels() - Starting with params: status=$status, challengeType=$challengeType, location=$location, limit=$limit, userParticipating=$userParticipating');
    
    try {
      print('[DEBUG] DuelsRepositoryImpl.getDuels() - Calling remoteDataSource.getDuels()');
      
      final duelModels = await remoteDataSource.getDuels(
        status: status,
        challengeType: challengeType,
        location: location,
        limit: limit,
        userParticipating: userParticipating,
      );
      
      print('[DEBUG] DuelsRepositoryImpl.getDuels() - Successfully got ${duelModels.length} duels from data source');
      return Right(duelModels);
    } on ServerException catch (e) {
      print('[ERROR] DuelsRepositoryImpl.getDuels() - ServerException: ${e.message}');
      return Left(ServerFailure(message: e.message));
    } catch (e, stackTrace) {
      print('[ERROR] DuelsRepositoryImpl.getDuels() - Unexpected exception: $e');
      print('[ERROR] DuelsRepositoryImpl.getDuels() - Stack trace: $stackTrace');
      return Left(ServerFailure(message: 'Unexpected error occurred'));
    }
  }

  @override
  Future<Either<Failure, Duel>> createDuel({
    required String title,
    required String challengeType,
    required double targetValue,
    required int timeframeHours,
    required int maxParticipants,
    required int minParticipants,
    required String startMode,
    required bool isPublic,
    List<String>? inviteeEmails,
  }) async {
    try {
      final duelModel = await remoteDataSource.createDuel(
        title: title,
        challengeType: challengeType,
        targetValue: targetValue,
        timeframeHours: timeframeHours,
        maxParticipants: maxParticipants,
        minParticipants: minParticipants,
        startMode: startMode,
        isPublic: isPublic,
        inviteeEmails: inviteeEmails,
      );
      return Right(duelModel);
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } catch (e) {
      return Left(ServerFailure(message: 'Failed to create duel'));
    }
  }

  @override
  Future<Either<Failure, Duel>> getDuel(String duelId) async {
    try {
      final duelModel = await remoteDataSource.getDuel(duelId);
      return Right(duelModel);
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } catch (e) {
      return Left(ServerFailure(message: 'Failed to fetch duel'));
    }
  }

  @override
  Future<Either<Failure, Duel>> updateDuel({
    required String duelId,
    String? title,
    String? description,
    String? status,
  }) async {
    try {
      final updates = <String, dynamic>{};
      if (title != null) updates['title'] = title;
      if (description != null) updates['description'] = description;
      if (status != null) updates['status'] = status;

      final duelModel = await remoteDataSource.updateDuel(duelId, updates);
      return Right(duelModel);
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } catch (e) {
      return Left(ServerFailure(message: 'Failed to update duel'));
    }
  }

  @override
  Future<Either<Failure, void>> joinDuel(String duelId) async {
    try {
      await remoteDataSource.joinDuel(duelId);
      return const Right(null);
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } catch (e) {
      return Left(ServerFailure(message: 'Failed to join duel'));
    }
  }

  @override
  Future<Either<Failure, void>> updateParticipantStatus({
    required String duelId,
    required String participantId,
    required String status,
  }) async {
    try {
      await remoteDataSource.updateParticipantStatus(duelId, participantId, status);
      return const Right(null);
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } catch (e) {
      return Left(ServerFailure(message: 'Failed to update participant status'));
    }
  }

  @override
  Future<Either<Failure, void>> updateParticipantProgress({
    required String duelId,
    required String participantId,
    required String sessionId,
    required double contributionValue,
  }) async {
    try {
      await remoteDataSource.updateParticipantProgress(
        duelId,
        participantId,
        sessionId,
        contributionValue,
      );
      return const Right(null);
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } catch (e) {
      return Left(ServerFailure(message: 'Failed to update progress'));
    }
  }

  @override
  Future<Either<Failure, DuelParticipant>> getParticipantProgress({
    required String duelId,
    required String participantId,
  }) async {
    try {
      final participantModel = await remoteDataSource.getParticipantProgress(duelId, participantId);
      return Right(participantModel);
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } catch (e) {
      return Left(ServerFailure(message: 'Failed to fetch participant progress'));
    }
  }

  @override
  Future<Either<Failure, List<DuelParticipant>>> getDuelLeaderboard(String duelId) async {
    try {
      final participantModels = await remoteDataSource.getDuelLeaderboard(duelId);
      return Right(participantModels);
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } catch (e) {
      return Left(ServerFailure(message: 'Failed to fetch leaderboard'));
    }
  }

  @override
  Future<Either<Failure, DuelStats>> getUserDuelStats([String? userId]) async {
    try {
      final statsModel = await remoteDataSource.getUserDuelStats(userId);
      return Right(statsModel);
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } catch (e) {
      return Left(ServerFailure(message: 'Failed to fetch duel stats'));
    }
  }

  @override
  Future<Either<Failure, List<DuelStats>>> getDuelStatsLeaderboard({
    String statType = 'wins',
    int limit = 50,
  }) async {
    try {
      final statsModels = await remoteDataSource.getDuelStatsLeaderboard(statType, limit);
      return Right(statsModels);
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } catch (e) {
      return Left(ServerFailure(message: 'Failed to fetch stats leaderboard'));
    }
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> getDuelAnalytics({
    int days = 30,
  }) async {
    try {
      final analytics = await remoteDataSource.getDuelAnalytics(days);
      return Right(analytics);
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } catch (e) {
      return Left(ServerFailure(message: 'Failed to fetch analytics'));
    }
  }

  @override
  Future<Either<Failure, List<DuelInvitation>>> getDuelInvitations({
    String status = 'pending',
  }) async {
    try {
      final invitationModels = await remoteDataSource.getDuelInvitations(status);
      return Right(invitationModels);
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } catch (e) {
      return Left(ServerFailure(message: 'Failed to fetch invitations'));
    }
  }

  @override
  Future<Either<Failure, void>> respondToInvitation({
    required String invitationId,
    required String action,
  }) async {
    try {
      await remoteDataSource.respondToInvitation(invitationId, action);
      return const Right(null);
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } catch (e) {
      return Left(ServerFailure(message: 'Failed to respond to invitation'));
    }
  }

  @override
  Future<Either<Failure, void>> cancelInvitation(String invitationId) async {
    try {
      await remoteDataSource.cancelInvitation(invitationId);
      return const Right(null);
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } catch (e) {
      return Left(ServerFailure(message: 'Failed to cancel invitation'));
    }
  }

  @override
  Future<Either<Failure, List<DuelInvitation>>> getSentInvitations() async {
    try {
      final invitationModels = await remoteDataSource.getSentInvitations();
      return Right(invitationModels);
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } catch (e) {
      return Left(ServerFailure(message: 'Failed to fetch sent invitations'));
    }
  }

  @override
  Future<Either<Failure, List<DuelComment>>> getDuelComments(String duelId) async {
    try {
      final commentModels = await remoteDataSource.getDuelComments(duelId);
      return Right(commentModels);
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } catch (e) {
      return Left(ServerFailure(message: 'Failed to fetch comments'));
    }
  }

  @override
  Future<Either<Failure, DuelComment>> addDuelComment({
    required String duelId,
    required String content,
  }) async {
    try {
      final commentModel = await remoteDataSource.createDuelComment(duelId, content);
      return Right(commentModel);
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } catch (e) {
      return Left(ServerFailure(message: 'Failed to create comment'));
    }
  }

  @override
  Future<Either<Failure, DuelComment>> updateDuelComment({
    required String commentId,
    required String content,
  }) async {
    try {
      // Note: We need to get the duelId somehow - this may need to be passed differently
      // For now, we'll assume the commentId contains enough info or modify the interface later
      await remoteDataSource.updateDuelComment('', commentId, content);
      
      // Since the remote data source returns void, we need to return a placeholder comment
      // In a real implementation, you'd want to fetch the updated comment or modify the data source
      final updatedComment = DuelCommentModel(
        id: commentId,
        duelId: '', // Placeholder - in real implementation would need actual duel ID
        userId: '',
        content: content,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        userDisplayName: '',
        userAvatarUrl: null,
      );
      return Right(updatedComment);
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } catch (e) {
      return Left(ServerFailure(message: 'Failed to update comment'));
    }
  }

  @override
  Future<Either<Failure, void>> deleteDuelComment({
    required String commentId,
  }) async {
    try {
      // Note: We need to get the duelId somehow - this may need to be passed differently
      await remoteDataSource.deleteDuelComment('', commentId);
      return const Right(null);
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } catch (e) {
      return Left(ServerFailure(message: 'Failed to delete comment'));
    }
  }

  @override
  Future<Either<Failure, void>> startDuel({
    required String duelId,
  }) async {
    try {
      await remoteDataSource.startDuel(duelId);
      return const Right(null);
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } catch (e) {
      return Left(ServerFailure(message: 'Failed to start duel'));
    }
  }

  @override
  Future<Either<Failure, void>> withdrawFromDuel(String duelId) async {
    try {
      // TODO: Implement actual withdraw functionality in remote data source
      // For now, return success - this would need to be implemented in the backend
      await Future.delayed(const Duration(milliseconds: 500)); // Simulate network call
      return const Right(null);
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } catch (e) {
      return Left(ServerFailure(message: 'Failed to withdraw from duel'));
    }
  }

  @override
  Future<Either<Failure, List<DuelSession>>> getDuelSessions(String duelId) async {
    try {
      // TODO: Implement actual duel sessions functionality in remote data source
      // For now, return empty list - this would need to be implemented in the backend
      await Future.delayed(const Duration(milliseconds: 300)); // Simulate network call
      return const Right([]);
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } catch (e) {
      return Left(ServerFailure(message: 'Failed to fetch duel sessions'));
    }
  }
}
