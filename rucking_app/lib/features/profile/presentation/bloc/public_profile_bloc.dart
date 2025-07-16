import 'package:bloc/bloc.dart';
import 'package:rucking_app/features/profile/domain/repositories/profile_repository.dart';
import 'package:rucking_app/features/profile/domain/entities/user_profile.dart';
import 'package:rucking_app/features/profile/domain/entities/user_profile_stats.dart';

abstract class PublicProfileEvent {}
class LoadPublicProfile extends PublicProfileEvent {
  final String userId;
  LoadPublicProfile(this.userId);
}
class ToggleFollow extends PublicProfileEvent {
  final String userId;
  ToggleFollow(this.userId);
}

abstract class PublicProfileState {}
class PublicProfileInitial extends PublicProfileState {}
class PublicProfileLoading extends PublicProfileState {}
class PublicProfileLoaded extends PublicProfileState {
  final UserProfile profile;
  final UserProfileStats? stats;
  final List<dynamic>? clubs;  // Assuming Club model exists
  final List<dynamic>? recentRucks;  // Assuming RuckSession model
  PublicProfileLoaded({required this.profile, this.stats, this.clubs, this.recentRucks});
}
class PublicProfileError extends PublicProfileState {
  final String message;
  PublicProfileError(this.message);
}

class PublicProfileBloc extends Bloc<PublicProfileEvent, PublicProfileState> {
  final ProfileRepository repository;
  PublicProfileBloc(this.repository) : super(PublicProfileInitial());

  @override
  Stream<PublicProfileState> mapEventToState(PublicProfileEvent event) async* {
    if (event is LoadPublicProfile) {
      yield PublicProfileLoading();
      try {
        final profile = await repository.getPublicProfile(event.userId);
        final stats = profile.isPrivateProfile ? null : await repository.getProfileStats(event.userId);
        // Assuming methods to fetch clubs and rucks
        final clubs = profile.isPrivateProfile ? null : [];  // Implement fetch
        final recentRucks = profile.isPrivateProfile ? null : [];  // Implement fetch
        yield PublicProfileLoaded(profile: profile, stats: stats, clubs: clubs, recentRucks: recentRucks);
      } catch (e) {
        yield PublicProfileError(e.toString());
      }
    } else if (event is ToggleFollow) {
      if (state is PublicProfileLoaded) {
        final current = state as PublicProfileLoaded;
        yield PublicProfileLoading();
        try {
          final success = current.profile.isFollowing
              ? await repository.unfollowUser(event.userId)
              : await repository.followUser(event.userId);
          if (success) {
            final updatedProfile = current.profile.copyWith(isFollowing: !current.profile.isFollowing);
            yield PublicProfileLoaded(
              profile: updatedProfile,
              stats: current.stats,
              clubs: current.clubs,
              recentRucks: current.recentRucks,
            );
          } else {
            yield PublicProfileError('Follow toggle failed');
          }
        } catch (e) {
          yield PublicProfileError(e.toString());
        }
      }
    }
  }
} 