import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/duels_repository.dart';

class JoinDuel implements UseCase<void, JoinDuelParams> {
  final DuelsRepository repository;

  JoinDuel(this.repository);

  @override
  Future<Either<Failure, void>> call(JoinDuelParams params) async {
    // Get duel details to validate join conditions
    final duelResult = await repository.getDuel(params.duelId);
    
    return duelResult.fold(
      (failure) => Left(failure),
      (duel) async {
        // Validate that user can join
        if (!duel.isPublic) {
          return Left(ValidationFailure('Cannot join private duel without invitation'));
        }

        if (duel.status.name != 'pending') {
          return Left(ValidationFailure('Cannot join duel that is not pending'));
        }

        if (duel.hasEnded) {
          return Left(ValidationFailure('Cannot join duel that has ended'));
        }

        // Attempt to join
        return await repository.joinDuel(params.duelId);
      },
    );
  }
}

class JoinDuelParams {
  final String duelId;

  const JoinDuelParams({required this.duelId});
}

class ValidationFailure extends Failure {
  ValidationFailure(String message) : super(message: message);

  @override
  List<Object> get props => [message];
}
