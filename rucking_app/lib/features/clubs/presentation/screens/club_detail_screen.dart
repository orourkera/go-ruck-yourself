import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/skeleton/skeleton_widgets.dart';
import 'package:rucking_app/shared/widgets/skeleton/skeleton_loader.dart';
import 'package:rucking_app/features/clubs/domain/models/club.dart';
import 'package:rucking_app/features/clubs/presentation/bloc/clubs_bloc.dart';
import 'package:rucking_app/features/clubs/presentation/bloc/clubs_event.dart';
import 'package:rucking_app/features/clubs/presentation/bloc/clubs_state.dart';
import 'package:rucking_app/core/services/service_locator.dart';

class ClubDetailScreen extends StatefulWidget {
  final String clubId;

  const ClubDetailScreen({
    super.key,
    required this.clubId,
  });

  @override
  State<ClubDetailScreen> createState() => _ClubDetailScreenState();
}

class _ClubDetailScreenState extends State<ClubDetailScreen> {
  late ClubsBloc _clubsBloc;
  ClubDetails? _clubDetails;

  @override
  void initState() {
    super.initState();
    _clubsBloc = getIt<ClubsBloc>();
    _clubsBloc.add(LoadClubDetails(widget.clubId));
  }

  @override
  void dispose() {
    _clubsBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _clubsBloc,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _clubDetails?.club.name ?? 'Club Details',
            style: AppTextStyles.titleLarge.copyWith(
              color: Theme.of(context).brightness == Brightness.dark ? Colors.white : AppColors.textDark,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: _buildAppBarActions(),
        ),
        body: BlocConsumer<ClubsBloc, ClubsState>(
          listener: (context, state) {
            if (state is ClubDetailsLoaded) {
              setState(() {
                _clubDetails = state.clubDetails;
              });
            } else if (state is ClubActionSuccess) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.message),
                  backgroundColor: Colors.green,
                ),
              );
              // Refresh club details after successful action
              _clubsBloc.add(LoadClubDetails(widget.clubId));
            } else if (state is ClubActionError) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.message),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
          builder: (context, state) {
            if (state is ClubsLoading || state is ClubActionLoading) {
              return _buildClubDetailSkeleton();
            } else if (state is ClubDetailsLoaded) {
              return _buildClubContent(state.clubDetails);
            } else if (state is ClubsError) {
              return _buildErrorState(state.message);
            }
            
            return const SizedBox.shrink();
          },
        ),
        floatingActionButton: _buildFloatingActionButton(),
      ),
    );
  }

  List<Widget> _buildAppBarActions() {
    if (_clubDetails?.club.userRole == 'admin') {
      return [
        IconButton(
          icon: const Icon(Icons.edit),
          onPressed: () => _navigateToEditClub(),
          tooltip: 'Edit Club',
        ),
        PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'delete') {
              _showDeleteConfirmation();
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Delete Club', style: AppTextStyles.bodyMedium.copyWith(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
      ];
    }
    return [];
  }

  Widget _buildClubContent(ClubDetails clubDetails) {
    return RefreshIndicator(
      onRefresh: () async {
        _clubsBloc.add(LoadClubDetails(widget.clubId));
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildClubHeader(clubDetails),
            const SizedBox(height: 24),
            _buildClubStats(clubDetails),
            const SizedBox(height: 24),
            _buildMembersSection(clubDetails),
            if (clubDetails.club.userRole == 'admin' && clubDetails.pendingRequests.isNotEmpty) ...[
              const SizedBox(height: 24),
              _buildPendingRequestsSection(clubDetails),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildClubHeader(ClubDetails clubDetails) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Theme.of(context).primaryColor,
                  child: Text(
                    clubDetails.club.name.isNotEmpty ? clubDetails.club.name[0].toUpperCase() : 'C',
                    style: AppTextStyles.bodyMedium.copyWith(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        clubDetails.club.name,
                        style: AppTextStyles.titleLarge.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            clubDetails.club.isPublic ? Icons.public : Icons.lock,
                            size: 16,
                            color: AppColors.textDarkSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            clubDetails.club.isPublic ? 'Public Club' : 'Private Club',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.textDarkSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (clubDetails.club.description != null && clubDetails.club.description!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                clubDetails.club.description!,
                style: AppTextStyles.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildClubStats(ClubDetails clubDetails) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem(
              'Members',
              '${clubDetails.members.length}/${clubDetails.club.maxMembers}',
              Icons.people,
            ),
            _buildStatItem(
              'Admin',
              _getAdminName(clubDetails),
              Icons.admin_panel_settings,
            ),
            _buildStatItem(
              'Created',
              _formatDate(clubDetails.club.createdAt),
              Icons.calendar_today,
            ),
          ],
        ),
      ),
    );
  }

  String _getAdminName(ClubDetails clubDetails) {
    return clubDetails.adminUser.username ?? 'Unknown';
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Theme.of(context).primaryColor, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTextStyles.bodyMedium.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textDarkSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildMembersSection(ClubDetails clubDetails) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Members',
          style: AppTextStyles.titleMedium.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: clubDetails.members.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final member = clubDetails.members[index];
              return _buildMemberTile(member, clubDetails);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMemberTile(ClubMember member, ClubDetails clubDetails) {
    final canManageMember = clubDetails.club.userRole == 'admin' && 
                           member.role != 'admin';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).primaryColor,
        child: Text(
          (member.username ?? '').isNotEmpty ? (member.username![0].toUpperCase()) : 'U',
          style: AppTextStyles.bodyMedium.copyWith(color: Colors.white),
        ),
      ),
      title: Text(
        member.username ?? 'Unknown',
        style: AppTextStyles.bodyMedium,
      ),
      subtitle: Text(
        member.role.toUpperCase(),
        style: AppTextStyles.bodySmall.copyWith(
          color: member.role == 'admin' ? Theme.of(context).primaryColor : AppColors.textDarkSecondary,
          fontWeight: FontWeight.bold,
        ),
      ),
      trailing: canManageMember ? _buildMemberActions(member) : null,
    );
  }

  Widget _buildMemberActions(ClubMember member) {
    return PopupMenuButton<String>(
      onSelected: (value) {
        switch (value) {
          case 'promote':
            _showPromoteMemberDialog(member);
            break;
          case 'remove':
            _showRemoveMemberDialog(member);
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'promote',
          child: Row(
            children: [
              const Icon(Icons.upgrade),
              const SizedBox(width: 8),
              Text(member.role == 'member' ? 'Promote to Admin' : 'Demote to Member'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'remove',
          child: Row(
            children: [
              Icon(Icons.remove_circle, color: Colors.red),
              SizedBox(width: 8),
              Text('Remove Member', style: AppTextStyles.bodyMedium.copyWith(color: Colors.red)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPendingRequestsSection(ClubDetails clubDetails) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pending Requests (${clubDetails.pendingRequests.length})',
          style: AppTextStyles.titleMedium.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: clubDetails.pendingRequests.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final request = clubDetails.pendingRequests[index];
              return _buildPendingRequestTile(request);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPendingRequestTile(ClubMember request) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).primaryColor,
        child: Text(
          (request.username ?? '').isNotEmpty ? request.username![0].toUpperCase() : 'U',
          style: AppTextStyles.bodyMedium.copyWith(color: Colors.white),
        ),
      ),
      title: Text(request.username ?? 'Unknown'),
      subtitle: Text(
        'Requested ${_formatDate(request.joinedAt)}',
        style: AppTextStyles.bodySmall.copyWith(
          color: AppColors.textDarkSecondary,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.check_circle, color: Colors.green),
            onPressed: () => _approveRequest(request),
            tooltip: 'Approve',
          ),
          IconButton(
            icon: const Icon(Icons.cancel, color: Colors.red),
            onPressed: () => _rejectRequest(request),
            tooltip: 'Reject',
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingActionButton() {
    if (_clubDetails == null) return const SizedBox.shrink();

    if (_clubDetails!.club.canJoin) {
      // User is not a member - show join button
      return FloatingActionButton.extended(
        onPressed: () => _requestMembership(),
        icon: const Icon(Icons.group_add),
        label: const Text('Join Club'),
        backgroundColor: Theme.of(context).primaryColor,
      );
    } else if (_clubDetails!.club.isUserPending) {
      // User has pending request
      return FloatingActionButton.extended(
        onPressed: null,
        icon: const Icon(Icons.hourglass_empty),
        label: const Text('Request Pending'),
        backgroundColor: Colors.grey,
      );
    } else if (_clubDetails!.club.isUserMember && !_clubDetails!.club.isUserAdmin) {
      // User is a member but not admin - show leave button
      return FloatingActionButton.extended(
        onPressed: () => _showLeaveClubDialog(),
        icon: const Icon(Icons.exit_to_app),
        label: const Text('Leave Club'),
        backgroundColor: Colors.red,
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Error Loading Club',
            style: AppTextStyles.titleMedium.copyWith(
              color: Colors.grey[600],
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: AppTextStyles.bodyMedium.copyWith(
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _clubsBloc.add(LoadClubDetails(widget.clubId)),
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 365) {
      return '${(difference.inDays / 365).floor()}y ago';
    } else if (difference.inDays > 30) {
      return '${(difference.inDays / 30).floor()}mo ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else {
      return 'Today';
    }
  }

  void _navigateToEditClub() {
    Navigator.of(context).pushNamed('/edit_club', arguments: _clubDetails);
  }

  void _requestMembership() {
    _clubsBloc.add(RequestMembership(widget.clubId));
  }

  void _approveRequest(ClubMember request) {
    _clubsBloc.add(ManageMembership(
      clubId: widget.clubId,
      userId: request.userId,
      action: 'approve',
    ));
  }

  void _rejectRequest(ClubMember request) {
    _clubsBloc.add(ManageMembership(
      clubId: widget.clubId,
      userId: request.userId,
      action: 'reject',
    ));
  }

  void _showPromoteMemberDialog(ClubMember member) {
    final newRole = member.role == 'member' ? 'admin' : 'member';
    final action = member.role == 'member' ? 'promote' : 'demote';
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${action.capitalizeFirst()} Member'),
        content: Text(
          'Are you sure you want to $action ${member.username} to $newRole?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _clubsBloc.add(ManageMembership(
                clubId: widget.clubId,
                userId: member.userId,
                action: newRole,
              ));
            },
            child: Text(action.capitalizeFirst()),
          ),
        ],
      ),
    );
  }

  void _showRemoveMemberDialog(ClubMember member) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text(
          'Are you sure you want to remove ${member.username} from the club?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _clubsBloc.add(RemoveMembership(
                clubId: widget.clubId,
                userId: member.userId,
              ));
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  void _showLeaveClubDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Club'),
        content: Text(
          'Are you sure you want to leave ${_clubDetails!.club.name}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _clubsBloc.add(LeaveClub(widget.clubId));
              Navigator.of(context).pop(); // Go back to clubs list
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Club'),
        content: Text(
          'Are you sure you want to permanently delete ${_clubDetails!.club.name}? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _clubsBloc.add(DeleteClub(widget.clubId));
              Navigator.of(context).pop(); // Go back to clubs list
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildClubDetailSkeleton() {
    return SkeletonLoader(
      isLoading: true,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Club header section
            Row(
              children: [
                SkeletonCircle(size: 60),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonLine(width: 150, height: 24),
                      const SizedBox(height: 8),
                      SkeletonLine(width: 100, height: 16),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 24),
            
            // Club stats section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  children: [
                    SkeletonLine(width: 40, height: 24),
                    const SizedBox(height: 4),
                    SkeletonLine(width: 60, height: 16),
                  ],
                ),
                Column(
                  children: [
                    SkeletonLine(width: 40, height: 24),
                    const SizedBox(height: 4),
                    SkeletonLine(width: 60, height: 16),
                  ],
                ),
                Column(
                  children: [
                    SkeletonLine(width: 40, height: 24),
                    const SizedBox(height: 4),
                    SkeletonLine(width: 60, height: 16),
                  ],
                ),
              ],
            ),
            
            const SizedBox(height: 24),
            
            // Members section
            SkeletonLine(width: 100, height: 20),
            const SizedBox(height: 16),
            
            // Member list
            ...List.generate(3, (index) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  SkeletonCircle(size: 40),
                  const SizedBox(width: 12),
                  Expanded(child: SkeletonLine(width: double.infinity, height: 16)),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }
}

extension StringExtension on String {
  String capitalizeFirst() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}
