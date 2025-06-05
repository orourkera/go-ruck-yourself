import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/duel.dart';
import '../repositories/duels_repository.dart';

class GetDuels implements UseCase<List<Duel>, GetDuelsParams> {
  final DuelsRepository repository;

  GetDuels(this.repository);

  @override
  Future<Either<Failure, List<Duel>>> call(GetDuelsParams params) async {
    return await repository.getDuels(
      status: params.status,
      challengeType: params.challengeType,
      location: params.location,
      limit: params.limit,
    );
  }
}

class GetDuelsParams {
  final String? status;
  final String? challengeType;
  final String? location;
  final int? limit;

  const GetDuelsParams({
    this.status,
    this.challengeType,
    this.location,
    this.limit,
  });
}
