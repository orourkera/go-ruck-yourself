import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:rucking_app/core/services/service_locator.dart';
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
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/skeleton/skeleton_widgets.dart';
import 'package:rucking_app/shared/widgets/error_display.dart';

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
    
    // Load event details and related data
    _eventsBloc.add(LoadEventDetails(widget.eventId));
    _commentsBloc.add(LoadEventComments(widget.eventId));
    _progressBloc.add(LoadEventLeaderboard(widget.eventId));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
        appBar: AppBar(
          title: Text(
            _eventDetails?.event.title ?? 'Event Details',
            style: AppTextStyles.titleLarge.copyWith(
              color: Theme.of(context).brightness == Brightness.dark 
                  ? Colors.white 
                  : AppColors.textDark,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: _buildAppBarActions(),
        ),
        body: BlocConsumer<EventsBloc, EventsState>(
          listener: (context, state) {
            if (state is EventDetailsLoaded) {
              setState(() {
                _eventDetails = state.eventDetails;
              });
            } else if (state is EventActionSuccess) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.message),
                  backgroundColor: Colors.green,
                ),
              );
              
              if (state.shouldRefresh) {
                _eventsBloc.add(LoadEventDetails(widget.eventId));
                _progressBloc.add(LoadEventLeaderboard(widget.eventId));
              }
              
              // Handle navigation after starting ruck session
              if (state.sessionId != null) {
                Navigator.of(context).pushReplacementNamed(
                  '/active_session',
                  arguments: state.sessionId,
                );
              }
            } else if (state is EventActionError) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.message),
                  backgroundColor: Colors.red,
                ),
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
    if (_eventDetails?.event.isCreator == true) {
      return [
        IconButton(
          icon: const Icon(Icons.edit),
          onPressed: () {
            Navigator.of(context).pushNamed(
              '/edit_event',
              arguments: widget.eventId,
            ).then((_) {
              _eventsBloc.add(LoadEventDetails(widget.eventId));
            });
          },
        ),
        PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'cancel') {
              _showCancelConfirmation();
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'cancel',
              child: Text('Cancel Event'),
            ),
          ],
        ),
      ];
    }
    return [];
  }

  Widget _buildLoadingSkeleton() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner skeleton
          const SkeletonRectangle(height: 200, width: double.infinity),
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
    
    return Column(
      children: [
        // Event header
        _buildEventHeader(event, isDarkMode),
        
        // Tab bar for content sections
        TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: isDarkMode ? Colors.grey[400] : Colors.grey[600],
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Details'),
            Tab(text: 'Leaderboard'),
            Tab(text: 'Comments'),
          ],
        ),
        
        // Tab content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildDetailsTab(event, eventDetails.participants),
              EventLeaderboardWidget(eventId: widget.eventId),
              EventCommentsSection(eventId: widget.eventId),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEventHeader(Event event, bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner image if available
          if (event.bannerImageUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                event.bannerImageUrl!,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    height: 200,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.event,
                        size: 60,
                        color: AppColors.primary,
                      ),
                    ),
                  );
                },
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
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.groups,
                    size: 24,
                    color: AppColors.primary,
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
                      style: AppTextStyles.headlineSmall.copyWith(
                        color: isDarkMode ? Colors.white : AppColors.textDark,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (event.hostingClub != null)
                      Text(
                        event.hostingClub!.name,
                        style: AppTextStyles.bodyLarge.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      )
                    else if (event.creator != null)
                      Text(
                        'Organized by ${event.creator!.fullName}',
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
            Row(
              children: [
                Icon(
                  Icons.location_on,
                  size: 20,
                  color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    event.locationName!,
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                    ),
                  ),
                ),
              ],
            ),
          
          const SizedBox(height: 16),
          
          // Participant count
          Row(
            children: [
              Icon(
                Icons.people,
                size: 20,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '${event.participantCount} participant${event.participantCount != 1 ? 's' : ''}',
                style: AppTextStyles.bodyLarge.copyWith(
                  color: AppColors.primary,
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
                color: isDarkMode ? Colors.white : AppColors.textDark,
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
          _buildEventDetailsSection(event, isDarkMode),
          
          const SizedBox(height: 24),
          
          // Participants list
          _buildParticipantsSection(participants, isDarkMode),
        ],
      ),
    );
  }

  Widget _buildEventDetailsSection(Event event, bool isDarkMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Event Details',
          style: AppTextStyles.titleMedium.copyWith(
            color: isDarkMode ? Colors.white : AppColors.textDark,
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
              color: isDarkMode ? Colors.white : AppColors.textDark,
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
            color: isDarkMode ? Colors.white : AppColors.textDark,
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
            backgroundColor: AppColors.primary.withOpacity(0.1),
            child: Text(
              (participant.user?.firstName.isNotEmpty == true 
                  ? participant.user!.firstName[0].toUpperCase()
                  : '?'),
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              participant.user?.fullName ?? 'Unknown User',
              style: AppTextStyles.bodyMedium.copyWith(
                color: isDarkMode ? Colors.white : AppColors.textDark,
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
    if (event.isUserApproved && event.isUpcoming) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () {
            _eventsBloc.add(StartRuckFromEvent(event.id));
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
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
            backgroundColor: AppColors.primary,
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
}
