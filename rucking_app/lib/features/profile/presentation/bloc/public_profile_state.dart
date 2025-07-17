part of 'public_profile_bloc.dart';

abstract class PublicProfileState extends Equatable {
  const PublicProfileState();

  @override
  List<Object> get props => [];
}

class PublicProfileInitial extends PublicProfileState {}

class PublicProfileLoading extends PublicProfileState {}

class PublicProfileLoaded extends PublicProfileState {
  final UserProfile profile;
  final UserProfileStats stats;
  final bool isFollowing;
  final List<dynamic>? clubs;
  final List<dynamic>? recentRucks;

  const PublicProfileLoaded({
    required this.profile,
    required this.stats,
    required this.isFollowing,
    this.clubs,
    this.recentRucks,
  });

  @override
  List<Object> get props => [profile, stats, isFollowing, clubs ?? [], recentRucks ?? []];
}

class PublicProfileError extends PublicProfileState {
  final String message;

  const PublicProfileError(this.message);

  @override
  List<Object> get props => [message];
}

class PublicProfileToggleFollowSuccess extends PublicProfileState {
  final bool isFollowing;

  const PublicProfileToggleFollowSuccess(this.isFollowing);

  @override
  List<Object> get props => [isFollowing];
}
