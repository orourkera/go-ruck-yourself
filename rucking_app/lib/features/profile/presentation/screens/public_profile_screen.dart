import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/profile/presentation/bloc/public_profile_bloc.dart';
import 'package:rucking_app/features/profile/presentation/widgets/profile_header.dart';
import 'package:rucking_app/features/profile/presentation/widgets/profile_stats_grid.dart';
import 'package:rucking_app/features/profile/domain/entities/user_profile_stats.dart';

class PublicProfileScreen extends StatefulWidget {
  final String userId;
  const PublicProfileScreen({Key? key, required this.userId}) : super(key: key);

  @override
  _PublicProfileScreenState createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    context.read<PublicProfileBloc>().add(LoadPublicProfile(widget.userId));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Profile')),
      body: BlocBuilder<PublicProfileBloc, PublicProfileState>(
        builder: (context, state) {
          if (state is PublicProfileLoading) return Center(child: CircularProgressIndicator());
          if (state is PublicProfileError) return Center(child: Text(state.message));
          if (state is PublicProfileLoaded) {
            return SingleChildScrollView(
              child: Column(
                children: [
                  ProfileHeader(profile: state.profile, isOwnProfile: false),
                  if (!state.profile.isPrivateProfile) ...[
                    ProfileStatsGrid(stats: state.stats ?? UserProfileStats.fromJson({})),
                    TabBar(controller: _tabController, tabs: [Tab(text: 'Stats'), Tab(text: 'Clubs'), Tab(text: 'Recent')]),
                    SizedBox(
                      height: 300,
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          Text('Detailed Stats'),
                          ListView.builder(itemCount: state.clubs?.length ?? 0, itemBuilder: (_, i) => ListTile(title: Text(state.clubs![i].name ?? ''))),
                          ListView.builder(itemCount: state.recentRucks?.length ?? 0, itemBuilder: (_, i) => ListTile(title: Text('Ruck ${i+1}'))),
                        ],
                      ),
                    ),
                  ] else
                    Center(child: Text('This profile is private')),
                ],
              ),
            );
          }
          return SizedBox.shrink();
        },
      ),
    );
  }
} 