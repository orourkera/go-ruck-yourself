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
    // First check if user already has an active or pending duel
    final userDuelsResult = await repository.getDuels(userParticipating: true);

    final hasActiveDuel = userDuelsResult.fold(
      (failure) =>
          false, // If we can't fetch, allow create (server will handle)
      (duels) => duels.any((duel) =>
          (duel.status.name == 'active' || duel.status.name == 'pending') &&
          duel.status.name != 'cancelled'),
    );

    if (hasActiveDuel) {
      return Left(ValidationFailure(
          'You can only participate in one duel at a time. Please complete or withdraw from your current duel first.'));
    }

    // Validate parameters
    if (params.title.trim().isEmpty) {
      return Left(ValidationFailure('Duel title cannot be empty'));
    }

    if (params.targetValue <= 0) {
      return Left(ValidationFailure('Target value must be greater than 0'));
    }

    if (params.timeframeHours <= 0 || params.timeframeHours > 24 * 30) {
      return Left(
          ValidationFailure('Timeframe must be between 1 hour and 30 days'));
    }

    if (params.maxParticipants < 2 || params.maxParticipants > 50) {
      return Left(
          ValidationFailure('Max participants must be between 2 and 50'));
    }

    // Validate min participants
    if (params.minParticipants < 2) {
      return Left(ValidationFailure('Minimum participants must be at least 2'));
    }
    if (params.minParticipants > params.maxParticipants) {
      return Left(ValidationFailure(
          'Minimum participants cannot exceed maximum participants'));
    }

    // Validate start mode
    final validStartModes = ['auto', 'manual'];
    if (!validStartModes.contains(params.startMode)) {
      return Left(ValidationFailure('Invalid start mode'));
    }

    // Validate challenge type
    final validChallengeTypes = [
      'distance',
      'time',
      'elevation',
      'power_points'
    ];
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
      minParticipants: params.minParticipants,
      startMode: params.startMode,
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
  final int minParticipants;
  final String startMode;
  final bool isPublic;
  final List<String>? inviteeEmails;

  const CreateDuelParams({
    required this.title,
    required this.challengeType,
    required this.targetValue,
    required this.timeframeHours,
    required this.maxParticipants,
    required this.minParticipants,
    required this.startMode,
    required this.isPublic,
    this.inviteeEmails,
  });
}

class ValidationFailure extends Failure {
  ValidationFailure(String message) : super(message: message);

  @override
  List<Object> get props => [message];
}
