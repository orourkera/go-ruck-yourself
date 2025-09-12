import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/duel_invitation.dart';
import '../repositories/duels_repository.dart';

class GetDuelInvitations
    implements UseCase<List<DuelInvitation>, GetDuelInvitationsParams> {
  final DuelsRepository repository;

  GetDuelInvitations(this.repository);

  @override
  Future<Either<Failure, List<DuelInvitation>>> call(
      GetDuelInvitationsParams params) async {
    return await repository.getDuelInvitations(status: params.status);
  }
}

class GetDuelInvitationsParams {
  final String status;

  const GetDuelInvitationsParams({this.status = 'pending'});
}
