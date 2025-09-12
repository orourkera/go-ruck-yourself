import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/duel_participant.dart';
import '../repositories/duels_repository.dart';

class GetDuelLeaderboard
    implements UseCase<List<DuelParticipant>, GetDuelLeaderboardParams> {
  final DuelsRepository repository;

  GetDuelLeaderboard(this.repository);

  @override
  Future<Either<Failure, List<DuelParticipant>>> call(
      GetDuelLeaderboardParams params) async {
    return await repository.getDuelLeaderboard(params.duelId);
  }
}

class GetDuelLeaderboardParams {
  final String duelId;

  const GetDuelLeaderboardParams({required this.duelId});
}
