import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/duel_comment.dart';
import '../repositories/duels_repository.dart';

class GetDuelComments implements UseCase<List<DuelComment>, GetDuelCommentsParams> {
  final DuelsRepository repository;

  GetDuelComments(this.repository);

  @override
  Future<Either<Failure, List<DuelComment>>> call(GetDuelCommentsParams params) async {
    return await repository.getDuelComments(params.duelId);
  }
}

class GetDuelCommentsParams {
  final String duelId;

  GetDuelCommentsParams({required this.duelId});
}
