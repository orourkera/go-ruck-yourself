import 'package:bloc/bloc.dart';
import 'package:rucking_app/features/profile/domain/repositories/profile_repository.dart';
import 'package:rucking_app/features/profile/domain/entities/social_user.dart';

abstract class SocialListEvent {}

class LoadSocialList extends SocialListEvent {
  final String userId;
  final bool isFollowersPage;
  LoadSocialList(this.userId, this.isFollowersPage);
}

class ToggleFollowUser extends SocialListEvent {
  final String userId;
  ToggleFollowUser(this.userId);
}

abstract class SocialListState {}

class SocialListInitial extends SocialListState {}

class SocialListLoading extends SocialListState {}

class SocialListLoaded extends SocialListState {
  final List<SocialUser> users;
  final bool hasMore;
  SocialListLoaded({required this.users, this.hasMore = false});
}

class SocialListError extends SocialListState {
  final String message;
  SocialListError(this.message);
}

class SocialListBloc extends Bloc<SocialListEvent, SocialListState> {
  final ProfileRepository repository;

  SocialListBloc(this.repository) : super(SocialListInitial()) {
    on<LoadSocialList>(_onLoadSocialList);
    on<ToggleFollowUser>(_onToggleFollowUser);
  }

  Future<void> _onLoadSocialList(
      LoadSocialList event, Emitter<SocialListState> emit) async {
    emit(SocialListLoading());
    try {
      final users = event.isFollowersPage
          ? await repository.getFollowers(event.userId)
          : await repository.getFollowing(event.userId);
      emit(SocialListLoaded(
          users: users, hasMore: users.length == 20)); // Assuming per_page=20
    } catch (e) {
      emit(SocialListError(e.toString()));
    }
  }

  Future<void> _onToggleFollowUser(
      ToggleFollowUser event, Emitter<SocialListState> emit) async {
    if (state is SocialListLoaded) {
      final current = state as SocialListLoaded;
      emit(SocialListLoading());
      try {
        final targetUser =
            current.users.firstWhere((u) => u.id == event.userId);
        final success = targetUser.isFollowing
            ? await repository.unfollowUser(event.userId)
            : await repository.followUser(event.userId);
        if (success) {
          final updatedUsers = current.users
              .map((u) => u.id == event.userId
                  ? u.copyWith(isFollowing: !u.isFollowing)
                  : u)
              .toList();
          emit(SocialListLoaded(users: updatedUsers, hasMore: current.hasMore));
        } else {
          emit(SocialListError('Follow toggle failed'));
        }
      } catch (e) {
        emit(SocialListError(e.toString()));
      }
    }
  }
}
