import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:rucking_app/core/error/failures.dart';

/// Generic usecase interface
abstract class UseCase<Type, Params> {
  Future<Either<Failure, Type>> call(Params params);
}

/// No params required for this use case
class NoParams extends Equatable {
  @override
  List<Object> get props => [];
}
