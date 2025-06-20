import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rucking_app/features/events/domain/models/event.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

class EventCard extends StatelessWidget {
  final Event event;
  final VoidCallback? onTap;
  final VoidCallback? onJoinTap;

  const EventCard({
    Key? key,
    required this.event,
    this.onTap,
    this.onJoinTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: GestureDetector(
        onTap: onTap,
        child: Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          color: isDarkMode ? Colors.black : null,
          child: Column(
            children: [
              // Banner image if available
              if (event.bannerImageUrl != null)
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                  child: Image.network(
                    event.bannerImageUrl!,
                    height: 120,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        height: 120,
                        width: double.infinity,
                        color: Theme.of(context).primaryColor.withOpacity(0.1),
                        child: Icon(
                          Icons.event,
                          size: 40,
                          color: Theme.of(context).primaryColor,
                        ),
                      );
                    },
                  ),
                ),
              
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header with title and club info
                    Row(
                      children: [
                        // Club logo or event icon
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: event.isClubEvent 
                                ? Theme.of(context).primaryColor.withOpacity(0.1) 
                                : Colors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            event.isClubEvent ? Icons.groups : Icons.event,
                            size: 20,
                            color: event.isClubEvent ? Theme.of(context).primaryColor : Colors.grey[600],
                          ),
                        ),
                        const SizedBox(width: 12),
                        
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                event.title,
                                style: AppTextStyles.titleMedium.copyWith(
                                  color: isDarkMode ? Colors.white : AppColors.textDark,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              if (event.hostingClub != null)
                                Text(
                                  event.hostingClub!.name,
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: Theme.of(context).primaryColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                                )
                              else if (event.creator != null)
                                Text(
                                  'by ${event.creator!.username}',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        
                        // Event status badge
                        _buildStatusBadge(context),
                      ],
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // Description if available
                    if (event.description != null && event.description!.isNotEmpty)
                      Column(
                        children: [
                          Text(
                            event.description!,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    
                    // Event details row
                    Row(
                      children: [
                        Icon(
                          Icons.schedule,
                          size: 16,
                          color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatDateTime(event.scheduledStartTime),
                          style: AppTextStyles.bodySmall.copyWith(
                            color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                        const SizedBox(width: 16),
                        
                        Icon(
                          Icons.timer,
                          size: 16,
                          color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${event.durationMinutes}min',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                        
                        if (event.locationName != null) ...[
                          const SizedBox(width: 16),
                          Icon(
                            Icons.location_on,
                            size: 16,
                            color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              event.locationName!,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // Participants and action buttons
                    Row(
                      children: [
                        // Participant count
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Theme.of(context).primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.people,
                                size: 14,
                                color: Theme.of(context).primaryColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${event.participantCount}',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: Theme.of(context).primaryColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (event.maxParticipants != null)
                                Text(
                                  '/${event.maxParticipants}',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: Theme.of(context).primaryColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        
                        const Spacer(),
                        
                        // Action buttons
                        _buildActionButtons(context),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: badgeColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
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

  Widget _buildActionButtons(BuildContext context) {
    final isUpcoming = event.isUpcoming;
    final canJoin = event.canJoin;
    
    if (event.isPast || event.isCancelled) {
      return const SizedBox.shrink();
    }
    
    if (canJoin && onJoinTap != null) {
      return ElevatedButton(
        onPressed: event.isFull ? null : onJoinTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(event.isFull ? 'Full' : 'Join'),
      );
    }
    
    return const SizedBox.shrink();
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = dateTime.difference(now);
    
    if (difference.inDays > 7) {
      return DateFormat('MMM d, y').format(dateTime);
    } else if (difference.inDays > 0) {
      return DateFormat('E, MMM d').format(dateTime);
    } else if (difference.inDays == 0) {
      return 'Today ${DateFormat('h:mm a').format(dateTime)}';
    } else {
      return DateFormat('MMM d, h:mm a').format(dateTime);
    }
  }
}
