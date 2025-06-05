import 'package:equatable/equatable.dart';
import '../../../domain/entities/duel.dart';

abstract class CreateDuelState extends Equatable {
  const CreateDuelState();

  @override
  List<Object?> get props => [];
}

class CreateDuelInitial extends CreateDuelState {}

class CreateDuelValidating extends CreateDuelState {}

class CreateDuelFormValid extends CreateDuelState {}

class CreateDuelFormInvalid extends CreateDuelState {
  final Map<String, String> errors;

  const CreateDuelFormInvalid({required this.errors});

  @override
  List<Object> get props => [errors];
}

class CreateDuelSubmitting extends CreateDuelState {}

class CreateDuelSuccess extends CreateDuelState {
  final Duel createdDuel;
  final String message;

  const CreateDuelSuccess({
    required this.createdDuel,
    this.message = 'Duel created successfully!',
  });

  @override
  List<Object> get props => [createdDuel, message];
}

class CreateDuelError extends CreateDuelState {
  final String message;

  const CreateDuelError({required this.message});

  @override
  List<Object> get props => [message];
}
