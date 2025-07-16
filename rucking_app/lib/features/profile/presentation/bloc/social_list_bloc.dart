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
  SocialListBloc(this.repository) : super(SocialListInitial());

  @override
  Stream<SocialListState> mapEventToState(SocialListEvent event) async* {
    if (event is LoadSocialList) {
      yield SocialListLoading();
      try {
        final users = event.isFollowersPage
            ? await repository.getFollowers(event.userId)
            : await repository.getFollowing(event.userId);
        yield SocialListLoaded(users: users, hasMore: users.length == 20);  // Assuming per_page=20
      } catch (e) {
        yield SocialListError(e.toString());
      }
    } else if (event is ToggleFollowUser) {
      if (state is SocialListLoaded) {
        final current = state as SocialListLoaded;
        yield SocialListLoading();
        try {
          final targetUser = current.users.firstWhere((u) => u.id == event.userId);
          final success = targetUser.isFollowing
              ? await repository.unfollowUser(event.userId)
              : await repository.followUser(event.userId);
          if (success) {
            final updatedUsers = current.users.map((u) => u.id == event.userId ? u.copyWith(isFollowing: !u.isFollowing) : u).toList();
            yield SocialListLoaded(users: updatedUsers, hasMore: current.hasMore);
          } else {
            yield SocialListError('Follow toggle failed');
          }
        } catch (e) {
          yield SocialListError(e.toString());
        }
      }
    }
  }
} 