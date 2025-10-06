import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/features/profile/presentation/bloc/social_list_bloc.dart';
import 'package:rucking_app/features/profile/presentation/widgets/social_user_tile.dart';
import 'package:rucking_app/features/profile/presentation/bloc/public_profile_bloc.dart';
import 'package:rucking_app/features/profile/presentation/screens/public_profile_screen.dart';

class FollowersScreen extends StatefulWidget {
  final String userId;
  final String title;
  final bool isFollowersPage;
  const FollowersScreen(
      {Key? key,
      required this.userId,
      required this.title,
      required this.isFollowersPage})
      : super(key: key);

  @override
  _FollowersScreenState createState() => _FollowersScreenState();
}

class _FollowersScreenState extends State<FollowersScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    context
        .read<SocialListBloc>()
        .add(LoadSocialList(widget.userId, widget.isFollowersPage));

    // Add scroll listener for pagination
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent * 0.9) {
      // Load more when scrolled to 90%
      final state = context.read<SocialListBloc>().state;
      if (state is SocialListLoaded && state.hasMore) {
        context.read<SocialListBloc>().add(LoadMoreUsers());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: BlocBuilder<SocialListBloc, SocialListState>(
        builder: (context, state) {
          if (state is SocialListLoading)
            return Center(child: CircularProgressIndicator());
          if (state is SocialListError)
            return Center(child: Text(state.message));
          if (state is SocialListLoaded) {
            return ListView.builder(
              controller: _scrollController,
              itemCount: state.users.length + (state.hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == state.users.length)
                  return Center(child: CircularProgressIndicator());

                final user = state.users[index];
                return SocialUserTile(
                  user: user,
                  onFollowPressed: () => context
                      .read<SocialListBloc>()
                      .add(ToggleFollowUser(user.id)),
                  onTap: user.isLiveRuckingNow
                      ? null // Live tap is handled in SocialUserTile
                      : () {
                          // Navigate to public profile
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => BlocProvider(
                                create: (context) => GetIt.I<PublicProfileBloc>(),
                                child: PublicProfileScreen(userId: user.id),
                              ),
                            ),
                          );
                        },
                  showFollowButton: true,
                );
              },
            );
          }
          return SizedBox.shrink();
        },
      ),
    );
  }
}
