import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/core/services/service_locator.dart';
import 'package:rucking_app/features/clubs/domain/models/club.dart';
import 'package:rucking_app/features/clubs/presentation/bloc/clubs_bloc.dart';
import 'package:rucking_app/features/clubs/presentation/bloc/clubs_event.dart';
import 'package:rucking_app/features/clubs/presentation/bloc/clubs_state.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/custom_button.dart';
import 'package:rucking_app/shared/widgets/skeleton/skeleton_widgets.dart';
import 'package:rucking_app/shared/widgets/skeleton/skeleton_loader.dart';

/// Clubs screen with full functionality
class ClubsScreen extends StatefulWidget {
  const ClubsScreen({Key? key}) : super(key: key);

  @override
  State<ClubsScreen> createState() => _ClubsScreenState();
}

class _ClubsScreenState extends State<ClubsScreen> {
  late ClubsBloc _clubsBloc;
  final TextEditingController _searchController = TextEditingController();
  String? _membershipFilter;
  bool? _isPublicFilter;

  @override
  void initState() {
    super.initState();
    _clubsBloc = getIt<ClubsBloc>();
    _clubsBloc.add(const LoadClubs());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _performSearch() {
    _clubsBloc.add(LoadClubs(
      search: _searchController.text.isEmpty ? null : _searchController.text,
      isPublic: _isPublicFilter,
      membershipFilter: _membershipFilter,
    ));
  }

  void _showCreateClubDialog() {
    Navigator.of(context).pushNamed('/clubs/create').then((_) {
      // Refresh clubs when returning from create screen
      _clubsBloc.add(RefreshClubs());
    });
  }

  void _navigateToClubDetails(String clubId) {
    Navigator.of(context).pushNamed('/club_detail', arguments: clubId);
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _clubsBloc,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Clubs',
            style: AppTextStyles.titleLarge.copyWith(
              color: Theme.of(context).brightness == Brightness.dark ? Colors.white : AppColors.textDark,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back,
              color: Theme.of(context).brightness == Brightness.dark ? Colors.white : AppColors.textDark,
            ),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            IconButton(
              icon: Icon(
                Icons.add,
                color: Theme.of(context).brightness == Brightness.dark ? Colors.white : AppColors.textDark,
              ),
              onPressed: _showCreateClubDialog,
            ),
          ],
        ),
        body: BlocListener<ClubsBloc, ClubsState>(
          listener: (context, state) {
            if (state is ClubActionSuccess) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.message),
                  backgroundColor: AppColors.primary,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            } else if (state is ClubActionError) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.message),
                  backgroundColor: Colors.red,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
          child: Column(
            children: [
              // Search and filters
              Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Search bar
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search clubs...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            _performSearch();
                          },
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onSubmitted: (_) => _performSearch(),
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // Filter chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip(
                            'All Clubs',
                            _membershipFilter == null && _isPublicFilter == null,
                            () {
                              setState(() {
                                _membershipFilter = null;
                                _isPublicFilter = null;
                              });
                              _performSearch();
                            },
                          ),
                          const SizedBox(width: 8),
                          _buildFilterChip(
                            'My Clubs',
                            _membershipFilter == 'member',
                            () {
                              setState(() {
                                _membershipFilter = 'member';
                                _isPublicFilter = null;
                              });
                              _performSearch();
                            },
                          ),
                          const SizedBox(width: 8),
                          _buildFilterChip(
                            'Public',
                            _isPublicFilter == true,
                            () {
                              setState(() {
                                _isPublicFilter = true;
                                _membershipFilter = null;
                              });
                              _performSearch();
                            },
                          ),
                          const SizedBox(width: 8),
                          _buildFilterChip(
                            'Private',
                            _isPublicFilter == false,
                            () {
                              setState(() {
                                _isPublicFilter = false;
                                _membershipFilter = null;
                              });
                              _performSearch();
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              // Clubs list
              Expanded(
                child: BlocBuilder<ClubsBloc, ClubsState>(
                  builder: (context, state) {
                    if (state is ClubsLoading) {
                      return ListSkeleton(
                        itemCount: 5,
                        itemBuilder: (index) => _buildClubCardSkeleton(),
                      );
                    } else if (state is ClubsLoaded) {
                      if (state.clubs.isEmpty) {
                        return _buildEmptyState();
                      }
                      return RefreshIndicator(
                        onRefresh: () async {
                          _clubsBloc.add(RefreshClubs());
                        },
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: state.clubs.length,
                          itemBuilder: (context, index) {
                            final club = state.clubs[index];
                            return _buildClubCard(club);
                          },
                        ),
                      );
                    } else if (state is ClubsError) {
                      return _buildErrorState(state.message);
                    }
                    
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            Navigator.pushNamed(context, '/create_club');
          },
          backgroundColor: AppColors.primary,
          child: const Icon(
            Icons.add,
            color: Colors.white,
          ),
          tooltip: 'Create Club',
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.grey,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            color: isSelected ? Colors.white : AppColors.textDark,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildClubCard(Club club) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _navigateToClubDetails(club.id),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          club.name,
                          style: AppTextStyles.titleMedium.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (club.description != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            club.description!,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textDarkSecondary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: club.isPublic ? AppColors.primary.withOpacity(0.1) : AppColors.grey.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          club.isPublic ? 'Public' : 'Private',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: club.isPublic ? AppColors.primary : AppColors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${club.memberCount} member${club.memberCount != 1 ? 's' : ''}',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textDarkSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              
              Row(
                children: [
                  if (club.userRole != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: club.isUserAdmin ? AppColors.primary : AppColors.secondary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        club.isUserAdmin ? 'Admin' : 'Member',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ] else if (club.isUserPending) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Pending',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                  
                  const Spacer(),
                  
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: AppColors.textDarkSecondary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClubCardSkeleton() {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonLine(width: 120, height: 20),
                      const SizedBox(height: 4),
                      SkeletonLine(width: 100, height: 16),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    SkeletonLine(width: 60, height: 16),
                    const SizedBox(height: 4),
                    SkeletonLine(width: 40, height: 16),
                  ],
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            Row(
              children: [
                SkeletonLine(width: 60, height: 16),
                const Spacer(),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: AppColors.textDarkSecondary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.group_outlined,
              size: 64,
              color: AppColors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              'No clubs found',
              style: AppTextStyles.titleMedium.copyWith(
                color: AppColors.textDarkSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Be the first to create a club!',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textDarkSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            CustomButton(
              onPressed: _showCreateClubDialog,
              text: 'Create Club',
              isLoading: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              'Error loading clubs',
              style: AppTextStyles.titleMedium.copyWith(
                color: AppColors.textDarkSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textDarkSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            CustomButton(
              onPressed: () => _clubsBloc.add(RefreshClubs()),
              text: 'Retry',
              isLoading: false,
            ),
          ],
        ),
      ),
    );
  }
}
