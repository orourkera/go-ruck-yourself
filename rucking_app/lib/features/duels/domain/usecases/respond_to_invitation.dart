import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/duels_repository.dart';

class RespondToInvitation implements UseCase<void, RespondToInvitationParams> {
  final DuelsRepository repository;

  RespondToInvitation(this.repository);

  @override
  Future<Either<Failure, void>> call(RespondToInvitationParams params) async {
    // Validate action
    if (params.action != 'accept' && params.action != 'decline') {
      return Left(ValidationFailure('Invalid action. Must be "accept" or "decline"'));
    }

    return await repository.respondToInvitation(
      invitationId: params.invitationId,
      action: params.action,
    );
  }
}

class RespondToInvitationParams {
  final String invitationId;
  final String action; // 'accept' or 'decline'

  const RespondToInvitationParams({
    required this.invitationId,
    required this.action,
  });
}

class ValidationFailure extends Failure {
  ValidationFailure(String message) : super(message: message);

  @override
  List<Object> get props => [message];
}
