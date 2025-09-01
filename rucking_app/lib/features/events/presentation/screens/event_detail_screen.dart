import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:rucking_app/core/services/service_locator.dart';
import 'package:rucking_app/core/services/event_share_service.dart';
import 'package:rucking_app/features/events/domain/models/event.dart';
import 'package:rucking_app/features/events/presentation/bloc/events_bloc.dart';
import 'package:rucking_app/features/events/presentation/bloc/events_event.dart';
import 'package:rucking_app/features/events/presentation/bloc/events_state.dart';
import 'package:rucking_app/features/events/presentation/bloc/event_comments_bloc.dart';
import 'package:rucking_app/features/events/presentation/bloc/event_comments_event.dart';
import 'package:rucking_app/features/events/presentation/bloc/event_comments_state.dart';
import 'package:rucking_app/features/events/presentation/bloc/event_progress_bloc.dart';
import 'package:rucking_app/features/events/presentation/bloc/event_progress_event.dart';
import 'package:rucking_app/features/events/presentation/bloc/event_progress_state.dart';
import 'package:rucking_app/features/events/presentation/widgets/event_leaderboard_widget.dart';
import 'package:rucking_app/features/events/presentation/widgets/event_comments_section.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/widgets/skeleton/skeleton_loader.dart';
import 'package:rucking_app/shared/widgets/skeleton/skeleton_widgets.dart';
import 'package:rucking_app/shared/widgets/error_display.dart';
import 'package:rucking_app/shared/widgets/styled_snackbar.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/shared/widgets/full_screen_image_viewer.dart';

class EventDetailScreen extends StatefulWidget {
  final String eventId;

  const EventDetailScreen({
    super.key,
    required this.eventId,
  });

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen>
    with SingleTickerProviderStateMixin {
  late EventsBloc _eventsBloc;
  late EventCommentsBloc _commentsBloc;
  late EventProgressBloc _progressBloc;
  late TabController _tabController;
  
  EventDetails? _eventDetails;

  @override
  void initState() {
    super.initState();
    _eventsBloc = getIt<EventsBloc>();
    _commentsBloc = getIt<EventCommentsBloc>();
    _progressBloc = getIt<EventProgressBloc>();
    _tabController = TabController(length: 3, vsync: this);
    
    // Load event details first
    _eventsBloc.add(LoadEventDetails(widget.eventId));
    // Comments and leaderboard will be loaded after we get event details
    // and can check user participation status
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Check if user can access event comments and leaderboard data
  /// Only participants (approved/pending) and event creators should have access
  bool _canAccessEventData(Event event) {
    // Event creators always have access
    if (event.isCreator) {
      return true;
    }
    
    // Participants (approved or pending) have access
    if (event.isUserParticipating) {
      return true;
    }
    
    // All other users don't have access
    return false;
  }

  /// Build unauthorized access message for restricted tabs
  Widget _buildUnauthorizedTab(String message) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline,
              size: 64,
              color: isDarkMode ? Colors.grey[600] : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyLarge.copyWith(
                color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            if (_eventDetails?.event.canJoin == true)
              ElevatedButton(
                onPressed: () {
                  _eventsBloc.add(JoinEvent(_eventDetails!.event.id));
                },
                child: const Text('Join Event'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _eventsBloc),
        BlocProvider.value(value: _commentsBloc),
        BlocProvider.value(value: _progressBloc),
      ],
      child: Scaffold(
        body: BlocConsumer<EventsBloc, EventsState>(
          listener: (context, state) {
            print('🎯 EventDetail BlocListener triggered with state: ${state.runtimeType}');
            
            if (state is EventDetailsLoaded) {
              setState(() {
                _eventDetails = state.eventDetails;
              });
              
              // Only load comments and leaderboard if user is authorized
              final event = state.eventDetails.event;
              if (_canAccessEventData(event)) {
                _commentsBloc.add(LoadEventComments(widget.eventId));
                _progressBloc.add(LoadEventLeaderboard(widget.eventId));
              }
            } else if (state is EventActionSuccess) {
              print('✅ EventActionSuccess received: sessionId=${state.sessionId}, eventId=${state.eventId}');
              
              StyledSnackBar.showSuccess(
                context: context,
                message: state.message,
              );
              
              if (state.shouldRefresh) {
                _eventsBloc.add(LoadEventDetails(widget.eventId));
                // Only refresh leaderboard if user is authorized
                if (_eventDetails != null && _canAccessEventData(_eventDetails!.event)) {
                  _progressBloc.add(LoadEventLeaderboard(widget.eventId));
                }
              }
              
              // Handle navigation after starting ruck session
              if (state.sessionId != null) {
                Navigator.of(context).pushReplacementNamed(
                  '/active_session',
                  arguments: state.sessionId,
                );
              }
              
              // Handle navigation to create session with event context
              if (state.eventId != null) {
                print('🚀 Navigating to create session with event_id: ${state.eventId}, event_title: ${state.eventTitle}');
                Navigator.of(context).pushNamed(
                  '/create_session',
                  arguments: {
                    'event_id': state.eventId,
                    'event_title': state.eventTitle,
                  },
                );
              }
            } else if (state is EventActionError) {
              StyledSnackBar.showError(
                context: context,
                message: state.message,
              );
            }
          },
          builder: (context, state) {
            if (state is EventDetailsLoading) {
              return _buildLoadingSkeleton();
            } else if (state is EventDetailsError) {
              return ErrorDisplay(
                message: state.message,
                onRetry: () {
                  _eventsBloc.add(LoadEventDetails(widget.eventId));
                },
              );
            } else if (state is EventDetailsLoaded) {
              return _buildEventDetails(state.eventDetails);
            }
            
            return _buildLoadingSkeleton();
          },
        ),
        bottomNavigationBar: _buildBottomActionBar(),
      ),
    );
  }

  List<Widget> _buildAppBarActions() {
    final event = _eventDetails?.event;
    if (event == null) return [];
    
    List<Widget> actions = [];
    
    // Add share button (always visible for all users)
    actions.add(
      IconButton(
        icon: const Icon(Icons.share),
        tooltip: 'Share Event',
        onPressed: () => _shareEvent(event),
      ),
    );
    
    List<PopupMenuEntry<String>> menuItems = [];
    
    // Add Edit option for event creators
    if (event.isCreator) {
      menuItems.add(
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              const Icon(Icons.edit, size: 20, color: Colors.black),
              const SizedBox(width: 8),
              Text(
                'Edit Event',
                style: AppTextStyles.bodyMedium.copyWith(
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    // Add Leave option for participants who can leave
    if (event.canLeave) {
      menuItems.add(
        PopupMenuItem(
          value: 'leave',
          child: Row(
            children: [
              const Icon(Icons.exit_to_app, size: 20, color: Colors.red),
              const SizedBox(width: 8),
              Text(
                'Leave Event',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: Colors.red,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    // Add Cancel option for event creators
    if (event.isCreator) {
      if (menuItems.isNotEmpty) {
        menuItems.add(const PopupMenuDivider());
      }
      menuItems.add(
        PopupMenuItem(
          value: 'cancel',
          child: Row(
            children: [
              const Icon(Icons.cancel, size: 20, color: Colors.red),
              const SizedBox(width: 8),
              Text(
                'Cancel Event',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: Colors.red,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    // Only show menu if there are items
    if (menuItems.isNotEmpty) {
      actions.add(
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert), // Vertical dots
          onSelected: (value) {
            switch (value) {
              case 'edit':
                Navigator.of(context).pushNamed(
                  '/edit_event',
                  arguments: widget.eventId,
                ).then((_) {
                  _eventsBloc.add(LoadEventDetails(widget.eventId));
                });
                break;
              case 'leave':
                _eventsBloc.add(LeaveEvent(event.id));
                break;
              case 'cancel':
                _showCancelConfirmation();
                break;
            }
          },
          itemBuilder: (context) => menuItems,
        ),
      );
    }
    
    return actions;
  }

  Widget _buildLoadingSkeleton() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner skeleton
          const SkeletonBox(height: 200, width: double.infinity),
          const SizedBox(height: 16),
          
          // Title and info skeleton
          const SkeletonLine(width: 250),
          const SizedBox(height: 8),
          const SkeletonLine(width: 150),
          const SizedBox(height: 16),
          
          // Description skeleton
          const SkeletonLine(width: double.infinity),
          const SizedBox(height: 4),
          const SkeletonLine(width: 200),
          const SizedBox(height: 16),
          
          // Details skeleton
          Row(
            children: const [
              SkeletonLine(width: 100),
              SizedBox(width: 16),
              SkeletonLine(width: 80),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEventDetails(EventDetails eventDetails) {
    final event = eventDetails.event;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    // Get lady mode status
    bool isLadyMode = false;
    final authState = context.read<AuthBloc>().state;
    if (authState is Authenticated) {
      isLadyMode = authState.user.gender == 'female';
    }
    
    final primaryColor = isLadyMode ? AppColors.ladyPrimary : AppColors.primary;
    
    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) {
        return [
          SliverAppBar(
            pinned: true,
            expandedHeight: 60,
            backgroundColor: _getLadyModeColor(context),
            title: Text(
              event.title,
              textAlign: TextAlign.center,
              style: AppTextStyles.titleLarge.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            centerTitle: true,
            iconTheme: const IconThemeData(color: Colors.white),
            actions: _buildAppBarActions().map((action) {
              // Ensure action icons are white
              if (action is IconButton) {
                return IconButton(
                  onPressed: action.onPressed,
                  icon: action.icon,
                  iconSize: action.iconSize,
                  color: Colors.white,
                );
              }
              return action;
            }).toList(),
          ),
        ];
      },
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Event header
            _buildEventHeader(event, isDarkMode, isLadyMode),
            
            // Tab bar for content sections
            Container(
              color: isDarkMode ? AppColors.darkAppBarBackground : AppColors.lightAppBarBackground,
              child: TabBar(
                controller: _tabController,
                labelColor: primaryColor,
                unselectedLabelColor: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                indicatorColor: primaryColor,
                tabs: const [
                  Tab(text: 'Details'),
                  Tab(text: 'Leaderboard'),
                  Tab(text: 'Comments'),
                ],
              ),
            ),
            
            // Tab content - Fixed height container
            Container(
              height: MediaQuery.of(context).size.height * 0.6,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildDetailsTab(event, eventDetails.participants),
                  _canAccessEventData(event) 
                    ? EventLeaderboardWidget(eventId: widget.eventId)
                    : _buildUnauthorizedTab('You must be a participant to view the leaderboard'),
                  _canAccessEventData(event)
                    ? EventCommentsSection(eventId: widget.eventId)
                    : _buildUnauthorizedTab('You must be a participant to view comments'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getLadyModeColor(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    return authState is Authenticated && authState.user.gender == 'female'
        ? AppColors.ladyPrimary
        : AppColors.primary;
  }

  Widget _buildEventHeader(Event event, bool isDarkMode, bool isLadyMode) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner image if available
          if (event.bannerImageUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: GestureDetector(
                onTap: () => FullScreenImageViewer.show(
                  context,
                  imageUrl: event.bannerImageUrl!,
                  heroTag: 'event_banner_${event.id}',
                ),
                child: Hero(
                  tag: 'event_banner_${event.id}',
                  child: Image.network(
                    event.bannerImageUrl!,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        height: 200,
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.event,
                            size: 60,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          
          const SizedBox(height: 16),
          
          // Title and club info
          Row(
            children: [
              if (event.hostingClub != null) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.groups,
                    size: 24,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      style: AppTextStyles.headlineMedium.copyWith(
                        color: isDarkMode ? Colors.white : (isLadyMode ? AppColors.ladyPrimary : AppColors.primary),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (event.hostingClub != null)
                      Text(
                        event.hostingClub!.name,
                        style: AppTextStyles.bodyLarge.copyWith(
                          color: (isLadyMode ? AppColors.ladyPrimary : AppColors.primary),
                          fontWeight: FontWeight.w500,
                        ),
                      )
                    else if (event.creator != null)
                      Text(
                        'Organized by ${event.creator!.username}',
                        style: AppTextStyles.bodyLarge.copyWith(
                          color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                  ],
                ),
              ),
              
              // Status badge
              _buildStatusBadge(event),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Event timing
          Row(
            children: [
              Icon(
                Icons.schedule,
                size: 20,
                color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
              ),
              const SizedBox(width: 8),
              Text(
                _formatEventDateTime(event.scheduledStartTime, event.durationMinutes),
                style: AppTextStyles.bodyLarge.copyWith(
                  color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 8),
          
          // Location if available
          if (event.locationName != null)
            InkWell(
              onTap: () => _openLocation(event.locationName!, event.latitude, event.longitude),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on,
                      size: 20,
                      color: AppColors.getLocationTextColor(context, isLadyMode: isLadyMode),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        event.locationName!,
                        style: AppTextStyles.bodyLarge.copyWith(
                          color: AppColors.getLocationTextColor(context, isLadyMode: isLadyMode),
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.open_in_new,
                      size: 16,
                      color: AppColors.getLocationTextColor(context, isLadyMode: isLadyMode),
                    ),
                  ],
                ),
              ),
            ),
          
          const SizedBox(height: 16),
          
          // Participant count
          Row(
            children: [
              Icon(
                Icons.people,
                size: 20,
                color: (isLadyMode ? AppColors.ladyPrimary : AppColors.primary),
              ),
              const SizedBox(width: 8),
              Text(
                '${event.participantCount} participant${event.participantCount != 1 ? 's' : ''}',
                style: AppTextStyles.bodyLarge.copyWith(
                  color: (isLadyMode ? AppColors.ladyPrimary : AppColors.primary),
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (event.maxParticipants != null)
                Text(
                  ' / ${event.maxParticipants} max',
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsTab(Event event, List<EventParticipant> participants) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    bool isLadyMode = false;
    final authState = context.read<AuthBloc>().state;
    if (authState is Authenticated) {
      isLadyMode = authState.user.gender == 'female';
    }
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Description
          if (event.description != null && event.description!.isNotEmpty) ...[
            Text(
              'Description',
              style: AppTextStyles.titleMedium.copyWith(
                color: isDarkMode ? Colors.white : (isLadyMode ? AppColors.ladyPrimary : AppColors.primary),
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              event.description!,
              style: AppTextStyles.bodyLarge.copyWith(
                color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
              ),
            ),
            const SizedBox(height: 24),
          ],
          
          // Event details
          _buildEventDetailsSection(event, isDarkMode, isLadyMode),
          
          const SizedBox(height: 24),
          
          // Participants list
          _buildParticipantsSection(participants, isDarkMode),
        ],
      ),
    );
  }

  Widget _buildEventDetailsSection(Event event, bool isDarkMode, bool isLadyMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Event Details',
          style: AppTextStyles.titleMedium.copyWith(
            color: isDarkMode ? Colors.white : (isLadyMode ? AppColors.ladyPrimary : AppColors.primary),
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        
        _buildDetailRow(
          Icons.timer,
          'Duration',
          '${event.durationMinutes} minutes',
          isDarkMode,
        ),
        
        if (event.difficultyLevel != null)
          _buildDetailRow(
            Icons.trending_up,
            'Difficulty',
            'Level ${event.difficultyLevel}',
            isDarkMode,
          ),
        
        if (event.ruckWeightKg != null)
          _buildDetailRow(
            Icons.fitness_center,
            'Recommended Weight',
            '${event.ruckWeightKg}kg',
            isDarkMode,
          ),
        
        if (event.minParticipants != null && event.minParticipants! > 1)
          _buildDetailRow(
            Icons.group,
            'Minimum Participants',
            '${event.minParticipants}',
            isDarkMode,
          ),
        
        if (event.approvalRequired)
          _buildDetailRow(
            Icons.check_circle,
            'Approval Required',
            'Yes',
            isDarkMode,
          ),
      ],
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value, bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: AppTextStyles.bodyMedium.copyWith(
              color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: AppTextStyles.bodyMedium.copyWith(
              color: isDarkMode ? Colors.white : Theme.of(context).primaryColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantsSection(List<EventParticipant> participants, bool isDarkMode) {
    final approvedParticipants = participants.where((p) => p.isApproved).toList();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Participants',
          style: AppTextStyles.titleMedium.copyWith(
            color: isDarkMode ? Colors.white : Theme.of(context).primaryColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        
        if (approvedParticipants.isEmpty)
          Text(
            'No participants yet',
            style: AppTextStyles.bodyMedium.copyWith(
              color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
            ),
          )
        else
          ...approvedParticipants.map((participant) => _buildParticipantRow(participant, isDarkMode)),
      ],
    );
  }

  Widget _buildParticipantRow(EventParticipant participant, bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
            backgroundImage: participant.user?.avatarUrl != null && participant.user!.avatarUrl!.isNotEmpty
                ? NetworkImage(participant.user!.avatarUrl!)
                : null,
            child: participant.user?.avatarUrl == null || participant.user!.avatarUrl!.isEmpty
                ? Text(
                    (participant.user?.username.isNotEmpty == true 
                        ? participant.user!.username[0].toUpperCase()
                        : '?'),
                    style: AppTextStyles.bodySmall.copyWith(
                      color: Theme.of(context).primaryColor,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              participant.user?.username ?? 'Unknown User',
              style: AppTextStyles.bodyMedium.copyWith(
                color: isDarkMode ? Colors.white : Theme.of(context).primaryColor,
              ),
            ),
          ),
          Text(
            DateFormat('MMM d').format(participant.joinedAt),
            style: AppTextStyles.bodySmall.copyWith(
              color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(Event event) {
    if (event.userParticipationStatus != null) {
      Color badgeColor;
      String badgeText;
      
      switch (event.userParticipationStatus) {
        case 'approved':
          badgeColor = Colors.green;
          badgeText = 'Joined';
          break;
        case 'pending':
          badgeColor = Colors.orange;
          badgeText = 'Pending';
          break;
        case 'rejected':
          badgeColor = Colors.red;
          badgeText = 'Rejected';
          break;
        default:
          return const SizedBox.shrink();
      }
      
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: badgeColor.withOpacity(0.1),
          border: Border.all(color: badgeColor.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          badgeText,
          style: AppTextStyles.bodySmall.copyWith(
            color: badgeColor,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }
    
    return const SizedBox.shrink();
  }

  Widget? _buildBottomActionBar() {
    if (_eventDetails == null) return null;
    
    final event = _eventDetails!.event;
    
    if (event.isPast || event.isCancelled) {
      return null;
    }
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(
            color: Colors.grey.withOpacity(0.2),
          ),
        ),
      ),
      child: SafeArea(
        child: _buildActionButton(event),
      ),
    );
  }

  Widget _buildActionButton(Event event) {
    if (event.isUserApproved && event.canStartRuck) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () {
            _eventsBloc.add(StartRuckFromEvent(event.id));
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: const Text('Start Ruck Session'),
        ),
      );
    }
    
    if (event.canJoin) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: event.isFull ? null : () {
            _eventsBloc.add(JoinEvent(event.id));
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: Text(event.isFull ? 'Event Full' : 'Join Event'),
        ),
      );
    }
    
    if (event.canLeave) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: () {
            _eventsBloc.add(LeaveEvent(event.id));
          },
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Colors.red),
            foregroundColor: Colors.red,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: const Text('Leave Event'),
        ),
      );
    }
    
    return const SizedBox.shrink();
  }

  void _showCancelConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Event'),
        content: const Text('Are you sure you want to cancel this event? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _eventsBloc.add(CancelEvent(widget.eventId));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Cancel Event'),
          ),
        ],
      ),
    );
  }

  String _formatEventDateTime(DateTime startTime, int durationMinutes) {
    final now = DateTime.now();
    final endTime = startTime.add(Duration(minutes: durationMinutes));
    
    if (startTime.year == now.year && 
        startTime.month == now.month && 
        startTime.day == now.day) {
      return 'Today ${DateFormat('h:mm a').format(startTime)} - ${DateFormat('h:mm a').format(endTime)}';
    } else {
      return '${DateFormat('MMM d, y').format(startTime)} ${DateFormat('h:mm a').format(startTime)} - ${DateFormat('h:mm a').format(endTime)}';
    }
  }

  void _openLocation(String locationName, double? latitude, double? longitude) async {
    try {
      final encodedLocation = Uri.encodeComponent(locationName);
      String url;
      
      // If we have coordinates, use them for more precise location
      if (latitude != null && longitude != null) {
        // Google Maps with coordinates
        url = 'https://www.google.com/maps/search/?api=1&query=$encodedLocation&center=$latitude,$longitude';
      } else {
        // Fallback to search by name only
        url = 'https://www.google.com/maps/search/?api=1&query=$encodedLocation';
      }
      
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        // Fallback to platform-specific maps
        String fallbackUrl;
        if (Theme.of(context).platform == TargetPlatform.iOS) {
          // Apple Maps
          if (latitude != null && longitude != null) {
            fallbackUrl = 'http://maps.apple.com/?q=$encodedLocation&ll=$latitude,$longitude';
          } else {
            fallbackUrl = 'http://maps.apple.com/?q=$encodedLocation';
          }
        } else {
          // Generic maps URL for Android
          fallbackUrl = 'geo:0,0?q=$encodedLocation';
        }
        
        if (await canLaunchUrl(Uri.parse(fallbackUrl))) {
          await launchUrl(Uri.parse(fallbackUrl), mode: LaunchMode.externalApplication);
        } else {
          // Show error to user
          if (mounted) {
            StyledSnackBar.showError(
              context: context,
              message: 'Unable to open maps. Please check your location manually.',
            );
          }
        }
      }
    } catch (e) {
      // Show error to user
      if (mounted) {
        StyledSnackBar.showError(
          context: context,
          message: 'Unable to open maps. Please check your location manually.',
        );
      }
    }
  }

  void _shareEvent(Event event) async {
    await EventShareService.shareEvent(event);
  }
}
