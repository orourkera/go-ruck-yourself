import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:rucking_app/features/profile/domain/repositories/profile_repository.dart';
import 'package:rucking_app/features/profile/domain/entities/user_profile.dart';
import 'package:rucking_app/features/profile/domain/entities/user_profile_stats.dart';

part 'public_profile_event.dart';
part 'public_profile_state.dart';

class PublicProfileBloc extends Bloc<PublicProfileEvent, PublicProfileState> {
  final ProfileRepository repository;

  PublicProfileBloc(this.repository) : super(PublicProfileInitial()) {
    on<LoadPublicProfile>(_onLoadPublicProfile);
    on<ToggleFollow>(_onToggleFollow);
  }

  Future<void> _onLoadPublicProfile(LoadPublicProfile event, Emitter<PublicProfileState> emit) async {
    emit(PublicProfileLoading());
    try {
      final profile = await repository.getPublicProfile(event.userId);
      final stats = profile.isPrivateProfile ? null : await repository.getProfileStats(event.userId);
      
      // Fetch clubs and recent rucks if profile is not private
      final clubs = profile.isPrivateProfile ? null : await repository.getUserClubs(event.userId);
      final recentRucks = profile.isPrivateProfile ? null : await repository.getRecentRucks(event.userId);
      
      emit(PublicProfileLoaded(
        profile: profile,
        stats: stats ?? UserProfileStats.empty(),
        isFollowing: profile.isFollowing,
        clubs: clubs,
        recentRucks: recentRucks,
      ));
    } catch (e) {
      emit(PublicProfileError(e.toString()));
    }
  }

  Future<void> _onToggleFollow(ToggleFollow event, Emitter<PublicProfileState> emit) async {
    if (state is PublicProfileLoaded) {
      final current = state as PublicProfileLoaded;
      emit(PublicProfileLoading());
      try {
        final success = current.profile.isFollowing
            ? await repository.unfollowUser(event.userId)
            : await repository.followUser(event.userId);
        if (success) {
          final updatedProfile = current.profile.copyWith(isFollowing: !current.profile.isFollowing);
          emit(PublicProfileLoaded(
            profile: updatedProfile,
            stats: current.stats,
            isFollowing: !current.isFollowing,
            clubs: current.clubs,
            recentRucks: current.recentRucks,
          ));
        } else {
          emit(PublicProfileError('Follow toggle failed'));
        }
      } catch (e) {
        emit(PublicProfileError(e.toString()));
      }
    }
  }
} 