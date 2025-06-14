import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/core/services/service_locator.dart';
import 'package:rucking_app/features/events/domain/models/event.dart';
import 'package:rucking_app/features/events/presentation/bloc/events_bloc.dart';
import 'package:rucking_app/features/events/presentation/bloc/events_event.dart';
import 'package:rucking_app/features/events/presentation/bloc/events_state.dart';
import 'package:rucking_app/features/events/presentation/widgets/event_card.dart';
import 'package:rucking_app/features/events/presentation/widgets/event_card_skeleton.dart';
import 'package:rucking_app/features/events/presentation/widgets/event_filter_chips.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/empty_state.dart';
import 'package:rucking_app/shared/widgets/error_display.dart';
import 'package:rucking_app/shared/widgets/skeleton/skeleton_loader.dart';
import 'package:rucking_app/shared/widgets/skeleton/skeleton_widgets.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({Key? key}) : super(key: key);

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  late EventsBloc _eventsBloc;
  final ScrollController _scrollController = ScrollController();
  
  @override
  void initState() {
    super.initState();
    _eventsBloc = getIt<EventsBloc>();
    
    // Schedule BLoC event for the first frame to avoid context access issues
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _eventsBloc.add(const LoadEvents());
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onFilterChanged(String? status, String? clubId, bool? includeParticipating) {
    _eventsBloc.add(LoadEvents(
      status: status,
      clubId: clubId,
      includeParticipating: includeParticipating,
    ));
  }

  void _navigateToEventDetails(String eventId) {
    Navigator.of(context).pushNamed('/event_detail', arguments: eventId);
  }

  void _navigateToCreateEvent() {
    Navigator.of(context).pushNamed('/create_event').then((_) {
      // Refresh events when returning from create screen
      _eventsBloc.add(RefreshEvents());
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _eventsBloc,
      child: Scaffold(
        backgroundColor: Theme.of(context).brightness == Brightness.dark 
            ? Colors.black 
            : AppColors.backgroundLight,
        appBar: AppBar(
          title: Text(
            'Events',
            style: AppTextStyles.titleLarge.copyWith(
              color: Theme.of(context).brightness == Brightness.dark 
                  ? Colors.white 
                  : AppColors.textDark,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: Icon(
                Icons.add,
                color: Theme.of(context).brightness == Brightness.dark 
                    ? Colors.white 
                    : AppColors.textDark,
              ),
              onPressed: _navigateToCreateEvent,
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 12),
              
              // Filter chips for event status
              BlocBuilder<EventsBloc, EventsState>(
                builder: (context, state) {
                  String? currentStatus;
                  String? currentClubId;
                  bool? currentIncludeParticipating;
                  
                  // Extract current filters from state if available
                  if (state is EventsLoaded) {
                    currentStatus = state.status;
                    currentClubId = state.clubId;
                    currentIncludeParticipating = state.includeParticipating;
                  }
                  
                  return EventFilterChips(
                    selectedStatus: currentStatus,
                    selectedClubId: currentClubId,
                    includeParticipating: currentIncludeParticipating,
                    onFilterChanged: _onFilterChanged,
                  );
                },
              ),
              
              const SizedBox(height: 8),
              
              // Main content area
              Expanded(
                child: BlocConsumer<EventsBloc, EventsState>(
                  listener: (context, state) {
                    if (state is EventsError) {
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(content: Text(state.message)),
                        );
                    } else if (state is EventActionSuccess) {
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(content: Text(state.message)),
                        );
                      
                      if (state.shouldRefresh) {
                        _eventsBloc.add(RefreshEvents());
                      }
                      
                      // Handle navigation after starting ruck session
                      if (state.sessionId != null) {
                        Navigator.of(context).pushReplacementNamed(
                          '/active_session', 
                          arguments: state.sessionId,
                        );
                      }
                    }
                  },
                  builder: (context, state) {
                    // Handle initial and loading states
                    if (state is EventsInitial || state is EventsLoading) {
                      return SingleChildScrollView(
                        child: Column(
                          children: List.generate(3, (index) => const EventCardSkeleton()),
                        ),
                      );
                    } 
                    // Handle loaded state with data
                    else if (state is EventsLoaded) {
                      final events = state.events;
                      
                      if (events.isEmpty) {
                        return EmptyState(
                          title: 'No Events Yet',
                          message: 'Be the first to create an event in your area!',
                          action: ElevatedButton(
                            onPressed: _navigateToCreateEvent,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).primaryColor,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Create Event'),
                          ),
                        );
                      }
                      
                      return RefreshIndicator(
                        onRefresh: () async {
                          _eventsBloc.add(RefreshEvents());
                        },
                        child: ListView.builder(
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16.0),
                          itemCount: events.length,
                          itemBuilder: (context, index) {
                            final event = events[index];
                            return EventCard(
                              event: event,
                              onTap: () => _navigateToEventDetails(event.id),
                              onJoinTap: () {
                                _eventsBloc.add(JoinEvent(event.id));
                              },
                              onLeaveTap: () {
                                _eventsBloc.add(LeaveEvent(event.id));
                              },
                              onStartRuckTap: () {
                                _eventsBloc.add(StartRuckFromEvent(event.id));
                              },
                            );
                          },
                        ),
                      );
                    } else if (state is EventsError) {
                      return ErrorDisplay(
                        message: state.message,
                        onRetry: () {
                          _eventsBloc.add(const LoadEvents());
                        },
                      );
                    }
                    
                    // Fallback
                    return Column(
                      children: List.generate(3, (index) => const EventCardSkeleton()),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Skeleton widget for loading state
class EventCardSkeleton extends StatelessWidget {
  const EventCardSkeleton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title and club info skeleton
              Row(
                children: [
                  const SkeletonCircle(size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        SkeletonLine(width: 150),
                        SizedBox(height: 4),
                        SkeletonLine(width: 100),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              // Description skeleton
              const SkeletonLine(width: double.infinity),
              const SizedBox(height: 4),
              const SkeletonLine(width: 200),
              const SizedBox(height: 12),
              
              // Details skeleton
              Row(
                children: const [
                  SkeletonLine(width: 80),
                  SizedBox(width: 16),
                  SkeletonLine(width: 60),
                  Spacer(),
                  SkeletonLine(width: 40),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
