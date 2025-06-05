import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/duels_repository.dart';

class DeleteDuelComment implements UseCase<void, DeleteDuelCommentParams> {
  final DuelsRepository repository;

  DeleteDuelComment(this.repository);

  @override
  Future<Either<Failure, void>> call(DeleteDuelCommentParams params) async {
    return await repository.deleteDuelComment(params.commentId);
  }
}

class DeleteDuelCommentParams {
  final String commentId;

  DeleteDuelCommentParams({required this.commentId});
}
