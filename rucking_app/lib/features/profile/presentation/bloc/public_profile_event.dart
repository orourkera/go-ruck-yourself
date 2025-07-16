part of 'public_profile_bloc.dart';

abstract class PublicProfileEvent extends Equatable {
  const PublicProfileEvent();

  @override
  List<Object> get props => [];
}

class LoadPublicProfile extends PublicProfileEvent {
  final String userId;

  const LoadPublicProfile(this.userId);

  @override
  List<Object> get props => [userId];
}

class ToggleFollow extends PublicProfileEvent {
  final String userId;

  const ToggleFollow(this.userId);

  @override
  List<Object> get props => [userId];
}
