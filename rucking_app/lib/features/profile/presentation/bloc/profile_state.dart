part of 'profile_bloc.dart';

abstract class ProfileState extends Equatable {
  const ProfileState();

  @override
  List<Object> get props => [];
}

class ProfileInitial extends ProfileState {}

class AvatarUploading extends ProfileState {}

class AvatarUploadSuccess extends ProfileState {
  final String avatarUrl;

  const AvatarUploadSuccess(this.avatarUrl);

  @override
  List<Object> get props => [avatarUrl];
}

class AvatarUploadFailure extends ProfileState {
  final String error;

  const AvatarUploadFailure(this.error);

  @override
  List<Object> get props => [error];
}
