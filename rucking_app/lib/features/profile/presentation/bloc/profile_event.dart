part of 'profile_bloc.dart';

abstract class ProfileEvent extends Equatable {
  const ProfileEvent();

  @override
  List<Object> get props => [];
}

class UploadAvatar extends ProfileEvent {
  final File imageFile;

  const UploadAvatar(this.imageFile);

  @override
  List<Object> get props => [imageFile];
}
