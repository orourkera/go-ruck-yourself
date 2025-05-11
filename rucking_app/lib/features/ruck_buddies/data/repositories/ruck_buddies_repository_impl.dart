import 'package:dartz/dartz.dart';
import 'package:rucking_app/core/error/exceptions.dart';
import 'package:rucking_app/core/error/failures.dart';
import 'package:rucking_app/features/ruck_buddies/data/datasources/ruck_buddies_remote_datasource.dart';
import 'package:rucking_app/features/ruck_buddies/domain/entities/ruck_buddy.dart';
import 'package:rucking_app/features/ruck_buddies/domain/repositories/ruck_buddies_repository.dart';

class RuckBuddiesRepositoryImpl implements RuckBuddiesRepository {
  final RuckBuddiesRemoteDataSource remoteDataSource;

  RuckBuddiesRepositoryImpl({
    required this.remoteDataSource,
  });

  @override
  Future<Either<Failure, List<RuckBuddy>>> getRuckBuddies({
    required int limit,
    required int offset,
    required String filter,
  }) async {
    try {
      final ruckBuddies = await remoteDataSource.getRuckBuddies(
        limit: limit,
        offset: offset,
        filter: filter,
      );
      // Model class extends entity, so this is safe
      return Right(ruckBuddies);
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } catch (e) {
      return Left(ServerFailure(message: 'Unexpected error occurred: ${e.toString()}'));
    }
  }
}
