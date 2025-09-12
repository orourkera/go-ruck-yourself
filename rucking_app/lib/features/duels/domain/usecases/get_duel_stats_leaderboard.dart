import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/duel_stats.dart';
import '../repositories/duels_repository.dart';

class GetDuelStatsLeaderboard
    implements UseCase<List<DuelStats>, GetDuelStatsLeaderboardParams> {
  final DuelsRepository repository;

  GetDuelStatsLeaderboard(this.repository);

  @override
  Future<Either<Failure, List<DuelStats>>> call(
      GetDuelStatsLeaderboardParams params) async {
    // Validate stat type
    final validStatTypes = ['wins', 'completion_rate', 'total_duels'];
    if (!validStatTypes.contains(params.statType)) {
      return Left(ValidationFailure(
          'Invalid stat type. Must be one of: ${validStatTypes.join(', ')}'));
    }

    // Validate limit
    if (params.limit <= 0 || params.limit > 100) {
      return Left(ValidationFailure('Limit must be between 1 and 100'));
    }

    return await repository.getDuelStatsLeaderboard(
      statType: params.statType,
      limit: params.limit,
    );
  }
}

class GetDuelStatsLeaderboardParams {
  final String statType;
  final int limit;

  const GetDuelStatsLeaderboardParams({
    this.statType = 'wins',
    this.limit = 50,
  });
}

class ValidationFailure extends Failure {
  ValidationFailure(String message) : super(message: message);
}
