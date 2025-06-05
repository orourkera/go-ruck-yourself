import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/duel_stats.dart';
import '../repositories/duels_repository.dart';

class GetUserDuelStats implements UseCase<DuelStats, GetUserDuelStatsParams> {
  final DuelsRepository repository;

  GetUserDuelStats(this.repository);

  @override
  Future<Either<Failure, DuelStats>> call(GetUserDuelStatsParams params) async {
    return await repository.getUserDuelStats(params.userId);
  }
}

class GetUserDuelStatsParams {
  final String? userId; // null means current user

  const GetUserDuelStatsParams({this.userId});
}
