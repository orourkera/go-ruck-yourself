import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/duels_repository.dart';

class StartDuel implements UseCase<void, StartDuelParams> {
  final DuelsRepository repository;

  StartDuel(this.repository);

  @override
  Future<Either<Failure, void>> call(StartDuelParams params) async {
    return repository.startDuel(
      duelId: params.duelId,
    );
  }
}

class StartDuelParams extends Equatable {
  final String duelId;

  const StartDuelParams({
    required this.duelId,
  });

  @override
  List<Object?> get props => [duelId];
}
