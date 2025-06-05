import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/duel.dart';
import '../repositories/duels_repository.dart';

class GetDuelDetails implements UseCase<Duel, GetDuelDetailsParams> {
  final DuelsRepository repository;

  GetDuelDetails(this.repository);

  @override
  Future<Either<Failure, Duel>> call(GetDuelDetailsParams params) async {
    if (params.duelId.trim().isEmpty) {
      return Left(ValidationFailure('Duel ID cannot be empty'));
    }

    return await repository.getDuel(params.duelId.trim());
  }
}

class GetDuelDetailsParams {
  final String duelId;

  const GetDuelDetailsParams({required this.duelId});
}

class ValidationFailure extends Failure {
  ValidationFailure(String message) : super(message: message);
}
