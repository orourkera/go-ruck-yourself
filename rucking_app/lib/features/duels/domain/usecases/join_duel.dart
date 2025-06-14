import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/duels_repository.dart';

class JoinDuel implements UseCase<void, JoinDuelParams> {
  final DuelsRepository repository;

  JoinDuel(this.repository);

  @override
  Future<Either<Failure, void>> call(JoinDuelParams params) async {
    // First check if user already has an active or pending duel
    final userDuelsResult = await repository.getDuels(userParticipating: true);
    
    final hasActiveDuel = userDuelsResult.fold(
      (failure) => false, // If we can't fetch, allow join (server will handle)
      (duels) => duels.any((duel) => 
        (duel.status.name == 'active' || duel.status.name == 'pending') &&
        duel.status.name != 'cancelled'
      ),
    );
    
    if (hasActiveDuel) {
      return Left(ValidationFailure('You can only participate in one duel at a time. Please complete or withdraw from your current duel first.'));
    }

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
