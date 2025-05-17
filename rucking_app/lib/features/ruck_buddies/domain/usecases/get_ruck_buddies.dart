import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:rucking_app/core/error/failures.dart';
import 'package:rucking_app/core/usecases/usecase.dart';
import 'package:rucking_app/features/ruck_buddies/domain/entities/ruck_buddy.dart';
import 'package:rucking_app/features/ruck_buddies/domain/repositories/ruck_buddies_repository.dart';

class GetRuckBuddies implements UseCase<List<RuckBuddy>, RuckBuddiesParams> {
  final RuckBuddiesRepository repository;

  GetRuckBuddies(this.repository);

  @override
  Future<Either<Failure, List<RuckBuddy>>> call(RuckBuddiesParams params) {
    return repository.getRuckBuddies(
      limit: params.limit,
      offset: params.offset,
      filter: params.filter,
      latitude: params.latitude,
      longitude: params.longitude,
    );
  }
}

class RuckBuddiesParams extends Equatable {
  final int limit;
  final int offset;
  final String filter;
  final double? latitude;
  final double? longitude;

  const RuckBuddiesParams({
    this.limit = 20,
    this.offset = 0,
    this.filter = 'closest',
    this.latitude,
    this.longitude,
  });

  @override
  List<Object?> get props => [limit, offset, filter, latitude, longitude];
}
