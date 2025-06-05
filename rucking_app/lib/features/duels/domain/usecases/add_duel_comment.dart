import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/duel_comment.dart';
import '../repositories/duels_repository.dart';

class AddDuelComment implements UseCase<DuelComment, AddDuelCommentParams> {
  final DuelsRepository repository;

  AddDuelComment(this.repository);

  @override
  Future<Either<Failure, DuelComment>> call(AddDuelCommentParams params) async {
    return await repository.addDuelComment(params.duelId, params.content);
  }
}

class AddDuelCommentParams {
  final String duelId;
  final String content;

  AddDuelCommentParams({
    required this.duelId,
    required this.content,
  });
}
