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
  final int minParticipants;
  final String startMode;
  final bool isPublic;
  // final String? description; // Removed - not supported by backend yet
  // final String? creatorCity; // Removed - backend uses user profile location
  // final String? creatorState; // Removed - backend uses user profile location
  final List<String>? inviteeEmails;

  const CreateDuelSubmitted({
    required this.title,
    required this.challengeType,
    required this.targetValue,
    required this.timeframeHours,
    required this.maxParticipants,
    required this.minParticipants,
    required this.startMode,
    required this.isPublic,
    // this.description, // Removed - not supported by backend yet
    // this.creatorCity, // Removed - backend uses user profile location
    // this.creatorState, // Removed - backend uses user profile location
    this.inviteeEmails,
  });

  @override
  List<Object?> get props => [
        title,
        challengeType,
        targetValue,
        timeframeHours,
        maxParticipants,
        minParticipants,
        startMode,
        isPublic,
        // description, // Removed - not supported by backend yet
        // creatorCity, // Removed - backend uses user profile location
        // creatorState, // Removed - backend uses user profile location
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
  final int minParticipants;
  final String startMode;
  final List<String>? inviteeEmails;

  const ValidateCreateDuelForm({
    required this.title,
    required this.challengeType,
    required this.targetValue,
    required this.timeframeHours,
    required this.maxParticipants,
    required this.minParticipants,
    required this.startMode,
    this.inviteeEmails,
  });

  @override
  List<Object?> get props => [
        title,
        challengeType,
        targetValue,
        timeframeHours,
        maxParticipants,
        minParticipants,
        startMode,
        inviteeEmails,
      ];
}
