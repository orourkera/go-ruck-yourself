import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/duel_session.dart';
import '../repositories/duels_repository.dart';

class GetDuelSessions
    implements UseCase<List<DuelSession>, GetDuelSessionsParams> {
  final DuelsRepository repository;

  GetDuelSessions(this.repository);

  @override
  Future<Either<Failure, List<DuelSession>>> call(
      GetDuelSessionsParams params) async {
    return await repository.getDuelSessions(params.duelId);
  }
}

class GetDuelSessionsParams {
  final String duelId;

  GetDuelSessionsParams({required this.duelId});
}
