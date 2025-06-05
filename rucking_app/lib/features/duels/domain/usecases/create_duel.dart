import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/duel.dart';
import '../repositories/duels_repository.dart';

class CreateDuel implements UseCase<Duel, CreateDuelParams> {
  final DuelsRepository repository;

  CreateDuel(this.repository);

  @override
  Future<Either<Failure, Duel>> call(CreateDuelParams params) async {
    // Validate parameters
    if (params.title.trim().isEmpty) {
      return Left(ValidationFailure('Duel title cannot be empty'));
    }

    if (params.targetValue <= 0) {
      return Left(ValidationFailure('Target value must be greater than 0'));
    }

    if (params.timeframeHours <= 0 || params.timeframeHours > 24 * 30) {
      return Left(ValidationFailure('Timeframe must be between 1 hour and 30 days'));
    }

    if (params.maxParticipants < 2 || params.maxParticipants > 50) {
      return Left(ValidationFailure('Max participants must be between 2 and 50'));
    }

    // Validate challenge type
    final validChallengeTypes = ['distance', 'time', 'elevation', 'power_points'];
    if (!validChallengeTypes.contains(params.challengeType)) {
      return Left(ValidationFailure('Invalid challenge type'));
    }

    // Validate email formats if provided
    if (params.inviteeEmails != null) {
      for (final email in params.inviteeEmails!) {
        if (!_isValidEmail(email)) {
          return Left(ValidationFailure('Invalid email format: $email'));
        }
      }
    }

    return await repository.createDuel(
      title: params.title.trim(),
      challengeType: params.challengeType,
      targetValue: params.targetValue,
      timeframeHours: params.timeframeHours,
      maxParticipants: params.maxParticipants,
      isPublic: params.isPublic,
      inviteeEmails: params.inviteeEmails,
    );
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }
}

class CreateDuelParams {
  final String title;
  final String challengeType;
  final double targetValue;
  final int timeframeHours;
  final int maxParticipants;
  final bool isPublic;
  final List<String>? inviteeEmails;

  const CreateDuelParams({
    required this.title,
    required this.challengeType,
    required this.targetValue,
    required this.timeframeHours,
    required this.maxParticipants,
    required this.isPublic,
    this.inviteeEmails,
  });
}

class ValidationFailure extends Failure {
  ValidationFailure(String message) : super(message: message);

  @override
  List<Object> get props => [message];
}
