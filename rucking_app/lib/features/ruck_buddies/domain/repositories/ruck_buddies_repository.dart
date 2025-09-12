import 'package:dartz/dartz.dart';
import 'package:rucking_app/core/error/failures.dart';
import 'package:rucking_app/features/ruck_buddies/domain/entities/ruck_buddy.dart';

abstract class RuckBuddiesRepository {
  /// Get public ruck sessions from other users
  ///
  /// Filter types: 'recent', 'popular', 'distance', 'duration'
  ///
  /// Returns [Either] with a [Failure] or a list of [RuckBuddy] entities
  Future<Either<Failure, List<RuckBuddy>>> getRuckBuddies({
    required int limit,
    required int offset,
    required String filter,
    double? latitude,
    double? longitude,
  });
}
