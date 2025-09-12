import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/duel_comment.dart';
import '../repositories/duels_repository.dart';

class UpdateDuelComment
    implements UseCase<DuelComment, UpdateDuelCommentParams> {
  final DuelsRepository repository;

  UpdateDuelComment(this.repository);

  @override
  Future<Either<Failure, DuelComment>> call(
      UpdateDuelCommentParams params) async {
    return await repository.updateDuelComment(
        duelId: params.duelId,
        commentId: params.commentId,
        content: params.content);
  }
}

class UpdateDuelCommentParams {
  final String duelId;
  final String commentId;
  final String content;

  UpdateDuelCommentParams({
    required this.duelId,
    required this.commentId,
    required this.content,
  });
}
