import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/duels_repository.dart';

class UpdateDuelProgress implements UseCase<void, UpdateDuelProgressParams> {
  final DuelsRepository repository;

  UpdateDuelProgress(this.repository);

  @override
  Future<Either<Failure, void>> call(UpdateDuelProgressParams params) async {
    // Validate parameters
    if (params.contributionValue < 0) {
      return Left(ValidationFailure('Contribution value cannot be negative'));
    }

    if (params.sessionId.trim().isEmpty) {
      return Left(ValidationFailure('Session ID cannot be empty'));
    }

    return await repository.updateParticipantProgress(
      duelId: params.duelId,
      participantId: params.participantId,
      sessionId: params.sessionId.trim(),
      contributionValue: params.contributionValue,
    );
  }
}

class UpdateDuelProgressParams {
  final String duelId;
  final String participantId;
  final String sessionId;
  final double contributionValue;

  const UpdateDuelProgressParams({
    required this.duelId,
    required this.participantId,
    required this.sessionId,
    required this.contributionValue,
  });
}

class ValidationFailure extends Failure {
  ValidationFailure(String message) : super(message: message);

  @override
  List<Object> get props => [message];
}
