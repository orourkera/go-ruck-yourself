import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/events/domain/models/event_progress.dart';
import 'package:rucking_app/features/events/presentation/bloc/event_progress_bloc.dart';
import 'package:rucking_app/features/events/presentation/bloc/event_progress_event.dart';
import 'package:rucking_app/features/events/presentation/bloc/event_progress_state.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/skeleton/skeleton_loader.dart';
import 'package:rucking_app/shared/widgets/skeleton/skeleton_widgets.dart';
import 'package:rucking_app/shared/widgets/error_display.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/core/utils/measurement_utils.dart';

class EventLeaderboardWidget extends StatefulWidget {
  final String eventId;

  const EventLeaderboardWidget({
    Key? key,
    required this.eventId,
  }) : super(key: key);

  @override
  State<EventLeaderboardWidget> createState() => _EventLeaderboardWidgetState();
}

class _EventLeaderboardWidgetState extends State<EventLeaderboardWidget> {
  String _sortBy = 'distance'; // 'distance', 'time', 'sessions'

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Column(
      children: [
        // Sort options
        _buildSortOptions(isDarkMode),
        
        // Leaderboard content
        Expanded(
          child: BlocBuilder<EventProgressBloc, EventProgressState>(
            builder: (context, state) {
              if (state is EventLeaderboardLoading) {
                return _buildLoadingSkeleton();
              } else if (state is EventLeaderboardError) {
                return ErrorDisplay(
                  message: state.message,
                  onRetry: () {
                    context.read<EventProgressBloc>().add(
                      LoadEventLeaderboard(widget.eventId),
                    );
                  },
                );
              } else if (state is EventLeaderboardLoaded) {
                return _buildLeaderboard(state.leaderboard, isDarkMode);
              }
              
              return _buildLoadingSkeleton();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSortOptions(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Text(
            'Sort by:',
            style: AppTextStyles.bodyMedium.copyWith(
              color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          const SizedBox(width: 12),
          
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildSortChip('distance', 'Distance', isDarkMode),
                  const SizedBox(width: 8),
                  _buildSortChip('time', 'Time', isDarkMode),
                  const SizedBox(width: 8),
                  _buildSortChip('sessions', 'Sessions', isDarkMode),
                ],
              ),
            ),
          ),
          
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context.read<EventProgressBloc>().add(
                RefreshEventLeaderboard(widget.eventId),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSortChip(String value, String label, bool isDarkMode) {
    final isSelected = _sortBy == value;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _sortBy = value;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected 
              ? Theme.of(context).primaryColor 
              : Colors.transparent,
          border: Border.all(
            color: isSelected 
                ? Theme.of(context).primaryColor 
                : Colors.grey.withOpacity(0.3),
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            color: isSelected 
                ? Colors.white 
                : isDarkMode 
                    ? Colors.white 
                    : Colors.black87,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingSkeleton() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              const SkeletonCircle(size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonLine(width: 120),
                    SizedBox(height: 4),
                    SkeletonLine(width: 80),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: const [
                  SkeletonLine(width: 60),
                  SizedBox(height: 4),
                  SkeletonLine(width: 40),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLeaderboard(EventLeaderboard leaderboard, bool isDarkMode) {
    List<EventProgress> sortedEntries;
    
    switch (_sortBy) {
      case 'distance':
        sortedEntries = leaderboard.leaderboardByDistance;
        break;
      case 'time':
        sortedEntries = leaderboard.leaderboardByTime;
        break;
      case 'sessions':
        sortedEntries = leaderboard.leaderboardBySessionCount;
        break;
      default:
        sortedEntries = leaderboard.leaderboardByDistance;
    }
    
    if (sortedEntries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.leaderboard,
              size: 80,
              color: Colors.grey.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No progress yet',
              style: AppTextStyles.titleMedium.copyWith(
                color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Join the event and start rucking to see your progress!',
              style: AppTextStyles.bodyMedium.copyWith(
                color: isDarkMode ? Colors.grey[500] : Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    
    return RefreshIndicator(
      onRefresh: () async {
        context.read<EventProgressBloc>().add(
          RefreshEventLeaderboard(widget.eventId),
        );
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: sortedEntries.length,
        itemBuilder: (context, index) {
          final entry = sortedEntries[index];
          final rank = index + 1;
          
          return _buildLeaderboardEntry(entry, rank, isDarkMode);
        },
      ),
    );
  }

  Widget _buildLeaderboardEntry(EventProgress entry, int rank, bool isDarkMode) {
    // Get user's metric preference from auth bloc
    final authState = context.read<AuthBloc>().state;
    final preferMetric = authState is Authenticated ? authState.user.preferMetric : true;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.black : null,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey.withOpacity(0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Rank badge
          _buildRankBadge(rank, isDarkMode),
          
          const SizedBox(width: 12),
          
          // User avatar
          CircleAvatar(
            radius: 20,
            backgroundColor: Colors.grey[300],
            backgroundImage: entry.user?.avatar != null && entry.user!.avatar!.isNotEmpty
                ? NetworkImage(entry.user!.avatar!)
                : null,
            child: entry.user?.avatar == null || entry.user!.avatar!.isEmpty
                ? Icon(
                    Icons.person,
                    color: Colors.grey[600],
                    size: 20,
                  )
                : null,
          ),
          
          const SizedBox(width: 12),
          
          // User info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.user?.fullName ?? 'Unknown User',
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: isDarkMode ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${entry.sessionCount} session${entry.sessionCount != 1 ? 's' : ''}',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          
          // Progress stats
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                entry.formattedTotalDistance(metric: preferMetric),
                style: AppTextStyles.bodyLarge.copyWith(
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                entry.formattedTotalTime,
                style: AppTextStyles.bodySmall.copyWith(
                  color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
              if (entry.averagePaceMinutesPerKm > 0) ...[
                const SizedBox(height: 2),
                Text(
                  MeasurementUtils.formatPaceSeconds(entry.averagePaceMinutesPerKm * 60, metric: preferMetric),
                  style: AppTextStyles.bodySmall.copyWith(
                    color: isDarkMode ? Colors.grey[500] : Colors.grey[500],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRankBadge(int rank, bool isDarkMode) {
    Color badgeColor;
    Color textColor;
    
    if (rank == 1) {
      badgeColor = const Color(0xFFFFD700); // Gold
      textColor = Colors.black;
    } else if (rank == 2) {
      badgeColor = const Color(0xFFC0C0C0); // Silver
      textColor = Colors.black;
    } else if (rank == 3) {
      badgeColor = const Color(0xFFCD7F32); // Bronze
      textColor = Colors.white;
    } else {
      badgeColor = isDarkMode ? Colors.grey[700]! : Colors.grey[200]!;
      textColor = isDarkMode ? Colors.white : Colors.black87;
    }
    
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: badgeColor,
        shape: BoxShape.circle,
        border: rank <= 3 
            ? Border.all(color: Colors.white, width: 2)
            : null,
      ),
      child: Center(
        child: Text(
          rank.toString(),
          style: AppTextStyles.bodyMedium.copyWith(
            color: textColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
