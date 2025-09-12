import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/profile/presentation/bloc/social_list_bloc.dart';
import 'package:rucking_app/features/profile/presentation/widgets/social_user_tile.dart';

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
  @override
  void initState() {
    super.initState();
    context
        .read<SocialListBloc>()
        .add(LoadSocialList(widget.userId, widget.isFollowersPage));
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
              itemCount: state.users.length + (state.hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == state.users.length)
                  return Center(child: CircularProgressIndicator());
                return SocialUserTile(
                  user: state.users[index],
                  onFollowPressed: () => context
                      .read<SocialListBloc>()
                      .add(ToggleFollowUser(state.users[index].id)),
                  showFollowButton:
                      true, // Always show follow button so users can follow/unfollow
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
