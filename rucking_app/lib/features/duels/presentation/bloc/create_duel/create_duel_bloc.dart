import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/usecases/create_duel.dart';
import 'create_duel_event.dart';
import 'create_duel_state.dart';

class CreateDuelBloc extends Bloc<CreateDuelEvent, CreateDuelState> {
  final CreateDuel createDuel;

  CreateDuelBloc({
    required this.createDuel,
  }) : super(CreateDuelInitial()) {
    on<CreateDuelSubmitted>(_onCreateDuelSubmitted);
    on<ResetCreateDuel>(_onResetCreateDuel);
    on<ValidateCreateDuelForm>(_onValidateCreateDuelForm);
  }

  void _onCreateDuelSubmitted(CreateDuelSubmitted event, Emitter<CreateDuelState> emit) async {
    emit(CreateDuelSubmitting());

    final result = await createDuel(CreateDuelParams(
      title: event.title,
      challengeType: event.challengeType,
      targetValue: event.targetValue,
      timeframeHours: event.timeframeHours,
      maxParticipants: event.maxParticipants,
      minParticipants: event.minParticipants,
      startMode: event.startMode,
      isPublic: event.isPublic,
      // description: event.description, // Removed - not supported by backend yet
      // creatorCity: event.creatorCity, // Removed - backend uses user profile location
      // creatorState: event.creatorState, // Removed - backend uses user profile location
      inviteeEmails: event.inviteeEmails,
    ));

    result.fold(
      (failure) => emit(CreateDuelError(message: failure.message)),
      (duel) => emit(CreateDuelSuccess(createdDuel: duel)),
    );
  }

  void _onResetCreateDuel(ResetCreateDuel event, Emitter<CreateDuelState> emit) {
    emit(CreateDuelInitial());
  }

  void _onValidateCreateDuelForm(ValidateCreateDuelForm event, Emitter<CreateDuelState> emit) {
    emit(CreateDuelValidating());

    final errors = <String, String>{};

    // Validate title
    if (event.title.trim().isEmpty) {
      errors['title'] = 'Title is required';
    } else if (event.title.trim().length < 3) {
      errors['title'] = 'Title must be at least 3 characters';
    } else if (event.title.trim().length > 100) {
      errors['title'] = 'Title must be less than 100 characters';
    }

    // Validate challenge type
    final validChallengeTypes = ['distance', 'time', 'elevation', 'power_points'];
    if (!validChallengeTypes.contains(event.challengeType)) {
      errors['challengeType'] = 'Invalid challenge type';
    }

    // Validate target value
    if (event.targetValue <= 0) {
      errors['targetValue'] = 'Target value must be greater than 0';
    } else if (event.targetValue > 1000000) {
      errors['targetValue'] = 'Target value is too large';
    }

    // Validate timeframe
    if (event.timeframeHours <= 0) {
      errors['timeframeHours'] = 'Timeframe must be greater than 0';
    } else if (event.timeframeHours > 24 * 30) {
      errors['timeframeHours'] = 'Timeframe cannot exceed 30 days';
    }

    // Validate max participants
    if (event.maxParticipants < 2) {
      errors['maxParticipants'] = 'At least 2 participants required';
    } else if (event.maxParticipants > 50) {
      errors['maxParticipants'] = 'Maximum 50 participants allowed';
    }
    
    // Validate min participants
    if (event.minParticipants < 2) {
      errors['minParticipants'] = 'At least 2 participants required';
    } else if (event.minParticipants > event.maxParticipants) {
      errors['minParticipants'] = 'Cannot exceed maximum participants';
    }
    
    // Validate start mode
    final validStartModes = ['auto', 'manual'];
    if (!validStartModes.contains(event.startMode)) {
      errors['startMode'] = 'Invalid start mode';
    }

    // Validate email formats if provided
    if (event.inviteeEmails != null && event.inviteeEmails!.isNotEmpty) {
      final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
      for (int i = 0; i < event.inviteeEmails!.length; i++) {
        final email = event.inviteeEmails![i].trim();
        if (email.isNotEmpty && !emailRegex.hasMatch(email)) {
          errors['inviteeEmails'] = 'Invalid email format: $email';
          break;
        }
      }
    }

    if (errors.isEmpty) {
      emit(CreateDuelFormValid());
    } else {
      emit(CreateDuelFormInvalid(errors: errors));
    }
  }
}
