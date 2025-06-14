import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/duels_repository.dart';

class DeleteDuel implements UseCase<void, DeleteDuelParams> {
  final DuelsRepository repository;

  DeleteDuel(this.repository);

  @override
  Future<Either<Failure, void>> call(DeleteDuelParams params) async {
    return await repository.deleteDuel(params.duelId);
  }
}

class DeleteDuelParams {
  final String duelId;

  DeleteDuelParams({required this.duelId});
}
