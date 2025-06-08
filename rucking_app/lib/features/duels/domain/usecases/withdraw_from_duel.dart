import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/duels_repository.dart';

class WithdrawFromDuel implements UseCase<void, WithdrawFromDuelParams> {
  final DuelsRepository repository;

  WithdrawFromDuel(this.repository);

  @override
  Future<Either<Failure, void>> call(WithdrawFromDuelParams params) async {
    return await repository.withdrawFromDuel(params.duelId);
  }
}

class WithdrawFromDuelParams {
  final String duelId;

  WithdrawFromDuelParams({required this.duelId});
}
