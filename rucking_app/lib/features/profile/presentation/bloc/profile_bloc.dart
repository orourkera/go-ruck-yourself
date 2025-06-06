import 'dart:io';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:rucking_app/core/models/user.dart';
import 'package:rucking_app/core/services/avatar_service.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';

part 'profile_event.dart';
part 'profile_state.dart';

class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  final AvatarService _avatarService;
  final AuthBloc _authBloc;

  ProfileBloc({
    required AvatarService avatarService,
    required AuthBloc authBloc,
  })  : _avatarService = avatarService,
        _authBloc = authBloc,
        super(ProfileInitial()) {
    on<UploadAvatar>(_onUploadAvatar);
  }

  Future<void> _onUploadAvatar(
    UploadAvatar event,
    Emitter<ProfileState> emit,
  ) async {
    emit(AvatarUploading());
    
    try {
      // Upload the avatar
      final avatarUrl = await _avatarService.uploadAvatar(event.imageFile);
      
      // Get the current user
      final currentState = _authBloc.state;
      if (currentState is AuthAuthenticated && currentState.user != null) {
        // Update the user with the new avatar URL
        final updatedUser = currentState.user!.copyWith(avatarUrl: avatarUrl);
        
        // Trigger auth bloc to update the user
        _authBloc.add(AuthUpdateProfileRequested(avatarUrl: avatarUrl));
        
        emit(AvatarUploadSuccess(avatarUrl));
      } else {
        emit(const AvatarUploadFailure('User not authenticated'));
      }
    } catch (e) {
      emit(AvatarUploadFailure(e.toString()));
    }
  }
}
