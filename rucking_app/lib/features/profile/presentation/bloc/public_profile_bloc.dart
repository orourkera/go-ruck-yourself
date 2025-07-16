import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:rucking_app/features/profile/domain/repositories/profile_repository.dart';
import 'package:rucking_app/features/profile/domain/entities/user_profile.dart';
import 'package:rucking_app/features/profile/domain/entities/user_profile_stats.dart';
import 'package:rucking_app/features/clubs/domain/models/club.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_session.dart';

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
      // Assuming methods to fetch clubs and rucks
      final clubs = profile.isPrivateProfile ? null : <Club>[];  // Implement fetch
      final recentRucks = profile.isPrivateProfile ? null : <RuckSession>[];  // Implement fetch
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