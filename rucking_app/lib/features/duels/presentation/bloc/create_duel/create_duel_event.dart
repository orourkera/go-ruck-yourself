import 'package:equatable/equatable.dart';

abstract class CreateDuelEvent extends Equatable {
  const CreateDuelEvent();

  @override
  List<Object?> get props => [];
}

class CreateDuelSubmitted extends CreateDuelEvent {
  final String title;
  final String challengeType;
  final double targetValue;
  final int timeframeHours;
  final int maxParticipants;
  final bool isPublic;
  final String? description;
  final String? creatorCity;
  final String? creatorState;
  final List<String>? inviteeEmails;

  const CreateDuelSubmitted({
    required this.title,
    required this.challengeType,
    required this.targetValue,
    required this.timeframeHours,
    required this.maxParticipants,
    required this.isPublic,
    this.description,
    this.creatorCity,
    this.creatorState,
    this.inviteeEmails,
  });

  @override
  List<Object?> get props => [
        title,
        challengeType,
        targetValue,
        timeframeHours,
        maxParticipants,
        isPublic,
        description,
        creatorCity,
        creatorState,
        inviteeEmails,
      ];
}

class ResetCreateDuel extends CreateDuelEvent {}

class ValidateCreateDuelForm extends CreateDuelEvent {
  final String title;
  final String challengeType;
  final double targetValue;
  final int timeframeHours;
  final int maxParticipants;
  final List<String>? inviteeEmails;

  const ValidateCreateDuelForm({
    required this.title,
    required this.challengeType,
    required this.targetValue,
    required this.timeframeHours,
    required this.maxParticipants,
    this.inviteeEmails,
  });

  @override
  List<Object?> get props => [
        title,
        challengeType,
        targetValue,
        timeframeHours,
        maxParticipants,
        inviteeEmails,
      ];
}
